import Foundation
import StatsyKit

// Dumps one snapshot to the terminal, for checking the samplers against the
// system tools they are meant to agree with (top, df, netstat, smc).
//
// With `--target <id>` it does the same for a remote host, which is the only
// way to check a mapping against `nvidia-smi`, `free` and `df` on the machine
// the readings came from. `--reduce <scrape>` cuts a raw capture down to a
// test fixture instead (docs/adding-a-host.md).
let target: Target
do {
    target = try TargetRegistry.target(
        from: CommandLine.arguments, default: TargetRegistry.local
    )
} catch {
    FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
    exit(1)
}

// `--reduce <scrape>` cuts a raw capture down to what the target's mapper
// reads, which is how a test fixture is made (docs/adding-a-host.md).
if CommandLine.arguments.contains("--reduce") {
    guard let remote = target.remote,
          let path = argument(after: "--reduce", in: CommandLine.arguments),
          let text = try? String(contentsOfFile: path, encoding: .utf8)
    else {
        FileHandle.standardError.write(Data("usage: statsy-probe --target <remote id> --reduce <scrape.prom>\n".utf8))
        exit(1)
    }
    let mapper = RemoteMapper(target: remote)
    for line in PrometheusText.lines(text, wanted: mapper.wants).sorted() { print(line) }
    exit(0)
}

let provider = SnapshotProviderFactory.provider(for: target)
let snapshot = await provider.settledSample()

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
    print("  \(name)\(Format.binary(volume.used, of: volume.total))  \(share)%")
}
let readRate = Format.rate(snapshot.storage.readRate)
let writeRate = Format.rate(snapshot.storage.writeRate)
let lifetime = "lifetime read \(Format.binary(snapshot.storage.lifetimeRead))  "
    + "written \(Format.binary(snapshot.storage.lifetimeWritten))"
print("  io      read \(readRate)  write \(writeRate)  \(lifetime)")

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
    let vram = Format.binary(gpu.memoryUsed, of: gpu.memoryTotal)
    let share = Format.percent(gpu.memoryFraction, decimals: 0)
    let util = Format.percent(gpu.utilization, decimals: 0)
    let temperature = Format.decimal(gpu.celsius, decimals: 0)
    print("gpu \(gpu.id)     vram \(vram)  \(share)%  util \(util)%  \(gpu.powerDescription)  \(temperature)C")
}

func printProcesses(_ title: String, _ rows: [ProcessSample], _ value: (ProcessSample) -> String) {
    print(title)
    for row in rows {
        let name = row.name.padding(toLength: 24, withPad: " ", startingAt: 0)
        print("  \(String(row.id).padding(toLength: 8, withPad: " ", startingAt: 0))\(name)\(value(row))")
    }
}
if snapshot.machine.ranksProcesses {
    printProcesses("by cpu", snapshot.processes.byCPU) { Format.decimal($0.cpu, decimals: 1) + "%" }
    printProcesses("by memory", snapshot.processes.byMemory) { Format.binary($0.memory) }
}

if !snapshot.services.isEmpty {
    var units = "\(snapshot.services.activeUnits)/\(snapshot.services.totalUnits) units active"
    if snapshot.services.totalContainers > 0 {
        units += ", \(snapshot.services.runningContainers)/\(snapshot.services.totalContainers) containers running"
    }
    let age = snapshot.services.collectionAge.map { "  collected \(Format.age($0)) ago" } ?? ""
    print("services  \(units)\(age)")
    for endpoint in snapshot.services.endpoints {
        print("  \(endpoint.name)  \(endpoint.ready ? "ready" : "NOT READY")")
    }
}

if let detail = snapshot.link.detail {
    print("link      \(snapshot.link.state)  \(detail)")
}

await provider.stop()
