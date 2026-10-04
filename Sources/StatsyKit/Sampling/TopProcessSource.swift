import Foundation

/// Supplies the raw process samples the panel ranks.
///
/// Deliberately unranked: ranking is a pure transformation and belongs with the
/// other calculators in `MetricsEngine`, so an alternative source (a privileged
/// helper, say) only has to acquire samples, not reimplement the policy.
public protocol ProcessSource: Sendable {
    func start() async
    func stop() async
    func current() async -> [ProcessSample]
}

/// Ranks processes by streaming a single long-lived `/usr/bin/top`.
///
/// `top` is setuid root and so sees every process, which an unprivileged
/// libproc sweep cannot: on this machine roughly 180 of 1050 processes are
/// root-owned, and they include WindowServer and kernel_task — routinely the
/// largest consumers. Streaming one process rather than spawning one per
/// refresh keeps the cost to a single fork for the lifetime of the app.
///
/// Replacing this with a privileged XPC helper later means conforming that
/// helper to `ProcessSource`; nothing above this layer changes.
public actor TopProcessSource: ProcessSource {
    private let interval: Int
    private var process: Process?
    private var reader: Task<Void, Never>?
    private var samples: [ProcessSample] = []

    public init(interval: Int = 2) {
        self.interval = interval
    }

    public func current() -> [ProcessSample] { samples }

    /// `top`'s arguments: every process (ranking by memory needs the whole
    /// list, not just the head of the CPU ordering), four columns, a block
    /// every `interval` seconds. A remote Mac streams exactly these.
    static func arguments(interval: Int) -> [String] {
        ["-l", "0", "-s", "\(interval)", "-stats", "pid,command,cpu,mem", "-n", "9999"]
    }

    public func start() {
        guard process == nil else { return }
        guard let stream = try? TopStream.launch(
            "/usr/bin/top", arguments: Self.arguments(interval: interval), dialect: .darwin,
            onBlock: { [weak self] block in await self?.ingest(block) }
        ) else { return }
        process = stream.process
        reader = stream.reader
    }

    public func stop() {
        reader?.cancel()
        reader = nil
        process?.terminate()
        process = nil
    }

    private func ingest(_ block: [ProcessSample]) {
        samples = block
    }
}
