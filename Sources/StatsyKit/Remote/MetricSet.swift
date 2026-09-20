import Foundation

/// One scrape, indexed by metric name.
///
/// A scrape is ~2,800 series and the mapper asks for a few dozen of them, so
/// the samples are bucketed by name once rather than scanned per lookup.
public struct MetricSet: Sendable, Equatable {
    private let byName: [String: [MetricSample]]

    public init(_ samples: [MetricSample]) {
        byName = Dictionary(grouping: samples, by: \.name)
    }

    public init(text: String, wanted: (String) -> Bool = { _ in true }) {
        self.init(PrometheusText.parse(text, wanted: wanted))
    }

    public func samples(_ name: String) -> [MetricSample] {
        byName[name] ?? []
    }

    /// The value of the one series matching every given label.
    ///
    /// Nil rather than zero when the series is absent: a missing sensor and a
    /// sensor reading zero mean different things on the panel.
    public func value(_ name: String, _ labels: [String: String] = [:]) -> Double? {
        samples(name).first { sample in
            labels.allSatisfy { sample.labels[$0.key] == $0.value }
        }?.value
    }

    /// Every series of `name`, keyed by one of its label values.
    ///
    /// Series without that label are dropped. Where two share a key the last
    /// wins, which only happens when the exporter is emitting duplicates.
    public func grouped(_ name: String, by label: String) -> [String: Double] {
        var result: [String: Double] = [:]
        for sample in samples(name) {
            guard let key = sample.labels[label] else { continue }
            result[key] = sample.value
        }
        return result
    }
}
