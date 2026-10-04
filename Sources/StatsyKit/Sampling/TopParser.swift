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
    /// sample and carries no magnitude. Units match in either case, because
    /// procps writes them lower-case; a bare number is in `unscaled` bytes,
    /// which is 1 for macOS and 1024 for procps' `-e k`.
    public static func memoryBytes(_ token: String, unscaled: UInt64 = 1) -> UInt64? {
        var text = token.trimmingCharacters(in: .whitespaces)
        if text.hasSuffix("+") || text.hasSuffix("-") { text.removeLast() }
        guard !text.isEmpty else { return nil }

        var multiplier = unscaled
        switch text.last {
        case "K", "k": multiplier = 1024
        case "M", "m": multiplier = 1024 * 1024
        case "G", "g": multiplier = 1024 * 1024 * 1024
        case "T", "t": multiplier = 1024 * 1024 * 1024 * 1024
        default: break
        }
        if text.last?.isLetter == true { text.removeLast() }

        guard let value = Double(text), value >= 0 else { return nil }
        return UInt64(value * Double(multiplier))
    }
}

/// Which `top` is producing the stream: macOS's, or Linux procps'.
public enum TopDialect: Sendable, Equatable {
    case darwin
    case procps
}

/// Accumulates streamed `top` output and emits one batch per sampling block.
///
/// Streaming a single long-lived `top` avoids a fork/exec per refresh; `top`
/// itself costs about 9% of a core while sampling, which a monitor should not
/// pay repeatedly. Both dialects separate blocks the same way, with a header
/// line and a blank line around each table, so only the row format differs.
public struct TopStreamParser: Sendable {
    private enum Layout: Sendable {
        case darwin(TopParser.ColumnLayout)
        case procps(ProcpsTopParser.Layout)
    }

    private let dialect: TopDialect
    private var layout: Layout?
    private var rows: [ProcessSample] = []
    private var blocksSeen = 0

    /// `top`'s first block reports lifetime-average CPU rather than an interval
    /// delta — the same trap that makes `ps` unsuitable — so it is discarded.
    /// procps' first iteration has no earlier sample to difference against
    /// either, and is discarded for the same reason.
    public let skipFirstBlock: Bool

    public init(dialect: TopDialect = .darwin, skipFirstBlock: Bool = true) {
        self.dialect = dialect
        self.skipFirstBlock = skipFirstBlock
    }

    /// Feeds one line in. Returns a completed block when one ends.
    public mutating func consume(_ line: String) -> [ProcessSample]? {
        if let newLayout = header(line) {
            let finished = flush()
            layout = newLayout
            return finished
        }
        guard let layout else { return nil }
        // Checked on the bytes: trimming built a new string for every row.
        if line.utf8.allSatisfy({ $0 == 0x20 || $0 == 0x09 }) { return flush() }
        let sample: ProcessSample? = switch layout {
        case .darwin(let columns): TopParser.row(line, layout: columns)
        case .procps(let columns): ProcpsTopParser.row(line, layout: columns)
        }
        if let sample { rows.append(sample) }
        return nil
    }

    private func header(_ line: String) -> Layout? {
        switch dialect {
        case .darwin: TopParser.layout(header: line).map(Layout.darwin)
        case .procps: ProcpsTopParser.layout(header: line).map(Layout.procps)
        }
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
