import Foundation

/// Samples a remote host by scraping its node_exporter through an SSH forward.
///
/// Acquisition only, in the same sense as the local sources: the arithmetic all
/// lives in `RemoteMapper`, which is pure and carries the tests. What this adds
/// is everything that can go wrong — a host that is asleep, a tunnel that dies,
/// a scrape that takes longer than the refresh interval.
public actor RemoteSnapshotProvider: SnapshotProvider {
    private let target: RemoteTarget
    private var mapper: RemoteMapper
    private let tunnel: SSHTunnel
    private let session: URLSession

    /// The last readings worth showing, and when they were read.
    private var last = Snapshot.placeholder
    private var lastSuccess: Date?
    private var failure: String?

    /// A remote host is polled at half the local rate. The panel is glanceable
    /// either way, and this halves both the round trips and the scrape load on
    /// the machine being measured.
    public nonisolated let refreshInterval = Duration.seconds(2)

    /// How long stale readings stay on screen before the panel admits it has
    /// nothing. Long enough to ride out one missed scrape and a tunnel restart,
    /// short enough that nobody reads a minute-old number as current.
    private static let staleLimit: TimeInterval = 30

    public init(target: RemoteTarget) {
        self.target = target
        self.mapper = RemoteMapper(target: target)
        self.tunnel = SSHTunnel(target: target)

        let configuration = URLSessionConfiguration.ephemeral
        // Bounded by the refresh interval: a request still in flight when the
        // next one is due is a request that has already failed.
        configuration.timeoutIntervalForRequest = 2
        configuration.timeoutIntervalForResource = 4
        // Loopback, and a fresh reading every time.
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        self.session = URLSession(configuration: configuration)
    }

    /// How long to wait for a newly started forward before giving up on it.
    /// SSH usually has it listening in well under a second.
    private static let tunnelTimeout = Duration.seconds(6)
    private static let tunnelPoll = Duration.milliseconds(250)

    /// Brings the forward up and takes the baseline scrape.
    ///
    /// The baseline matters for the same reason it does locally: utilisation
    /// and throughput are differences between two readings, and without a first
    /// one the panel opens on an idle machine with no cores. Waiting here costs
    /// a second at startup and saves showing a wrong number.
    public func start() async {
        // An earlier tunnel on this port is reused rather than replaced: it
        // forwards to the same host, and tearing it down would only mean
        // waiting for a new one to come up. Its response is the baseline, not
        // a probe to be thrown away and immediately re-fetched.
        if let text = await scrape() {
            ingest(text, at: Date())
            return
        }
        do { try tunnel.start() } catch { failure = error.localizedDescription }

        var waited = Duration.zero
        while waited < Self.tunnelTimeout {
            if let text = await scrape() {
                ingest(text, at: Date())
                return
            }
            try? await Task.sleep(for: Self.tunnelPoll)
            waited += Self.tunnelPoll
        }
    }

    public func stop() async {
        tunnel.stop()
        // Switching target builds a new provider and drops this one. Without
        // this its connection pool, loopback socket and delegate queue outlive
        // it, and the count grows with every switch.
        session.finishTasksAndInvalidate()
    }

    public func sample() async -> Snapshot {
        let now = Date()

        guard let text = await scrape() else {
            // A dead tunnel is the usual reason, and restarting it costs
            // nothing when it is already up.
            if !tunnel.isRunning {
                do { try tunnel.start() } catch { failure = error.localizedDescription }
            }
            last = last.marking(degraded(at: now))
            return last
        }

        ingest(text, at: now)
        return last
    }

    /// Folds a successful scrape in. The one place a reading is accepted.
    private func ingest(_ text: String, at now: Date) {
        lastSuccess = now
        failure = nil
        last = mapper.snapshot(
            from: MetricSet(text: text, wanted: mapper.wants),
            now: now,
            link: LinkStatus(state: .live)
        )
    }

    /// What to tell the panel when a scrape has just failed.
    private func degraded(at now: Date) -> LinkStatus {
        guard let lastSuccess else {
            return LinkStatus(state: .down, detail: failure ?? "No connection")
        }
        let age = now.timeIntervalSince(lastSuccess)
        return LinkStatus(
            state: age > Self.staleLimit ? .down : .stale,
            age: age,
            detail: failure
        )
    }

    /// One scrape, or nil if it did not arrive intact.
    private func scrape() async -> String? {
        guard let url = target.metricsURL else { return nil }
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                failure = "Exporter returned \((response as? HTTPURLResponse)?.statusCode ?? 0)"
                return nil
            }
            return String(data: data, encoding: .utf8)
        } catch {
            failure = error.localizedDescription
            return nil
        }
    }
}
