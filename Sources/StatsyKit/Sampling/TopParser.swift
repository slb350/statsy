import Foundation

/// Parses the tabular output of `/usr/bin/top`.
///
/// `top` is setuid root, so it can see every process; an unprivileged call to
/// libproc cannot (it returns EPERM for the ~180 root-owned processes on this
/// machine, which include WindowServer and kernel_task). Parsing its output is
/// therefore the only way to rank all processes without a privileged helper.
///
/// Columns are located by their offsets in the header line rather than by
/// splitting on whitespace, because command names contain spaces
/// ("Google Chrome He", "Codex (Service)").
public enum TopParser {
    public struct ColumnLayout: Sendable, Equatable {
        /// Each column's character range, resolved once from the header.
        ///
        /// Resolved up front rather than per row: a `top` block is ~1050 rows,
        /// so searching for each field's neighbour on every row cost tens of
        /// thousands of string comparisons per sample.
        public let ranges: [String: Range<Int>]

        public init(ranges: [String: Range<Int>]) {
            self.ranges = ranges
        }
    }

    /// Derives column offsets from a `top` header line, or nil if not a header.
    public static func layout(header: String) -> ColumnLayout? {
        guard header.hasPrefix("PID"), header.contains("COMMAND") else { return nil }

        let characters = Array(header)
        var columns: [(name: String, start: Int)] = []
        var index = 0
        while index < characters.count {
            guard characters[index] != " " else {
                index += 1
                continue
            }
            let start = index
            while index < characters.count, characters[index] != " " { index += 1 }
            columns.append((String(characters[start..<index]), start))
        }

        var ranges: [String: Range<Int>] = [:]
        for (position, column) in columns.enumerated() {
            // The last column runs to the end of whatever row it is applied to.
            let end = position + 1 < columns.count ? columns[position + 1].start : Int.max
            ranges[column.name] = column.start..<end
        }
        return ColumnLayout(ranges: ranges)
    }

    /// Parses one table row, or nil if the line is not a process row.
    public static func row(_ line: String, layout: ColumnLayout) -> ProcessSample? {
        let characters = Array(line)
        guard !characters.isEmpty else { return nil }

        func field(_ name: String) -> String? {
            guard let range = layout.ranges[name], range.lowerBound < characters.count else {
                return nil
            }
            let end = min(range.upperBound, characters.count)
            guard end > range.lowerBound else { return nil }
            return String(characters[range.lowerBound..<end])
                .trimmingCharacters(in: .whitespaces)
        }

        guard let pidText = field("PID"), let pid = Int32(pidText) else { return nil }
        return ProcessSample(
            id: pid,
            name: field("COMMAND") ?? "",
            cpu: Double(field("%CPU") ?? "") ?? 0,
            memory: memoryBytes(field("MEM") ?? "") ?? 0
        )
    }

    /// Converts a `top` memory token ("7878M+", "20G", "3616K") to bytes.
    ///
    /// The trailing `+`/`-` marks which way the figure moved since the last
    /// sample and carries no magnitude.
    public static func memoryBytes(_ token: String) -> UInt64? {
        var text = token.trimmingCharacters(in: .whitespaces)
        if text.hasSuffix("+") || text.hasSuffix("-") { text.removeLast() }
        guard !text.isEmpty else { return nil }

        var multiplier: UInt64 = 1
        switch text.last {
        case "K": multiplier = 1024
        case "M": multiplier = 1024 * 1024
        case "G": multiplier = 1024 * 1024 * 1024
        case "T": multiplier = 1024 * 1024 * 1024 * 1024
        default: break
        }
        if multiplier > 1 { text.removeLast() }

        guard let value = Double(text), value >= 0 else { return nil }
        return UInt64(value * Double(multiplier))
    }
}

/// Accumulates `top -l 0` output and emits one batch per sampling block.
///
/// Streaming a single long-lived `top` avoids a fork/exec per refresh; `top`
/// itself costs about 9% of a core while sampling, which a monitor should not
/// pay repeatedly.
public struct TopStreamParser: Sendable {
    private var layout: TopParser.ColumnLayout?
    private var rows: [ProcessSample] = []
    private var blocksSeen = 0

    /// `top`'s first block reports lifetime-average CPU rather than an interval
    /// delta — the same trap that makes `ps` unsuitable — so it is discarded.
    public let skipFirstBlock: Bool

    public init(skipFirstBlock: Bool = true) {
        self.skipFirstBlock = skipFirstBlock
    }

    /// Feeds one line in. Returns a completed block when one ends.
    public mutating func consume(_ line: String) -> [ProcessSample]? {
        if let newLayout = TopParser.layout(header: line) {
            let finished = flush()
            layout = newLayout
            return finished
        }
        guard let layout else { return nil }
        if line.trimmingCharacters(in: .whitespaces).isEmpty { return flush() }
        if let sample = TopParser.row(line, layout: layout) { rows.append(sample) }
        return nil
    }

    private mutating func flush() -> [ProcessSample]? {
        guard !rows.isEmpty else { return nil }
        let block = rows
        rows = []
        blocksSeen += 1
        if skipFirstBlock, blocksSeen == 1 { return nil }
        return block
    }
}
