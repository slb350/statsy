import StatsyKit
import SwiftUI

struct CPUPane: View {
    let snapshot: Snapshot

    private var cpu: CPUMetrics { snapshot.cpu }

    var body: some View {
        Pane(title: "Processor", accent: Theme.purple, meta: "\(cpu.cores.count) CORES") {
            HeroNumber(
                value: Format.percent(cpu.busy),
                color: Theme.purple,
                captionLabel: "Load",
                caption: loadAverage
            )

            VStack(alignment: .leading, spacing: 4) {
                SegmentedBar(segments: [
                    .init(fraction: cpu.user, color: Theme.purple),
                    .init(fraction: cpu.system, color: Theme.yellow),
                ])
                HStack {
                    Text("USR \(Format.percent(cpu.user))").foregroundStyle(Theme.purple)
                    Spacer()
                    Text("SYS \(Format.percent(cpu.system))").foregroundStyle(Theme.yellow)
                    Spacer()
                    Text("IDLE \(Format.percent(cpu.idle))").foregroundStyle(Theme.textTertiary)
                }
                .font(Theme.mono(9))
            }

            VStack(alignment: .leading, spacing: 5) {
                SectionLabel(text: clusterCaption)
                CoreGrid(cores: cpu.cores, clusters: snapshot.machine.clusters)
            }

            VStack(alignment: .leading, spacing: 3) {
                SectionLabel(text: "Top processes", trailing: "% of one core")
                ProcessList(
                    processes: snapshot.processes.byCPU,
                    accent: Theme.purple,
                    value: { Format.decimal($0.cpu, decimals: 1) },
                    magnitude: \.cpu
                )
            }
        }
    }

    private var loadAverage: String {
        let load = cpu.loadAverage
        return [load.one, load.five, load.fifteen]
            .map { Format.decimal($0, decimals: 2) }
            .joined(separator: " ")
    }

    private var clusterCaption: String {
        let clusters = snapshot.machine.clusters
        guard !clusters.isEmpty else { return "Per-core" }
        return "Per-core · " + clusters.map(\.name).joined(separator: " / ")
    }
}
