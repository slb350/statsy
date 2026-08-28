import Foundation
import StatsyKit

// Dumps one snapshot to the terminal, for checking the samplers against the
// system tools they are meant to agree with (top, df, netstat, smc).
let engine = MetricsEngine()
await engine.start()
try? await Task.sleep(for: .seconds(1))
let snapshot = await engine.sample()

print("machine   \(snapshot.machine.summary)  \(snapshot.uptimeDescription)")
let cpuBusy = Format.percent(snapshot.cpu.busy)
let cpuUser = Format.percent(snapshot.cpu.user)
let cpuSystem = Format.percent(snapshot.cpu.system)
print("cpu       \(cpuBusy)%  usr \(cpuUser)  sys \(cpuSystem)")

let memoryInUse = Format.gibibytes(snapshot.memory.inUse)
let memoryTotal = Format.gibibytes(snapshot.memory.total)
let memoryReclaimable = Format.gibibytes(snapshot.memory.reclaimable)
let swapPercent = Format.percent(snapshot.memory.swapFraction)
let memorySummary = "in use \(memoryInUse) / \(memoryTotal) GiB  "
    + "reclaimable \(memoryReclaimable) GiB  swap \(swapPercent)%"
print("memory    \(memorySummary)")

let storageUsed = Format.percent(snapshot.storage.usedFraction, decimals: 0)
let storageFree = Format.binary(snapshot.storage.free)
print("storage   \(storageUsed)%  free \(storageFree)")
for volume in snapshot.storage.volumes {
    print("  \(volume.name.padding(toLength: 8, withPad: " ", startingAt: 0))\(Format.binary(volume.used))")
}
print("network   in \(Format.binary(snapshot.network.lifetimeIn))  out \(Format.binary(snapshot.network.lifetimeOut))")
for cluster in SensorCluster.allCases {
    if let reading = snapshot.thermal[cluster] {
        let label = cluster.label.padding(toLength: 10, withPad: " ", startingAt: 0)
        let average = Format.decimal(reading.average, decimals: 1)
        let spread = "\(Format.decimal(reading.minimum, decimals: 1))-\(Format.decimal(reading.maximum, decimals: 1))"
        print("  \(label)\(average)C  range \(spread)  n=\(reading.count)")
    }
}
await engine.stop()
