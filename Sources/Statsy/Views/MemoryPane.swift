import StatsyKit
import SwiftUI

struct MemoryPane: View {
    let snapshot: Snapshot

    private var memory: MemoryMetrics { snapshot.memory }

    var body: some View {
        Pane(
            title: "Memory",
            accent: Theme.yellow,
            meta: "\(Format.gibibytes(memory.total)) GB"
        ) {
            HeroNumber(
                value: Format.percent(memory.usedFraction),
                color: Theme.yellow,
                captionLabel: "Used",
                caption: "\(Format.gibibytes(memory.used)) / \(Format.gibibytes(memory.total)) GB"
            )

            VStack(alignment: .leading, spacing: 4) {
                SegmentedBar(segments: [
                    .init(fraction: share(memory.wired), color: Theme.channelWhite),
                    .init(fraction: share(memory.compressed), color: Theme.purple),
                    .init(fraction: share(memory.active), color: Theme.yellow),
                    .init(fraction: share(memory.inactive), color: Theme.yellowDim),
                ])
                HStack(spacing: 0) {
                    legend("WIRE", memory.wired, Theme.channelWhite)
                    Spacer(minLength: 2)
                    legend("CMPR", memory.compressed, Theme.purple)
                    Spacer(minLength: 2)
                    legend("ACTV", memory.active, Theme.yellow)
                    Spacer(minLength: 2)
                    legend("INAC", memory.inactive, Theme.yellowDim)
                    Spacer(minLength: 2)
                    legend("FREE", memory.unused, Theme.textTertiary)
                }
                .font(Theme.mono(9))
            }

            VStack(alignment: .leading, spacing: 5) {
                SectionLabel(
                    text: "Swap",
                    trailing: "\(Format.percent(memory.swapFraction))% · \(swapDetail)",
                    trailingColor: Theme.yellow
                )
                SwapBar(fraction: memory.swapFraction)
            }

            VStack(alignment: .leading, spacing: 3) {
                SectionLabel(text: "Top processes", trailing: "footprint")
                ProcessList(
                    processes: snapshot.processes.byMemory,
                    accent: Theme.yellow,
                    value: { Format.binary($0.memory) },
                    magnitude: { Double($0.memory) }
                )
            }
        }
    }

    private func share(_ bytes: UInt64) -> Double {
        memory.total == 0 ? 0 : Double(bytes) / Double(memory.total)
    }

    private func legend(_ name: String, _ bytes: UInt64, _ color: Color) -> some View {
        Text("\(name) \(Format.gibibytes(bytes))").foregroundStyle(color)
    }

    private var swapDetail: String {
        "\(Format.binary(memory.swapUsed)) / \(Format.binary(memory.swapTotal))"
    }
}

/// Swap gets a hatched fill so it reads as pressure rather than capacity.
private struct SwapBar: View {
    let fraction: Double

    /// One stripe plus its gap.
    private static let pitch: CGFloat = 6

    var body: some View {
        GeometryReader { geometry in
            let fill = geometry.size.width * fraction.clamped01
            HStack(spacing: 3) {
                ForEach(0..<Int(fill / Self.pitch) + 1, id: \.self) { _ in
                    Rectangle().fill(Theme.yellow).frame(width: 3)
                }
            }
            .frame(width: fill, alignment: .leading)
            .clipped()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 30)
        .background(Theme.track)
    }
}
