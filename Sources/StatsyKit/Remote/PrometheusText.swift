import Foundation

/// One line of a Prometheus exposition response.
public struct MetricSample: Sendable, Equatable {
    public let name: String
    public let labels: [String: String]
    public let value: Double

    public init(name: String, labels: [String: String] = [:], value: Double) {
        self.name = name
        self.labels = labels
        self.value = value
    }
}

/// Reads the Prometheus text exposition format that node_exporter serves.
///
/// Hand-written rather than regex-driven because label values are quoted and
/// may contain the separators: the fleet collector reports the DondeNAS mount
/// as `source="dondenas.local:/volume3/Donde Nas"`, which any split on
/// whitespace or commas would truncate. A line it cannot read is dropped rather
/// than failing the scrape — one malformed series should not blank the panel.
public enum PrometheusText {
    /// Parses a scrape, keeping only the series `wanted` accepts.
    ///
    /// The filter is applied after the metric name and before the label block,
    /// which is where nearly all the work is. A node_exporter scrape is around
    /// 2,800 series and the mapper reads about forty of them; parsing labels
    /// for `go_*`, `promhttp_*` and 144 lines of `node_schedstat_*` is most of
    /// the cost of a scrape and all of it is thrown away.
    public static func parse(
        _ text: String, wanted: (String) -> Bool = { _ in true }
    ) -> [MetricSample] {
        // Lines are found over the UTF-8 view: `split(separator:)` walks the
        // whole payload by grapheme cluster, and four fifths of it is about to
        // be dropped by name. Newlines are always character boundaries, so the
        // indices are valid for slicing the string itself.
        var samples: [MetricSample] = []
        samples.reserveCapacity(1024)
        let bytes = text.utf8
        var start = bytes.startIndex
        while start < bytes.endIndex {
            let end = bytes[start...].firstIndex(of: UInt8(ascii: "\n")) ?? bytes.endIndex
            if start < end, let sample = sample(from: text[start..<end], wanted: wanted) {
                samples.append(sample)
            }
            start = end < bytes.endIndex ? bytes.index(after: end) : bytes.endIndex
        }
        return samples
    }

    /// The raw lines of the series `wanted` accepts, comments dropped.
    ///
    /// How a fixture is cut from a live scrape: the same filter the mapper
    /// applies, so a capture keeps exactly what the mapper reads, byte for
    /// byte as the exporter wrote it.
    public static func lines(_ text: String, wanted: (String) -> Bool) -> [Substring] {
        text.split(separator: "\n").filter { line in
            seriesName(of: line).map { wanted(String($0)) } ?? false
        }
    }

    /// A line's metric name, or nil for a comment, a blank or a nameless line.
    /// The one rule `parse` and `lines` both apply, so a fixture keeps exactly
    /// the lines a live scrape would parse.
    private static func seriesName(of line: Substring) -> Substring? {
        let rest = line.drop(while: \.isWhitespace)
        guard let first = rest.first, first != "#",
              let end = rest.firstIndex(where: { $0 == "{" || $0.isWhitespace })
        else { return nil }
        let name = rest[..<end]
        return name.isEmpty ? nil : name
    }

    private static func sample(
        from line: Substring, wanted: (String) -> Bool
    ) -> MetricSample? {
        guard let found = seriesName(of: line) else { return nil }
        let name = String(found)
        guard wanted(name) else { return nil }
        var rest = line[found.endIndex...]

        var labels: [String: String] = [:]
        if rest.first == "{" {
            guard let block = labelBlock(from: rest.dropFirst()) else { return nil }
            labels = block.labels
            rest = block.rest
        }

        // A timestamp may follow the value; the scrape is current, so it is
        // ignored. Scanned rather than split: splitting allocates an array per
        // line to read its first element.
        let field = rest.drop(while: \.isWhitespace).prefix { !$0.isWhitespace }
        guard !field.isEmpty, let value = number(field) else { return nil }
        return MetricSample(name: name, labels: labels, value: value)
    }

    /// Scans to the closing brace, returning the labels and what follows it.
    ///
    /// Nil when the block never closes or a value is unquoted, which is the
    /// only way a truncated response can look like a valid short one.
    private static func labelBlock(from input: Substring) -> (labels: [String: String], rest: Substring)? {
        var labels: [String: String] = [:]
        var index = input.startIndex

        while index < input.endIndex {
            while index < input.endIndex, input[index] == "," || input[index].isWhitespace {
                index = input.index(after: index)
            }
            if index < input.endIndex, input[index] == "}" {
                return (labels, input[input.index(after: index)...])
            }

            guard let equals = input[index...].firstIndex(of: "=") else { return nil }
            let key = String(input[index..<equals])

            var cursor = input.index(after: equals)
            guard cursor < input.endIndex, input[cursor] == "\"" else { return nil }
            cursor = input.index(after: cursor)

            var value = ""
            var closed = false
            while cursor < input.endIndex {
                let character = input[cursor]
                if character == "\\" {
                    let escaped = input.index(after: cursor)
                    guard escaped < input.endIndex else { return nil }
                    value.append(unescape(input[escaped]))
                    cursor = input.index(after: escaped)
                    continue
                }
                cursor = input.index(after: cursor)
                if character == "\"" {
                    closed = true
                    break
                }
                value.append(character)
            }
            guard closed else { return nil }

            labels[key] = value
            index = cursor
        }
        return nil
    }

    private static func unescape(_ character: Character) -> Character {
        switch character {
        case "n": "\n"
        case "\\": "\\"
        case "\"": "\""
        default: character
        }
    }

    /// Parses a sample value, including the three non-numeric forms the format
    /// allows. `Double.init` rejects the signed infinities.
    private static func number(_ field: Substring) -> Double? {
        switch field {
        case "NaN", "nan": .nan
        case "Inf", "+Inf", "inf", "+inf": .infinity
        case "-Inf", "-inf": -.infinity
        default: Double(field)
        }
    }
}
