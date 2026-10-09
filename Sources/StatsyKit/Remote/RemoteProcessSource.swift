import Foundation

/// Ranks a remote host's processes by streaming its `top` over SSH.
///
/// node_exporter publishes nothing per process, so this is the remote
/// counterpart of `TopProcessSource`: one long-lived `top` on the far side,
/// its table parsed here, nothing installed on the host. It costs the host
/// what `top` costs, measured at 0.36% of a core on strix and 0.86% on ai-1
/// at the 2 s interval, and runs only while a panel is pointed there.
///
/// If the panel dies, ssh dies with it, and the far `top` takes SIGPIPE on its
/// next write once sshd closes the channel — the same reasoning that keeps
/// the local `top` from outliving the panel.
public actor RemoteProcessSource: ProcessSource {
    private let target: RemoteTarget
    private var process: Process?
    private var reader: Task<Void, Never>?
    private var samples: [ProcessSample] = []
    private var startedAt: Date?
    /// Which stream a block came from, so a cancelled reader's last word
    /// cannot overwrite its replacement's.
    private var generation = 0

    /// How soon a dead stream may be restarted. ssh to a host that is down
    /// spends its whole connect timeout failing, and retrying on every 2 s
    /// sample would keep one such attempt permanently in flight.
    private static let restartInterval: TimeInterval = 15

    public init(target: RemoteTarget) {
        self.target = target
    }

    public func current() -> [ProcessSample] {
        if process?.isRunning != true,
           startedAt.map({ Date().timeIntervalSince($0) >= Self.restartInterval }) ?? true {
            launch()
        }
        return samples
    }

    public func start() {
        guard process == nil else { return }
        launch()
    }

    public func stop() {
        reader?.cancel()
        reader = nil
        process?.terminate()
        process = nil
        samples = []
    }

    private func launch() {
        stop()
        startedAt = Date()
        generation += 1
        let stream = generation
        guard let launched = try? TopStream.launch(
            "/usr/bin/ssh",
            arguments: ["-T"] + SSHOptions.unattended + [
                target.sshDestination, target.platform.topCommand
            ],
            dialect: target.platform.topDialect,
            onBlock: { [weak self] block in await self?.ingest(block, from: stream) }
        ) else { return }
        process = launched.process
        reader = launched.reader
    }

    private func ingest(_ block: [ProcessSample], from stream: Int) {
        guard stream == generation else { return }
        samples = block
    }
}

extension RemotePlatform {
    /// The far side's `top`, streaming a full table every 2 s to match the
    /// remote refresh interval.
    ///
    /// Linux: batch mode, wide enough that COMMAND is never cut, task memory
    /// in KiB, and the C locale so a decimal comma cannot reach the parser.
    /// macOS: the local panel's own arguments.
    var topCommand: String {
        switch self {
        case .linux: "LC_ALL=C exec top -b -d 2 -w 512 -e k"
        case .macOS:
            "exec /usr/bin/top " + TopProcessSource.arguments(interval: 2).joined(separator: " ")
        }
    }

    var topDialect: TopDialect {
        switch self {
        case .linux: .procps
        case .macOS: .darwin
        }
    }

    var processMemory: ProcessMemory {
        switch self {
        case .linux: .resident
        case .macOS: .footprint
        }
    }
}

/// ssh options shared by every unattended session the panel opens.
enum SSHOptions {
    static let unattended = [
        // Fail rather than prompt: there is no terminal to answer on.
        "-o", "BatchMode=yes",
        "-o", "ConnectTimeout=5",
        // Notice a host that has gone away within ~30s rather than hanging
        // on a dead TCP connection until the kernel gives up.
        "-o", "ServerAliveInterval=10",
        "-o", "ServerAliveCountMax=3"
    ]
}
