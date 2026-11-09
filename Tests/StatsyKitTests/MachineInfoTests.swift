import Testing
@testable import StatsyKit

@Suite("Machine info")
struct MachineInfoTests {
    @Test("a tier repeated across dies is totalled once in the header, in first-seen order")
    func repeatedTiers() {
        let die = [CPUCluster(name: "Performance", coreCount: 12), CPUCluster(name: "Super", coreCount: 6)]
        let machine = MachineInfo(model: "Apple M5 Ultra", clusters: die + die)
        #expect(machine.summary == "APPLE M5 ULTRA  ·  24P + 12S  ·  0 GB")
    }
}
