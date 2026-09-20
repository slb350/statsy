import Testing
@testable import StatsyKit

@Suite("Prometheus exposition parser")
struct PrometheusTextTests {
    @Test("reads a bare sample with no labels")
    func bareSample() {
        let samples = PrometheusText.parse("node_load1 0.42\n")
        #expect(samples.count == 1)
        #expect(samples[0].name == "node_load1")
        #expect(samples[0].labels.isEmpty)
        #expect(samples[0].value == 0.42)
    }

    @Test("skips HELP and TYPE comments")
    func comments() {
        let text = """
        # HELP node_load1 1m load average.
        # TYPE node_load1 gauge
        node_load1 0.42
        """
        #expect(PrometheusText.parse(text).count == 1)
    }

    @Test("reads labels")
    func labels() {
        let sample = PrometheusText.parse(#"node_cpu_seconds_total{cpu="7",mode="idle"} 12.5"#)[0]
        #expect(sample.labels == ["cpu": "7", "mode": "idle"])
        #expect(sample.value == 12.5)
    }

    /// The fleet collector reports the DondeNAS automount, whose source label
    /// carries a space. Splitting the label block on whitespace loses it.
    @Test("keeps a label value containing a space")
    func spaceInLabelValue() {
        let line = #"homelab_mount_present{fstype="nfs",mountpoint="/mnt/nas-storage",source="dondenas.local:/volume3/Donde Nas"} 1"#
        let sample = PrometheusText.parse(line)[0]
        #expect(sample.labels["source"] == "dondenas.local:/volume3/Donde Nas")
        #expect(sample.labels["mountpoint"] == "/mnt/nas-storage")
        #expect(sample.value == 1)
    }

    /// A comma inside a value would end the label early if the scanner did not
    /// track quoting.
    @Test("keeps a label value containing a comma")
    func commaInLabelValue() {
        let sample = PrometheusText.parse(#"thing{a="x,y",b="z"} 3"#)[0]
        #expect(sample.labels == ["a": "x,y", "b": "z"])
    }

    @Test("unescapes quotes, backslashes and newlines in label values")
    func escapes() {
        let sample = PrometheusText.parse(#"thing{a="say \"hi\"",b="c:\\tmp",c="one\ntwo"} 1"#)[0]
        #expect(sample.labels["a"] == #"say "hi""#)
        #expect(sample.labels["b"] == #"c:\tmp"#)
        #expect(sample.labels["c"] == "one\ntwo")
    }

    @Test("reads scientific notation, as node_exporter emits for byte counts")
    func scientificNotation() {
        let sample = PrometheusText.parse("node_memory_MemTotal_bytes 1.30354966528e+11")[0]
        #expect(sample.value == 130_354_966_528)
    }

    @Test("ignores an optional trailing timestamp")
    func trailingTimestamp() {
        let sample = PrometheusText.parse("thing 4.5 1789943975000")[0]
        #expect(sample.value == 4.5)
    }

    @Test("reads the special float values")
    func specialFloats() {
        let samples = PrometheusText.parse("a NaN\nb +Inf\nc -Inf\n")
        #expect(samples[0].value.isNaN)
        #expect(samples[1].value == .infinity)
        #expect(samples[2].value == -.infinity)
    }

    @Test("drops blank lines and lines it cannot read")
    func malformed() {
        let text = """

        node_load1 0.42
        this_has_no_value
        node_load5 0.10
        """
        let samples = PrometheusText.parse(text)
        #expect(samples.map(\.name) == ["node_load1", "node_load5"])
    }

    @Test("survives an unterminated label block")
    func unterminatedLabels() {
        #expect(PrometheusText.parse(#"thing{a="x 1"#).isEmpty)
    }
}
