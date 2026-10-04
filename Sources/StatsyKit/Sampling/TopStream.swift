import Foundation

/// One long-lived `top`, local or behind ssh, parsed a block at a time.
///
/// Shared by `TopProcessSource` and `RemoteProcessSource`, which differ only
/// in what they launch and in when they relaunch it.
enum TopStream {
    /// Launches `executable` and hands each completed block to `onBlock`,
    /// then an empty block once the stream ends: a `top` that has exited has
    /// nothing current to say, and an empty list beats one frozen at whatever
    /// the machine was doing last.
    static func launch(
        _ executable: String, arguments: [String], dialect: TopDialect,
        onBlock: @escaping @Sendable ([ProcessSample]) async -> Void
    ) throws -> (process: Process, reader: Task<Void, Never>) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()

        let handle = pipe.fileHandleForReading
        let reader = Task {
            var parser = TopStreamParser(dialect: dialect)
            do {
                for try await line in handle.bytes.lines {
                    guard let block = parser.consume(line) else { continue }
                    await onBlock(block)
                }
            } catch {
                // The pipe closes when the process exits.
            }
            await onBlock([])
        }
        return (process, reader)
    }
}
