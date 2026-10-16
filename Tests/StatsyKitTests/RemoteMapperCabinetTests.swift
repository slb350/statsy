import Foundation
import Testing
@testable import StatsyKit

@Suite("Remote mapper — cabinet sampler")
struct RemoteMapperCabinetTests {
    private func snapshot(_ text: String, target: Target = TargetRegistry.homelab1) throws -> Snapshot {
        var mapper = RemoteMapper(target: try #require(target.remote))
        return mapper.snapshot(
            from: mapper.metrics(from: text), now: Date(timeIntervalSince1970: 1_000),
            link: LinkStatus(state: .live)
        )
    }

    private let cabinet = """
    homelab_cabinet_temperature_celsius{asset_host="homelab-1",sensor="cpu"} 26
    homelab_cabinet_temperature_celsius{asset_host="homelab-1",sensor="gpu"} 40
    homelab_cabinet_temperature_celsius{asset_host="other",sensor="cpu"} 99
    homelab_cabinet_status_timestamp_seconds{asset_host="homelab-1"} 920
    homelab_collection_timestamp_seconds{asset_host="homelab-1"} 990
    """

    @Test("cabinet temperatures replace absent hwmon with host-scoped real samples")
    func temperatures() throws {
        let result = try snapshot(cabinet)
        #expect(result.thermal[.cpu]?.average == 26)
        #expect(result.thermal[.gpu]?.average == 40)
        #expect(result.thermal[.cpu]?.count == 1)
        #expect(result.services.collectionAge == 80)
    }

    @Test("cabinet age follows displayed fallback even when hwmon is enabled")
    func enabledHwmonFallbackAge() throws {
        let text = cabinet.replacingOccurrences(of: "homelab-1", with: "strix")
        let result = try snapshot(text, target: TargetRegistry.strix)
        #expect(result.thermal[.cpu]?.average == 26)
        #expect(result.services.collectionAge == 80)
    }

    @Test("unused cabinet data does not age direct temperature readings")
    func unusedCabinetAge() throws {
        let direct = """
        node_hwmon_chip_names{chip="cpu",chip_name="coretemp"} 1
        node_hwmon_temp_celsius{chip="cpu",sensor="temp1"} 30
        homelab_gpu_temperature_celsius{asset_host="homelab-1",gpu="0"} 43
        """
        let result = try snapshot(cabinet + "\n" + direct)
        #expect(result.thermal[.cpu]?.average == 30)
        #expect(result.thermal[.gpu]?.average == 43)
        #expect(result.services.collectionAge == 10)
    }

    @Test("direct hardware readings take precedence over cabinet fallback")
    func precedence() throws {
        let direct = """
        node_hwmon_chip_names{chip="cpu",chip_name="coretemp"} 1
        node_hwmon_temp_celsius{chip="cpu",sensor="temp1"} 30
        homelab_gpu_temperature_celsius{asset_host="homelab-1",gpu="0"} 43
        homelab_gpu_sample_timestamp_seconds{asset_host="homelab-1",gpu="0"} 910
        """
        let result = try snapshot(cabinet + "\n" + direct)
        #expect(result.thermal[.cpu]?.average == 30)
        #expect(result.thermal[.gpu]?.average == 43)
        #expect(result.thermal[.gpu]?.count == 1)
        #expect(result.services.collectionAge == 90)
    }
}
