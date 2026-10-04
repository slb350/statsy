import Foundation

/// Parses the task table of Linux procps `top -b`.
///
/// The opposite trade from `TopParser`: procps right-aligns its numeric
/// columns, so header offsets do not line up with the values beneath them,
/// but every column before COMMAND is a single token. Splitting a row into
/// one field per header column, with whatever remains as the command, is
/// therefore exact, and keeps a thread-group name such as "Web Content" whole.
public enum ProcpsTopParser {
    /// PID is always the first column, which `layout(header:)` requires.
    public struct Layout: Sendable, Equatable {
        public let cpu: Int
        public let resident: Int
        /// Columns in the header, COMMAND last.
        public let count: Int
    }

    /// Finds the columns the panel reads, or nil if the line is not a header.
    public static func layout(header: String) -> Layout? {
        // Every line of the stream is offered as a header, so a row is turned
        // away before it is split: splitting it cost more than parsing it.
        guard header.drop(while: { $0 == " " }).hasPrefix("PID ") else { return nil }
        let names = header.split(separator: " ")
        guard names.last == "COMMAND",
              let cpu = names.firstIndex(of: "%CPU"),
              let resident = names.firstIndex(of: "RES")
        else { return nil }
        return Layout(cpu: cpu, resident: resident, count: names.count)
    }

    /// Parses one task row, or nil if the line is not one.
    public static func row(_ line: String, layout: Layout) -> ProcessSample? {
        let fields = line.split(
            separator: " ", maxSplits: layout.count - 1, omittingEmptySubsequences: true
        )
        guard fields.count == layout.count, let pid = Int32(fields[0]) else {
            return nil
        }
        return ProcessSample(
            id: pid,
            name: String(fields[layout.count - 1]),
            cpu: Double(fields[layout.cpu]) ?? 0,
            memory: residentBytes(String(fields[layout.resident])) ?? 0
        )
    }

    /// Converts a RES token to bytes. `-e k` makes a plain number kibibytes;
    /// a value too wide for its column is scaled anyway and carries a
    /// lower-case unit ("6.5g").
    public static func residentBytes(_ token: String) -> UInt64? {
        TopParser.memoryBytes(token, unscaled: 1024)
    }
}
