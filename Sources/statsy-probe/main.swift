import Foundation
import StatsyKit

// Dumps one snapshot to the terminal, for checking the samplers against the
// system tools they are meant to agree with (top, df, netstat, smc).
//
// With `--target <id>` it does the same for a remote host, which is the only
// way to check a mapping against `nvidia-smi`, `free` and `df` on the machine
// the readings came from.
let target: Target
do {
    target = try TargetRegistry.target(
        from: CommandLine.arguments, default: TargetRegistry.local
    )
} catch {
    FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
    exit(1)
}

let provider = SnapshotProviderFactory.provider(for: target)
let snapshot = await provider.primedSample()

print("target    \(target.name)  (\(snapshot.link.state))")
print("machine   \(snapshot.machine.summary)  \(snapshot.uptimeDescription)")
print("platform  \(snapshot.machine.platformVersion)")

let cpuBusy = Format.percent(snapshot.cpu.busy)
let cpuUser = Format.percent(snapshot.cpu.user)
let cpuSystem = Format.percent(snapshot.cpu.system)
let load = snapshot.cpu.loadAverage
let loadSummary = [load.one, load.five, load.fifteen]
    .map { Format.decimal($0, decimals: 2) }.joined(separator: " ")
print("cpu       \(cpuBusy)%  usr \(cpuUser)  sys \(cpuSystem)  \(snapshot.cpu.cores.count) cores  load \(loadSummary)")

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
    let name = volume.name.padding(toLength: 8, withPad: " ", startingAt: 0)
    let share = Format.percent(volume.fraction, decimals: 0)
    print("  \(name)\(Format.binary(volume.used)) / \(Format.binary(volume.total))  \(share)%")
}
let readRate = Format.rate(snapshot.storage.readRate)
let writeRate = Format.rate(snapshot.storage.writeRate)
print("  io      read \(readRate)  write \(writeRate)")

print("network   in \(Format.binary(snapshot.network.lifetimeIn))  out \(Format.binary(snapshot.network.lifetimeOut))")

for cluster in SensorCluster.allCases {
    if let reading = snapshot.thermal[cluster] {
        let label = cluster.label.padding(toLength: 10, withPad: " ", startingAt: 0)
        let average = Format.decimal(reading.average, decimals: 1)
        let spread = "\(Format.decimal(reading.minimum, decimals: 1))-\(Format.decimal(reading.maximum, decimals: 1))"
        print("  \(label)\(average)C  range \(spread)  n=\(reading.count)")
    }
}

for gpu in snapshot.gpus {
    let vram = "\(Format.binary(gpu.memoryUsed)) / \(Format.binary(gpu.memoryTotal))"
    let share = Format.percent(gpu.memoryFraction, decimals: 0)
    let util = Format.percent(gpu.utilization, decimals: 0)
    let watts = Format.decimal(gpu.watts, decimals: 0)
    let limit = Format.decimal(gpu.wattLimit, decimals: 0)
    print("gpu \(gpu.id)     vram \(vram)  \(share)%  util \(util)%  \(watts)/\(limit)W  \(Format.decimal(gpu.celsius, decimals: 0))C")
}

if !snapshot.services.isEmpty {
    let units = "\(snapshot.services.activeUnits)/\(snapshot.services.totalUnits) units active"
    let age = snapshot.services.collectionAge.map { "  collected \(Format.decimal($0, decimals: 0))s ago" } ?? ""
    print("services  \(units)\(age)")
    for endpoint in snapshot.services.endpoints {
        print("  \(endpoint.name)  \(endpoint.ready ? "ready" : "NOT READY")")
    }
}

if let detail = snapshot.link.detail {
    print("link      \(snapshot.link.state)  \(detail)")
}

await provider.stop()
