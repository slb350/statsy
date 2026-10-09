import Foundation
import Testing
@testable import StatsyKit

// Failure and partial-data cases share the captured ai-1 fixture.
extension RemoteMapperTests {

    @Test("an empty scrape maps to empty readings rather than crashing")
    func emptyScrape() {
        var mapper = RemoteMapper(target: Self.target)
        let snapshot = mapper.snapshot(
            from: MetricSet([]), now: Self.captured, link: LinkStatus(state: .down)
        )
        #expect(snapshot.gpus.isEmpty)
        #expect(snapshot.memory.total == 0)
        #expect(snapshot.storage.volumes.isEmpty)
        #expect(snapshot.uptime == 0)
    }

    @Test("the declared series cover everything the mapper reads")
    func wantedSeries() {
        // A name the mapper reads but does not declare would be filtered out
        // of a live scrape and silently never arrive, while the fixture — which
        // is parsed unfiltered — would go on passing every other test here.
        var mapper = RemoteMapper(target: Self.target)
        let filtered = mapper.metrics(from: Self.fixture())
        let declared = mapper.snapshot(
            from: filtered, now: Self.captured, link: LinkStatus(state: .live)
        )
        #expect(declared == mapped())
    }

    @Test("fleet metrics are read through the target's collector prefix")
    func collectorPrefix() {
        // A host whose collector publishes under another namespace must read as
        // absent rather than silently drawing an empty band.
        var renamed = RemoteMapper(target: Self.target.replacing(collectorPrefix: "fleet_"))
        let snapshot = renamed.snapshot(
            from: Self.metrics, now: Self.captured, link: LinkStatus(state: .live)
        )
        #expect(snapshot.gpus.isEmpty)
        #expect(snapshot.services.isEmpty)
        // node_exporter's own series are unaffected by the collector's naming.
        #expect(snapshot.memory.total > 0)
        #expect(!mapped().gpus.isEmpty)
    }

    @Test("a card missing its capacity is dropped rather than drawn empty")
    func partialGPU() {
        let samples = Self.metrics.samples("homelab_gpu_memory_used_bytes")
            + Self.metrics.samples("homelab_gpu_temperature_celsius")
        #expect(RemoteMapper(target: Self.target).gpus(from: MetricSet(samples)).isEmpty)
    }
}
