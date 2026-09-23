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
                value: Format.percent(memory.inUseFraction),
                color: Theme.yellow,
                captionLabel: "In use",
                caption: "\(Format.gibibytes(memory.inUse)) / \(Format.gibibytes(memory.total)) GB"
            )

            VStack(alignment: .leading, spacing: 4) {
                SegmentedBar(segments: segments)
                HStack(spacing: 0) {
                    legend("WIRE", memory.wired, Theme.channelWhite)
                    Spacer(minLength: 2)
                    legend("CMPR", memory.compressed, Theme.purple)
                    Spacer(minLength: 2)
                    if memory.gpuShared > 0 {
                        legend("GPU", memory.gpuShared, Theme.purpleLight)
                        Spacer(minLength: 2)
                    }
                    legend("ACTV", memory.active, Theme.yellow)
                    Spacer(minLength: 2)
                    legend("RECL", memory.reclaimable, Theme.yellowDim)
                    Spacer(minLength: 2)
                    legend("FREE", memory.free, Theme.textTertiary)
                }
                .font(Theme.mono(9))
            }

            VStack(alignment: .leading, spacing: 5) {
                SectionLabel(
                    text: "Swap",
                    trailing: "\(Format.percent(memory.swapFraction))% · \(swapDetail)",
                    trailingColor: Theme.yellow
                )
                SwapBar(
                    fraction: memory.swapFraction,
                    height: snapshot.barHeight
                )
            }

            if snapshot.hasProcessTelemetry {
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
    }

    private func share(_ bytes: UInt64) -> Double {
        .ratio(bytes, of: memory.total)
    }

    /// The composition bar, with the unified host's GPU-held segment between
    /// compressed and active: the model's residency, in the bucket list's
    /// least-to-most-reclaimable order. Purple-light so it cannot blur into
    /// the yellow of the buckets around it; every non-unified target, which
    /// has no such memory, draws the pane exactly as before.
    private var segments: [SegmentedBar.Segment] {
        var segments = [
            SegmentedBar.Segment(fraction: share(memory.wired), color: Theme.channelWhite),
            SegmentedBar.Segment(fraction: share(memory.compressed), color: Theme.purple),
        ]
        if memory.gpuShared > 0 {
            segments.append(
                SegmentedBar.Segment(fraction: share(memory.gpuShared), color: Theme.purpleLight)
            )
        }
        segments += [
            SegmentedBar.Segment(fraction: share(memory.active), color: Theme.yellow),
            SegmentedBar.Segment(fraction: share(memory.reclaimable), color: Theme.yellowDim),
        ]
        return segments
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
    let height: CGFloat

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
        .frame(height: height)
        .background(Theme.track)
    }
}
