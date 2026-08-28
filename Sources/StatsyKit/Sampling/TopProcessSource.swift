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

    public func start() {
        guard process == nil else { return }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/top")
        // -n 9999 asks for every process: ranking by memory needs the whole
        // list, not just the head of the CPU ordering.
        task.arguments = [
            "-l", "0", "-s", "\(interval)",
            "-stats", "pid,command,cpu,mem", "-n", "9999"
        ]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
        } catch {
            return
        }
        process = task

        let handle = pipe.fileHandleForReading
        reader = Task { [weak self] in
            var parser = TopStreamParser()
            do {
                for try await line in handle.bytes.lines {
                    guard let block = parser.consume(line) else { continue }
                    await self?.ingest(block)
                }
            } catch {
                // The pipe closes when top exits; nothing further to read.
            }
        }
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
