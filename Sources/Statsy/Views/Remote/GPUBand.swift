import StatsyKit
import SwiftUI

/// The full-width row of discrete GPUs.
///
/// VRAM gets the widest bar and the largest figure because it is the reading
/// that decides whether a model fits: on this host the three cards sit near
/// 90% with a 27B model resident, and the margin left over is the number worth
/// seeing from across a room. Utilisation and power sit at idle until a
/// request arrives, so they get tracks rather than headlines.
struct GPUBand: View {
    let gpus: [GPUReading]

    /// Pinned rather than intrinsic, and chosen against the panes' natural
    /// height: the panel is a fixed 480 with no scroll, so one section has to
    /// name its size and the rest divide the remainder.
    static let height: CGFloat = 132

    var body: some View {
        HStack(spacing: 9) {
            ForEach(gpus) { gpu in
                GPUCard(gpu: gpu)
            }
        }
    }
}

private struct GPUCard: View {
    let gpu: GPUReading

    /// VRAM leaves the memory channel's yellow once the card is nearly full.
    /// Nothing else on the panel changes colour under pressure, so it reads as
    /// a state change rather than decoration.
    private var vramColor: Color {
        gpu.memoryFraction > 0.95 ? Theme.purpleLight : Theme.yellow
    }

    var body: some View {
        Pane(
            title: "GPU \(gpu.id)",
            accent: Theme.yellow,
            meta: "",
            subtitle: "VRAM",
            trailing: "\(Format.decimal(gpu.celsius, decimals: 0))°",
            trailingColor: Theme.temperature(gpu.celsius)
        ) {
            VStack(alignment: .leading, spacing: 4) {
                MiniTrack(fraction: gpu.memoryFraction, color: vramColor, height: 16)
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text("\(Format.binary(gpu.memoryUsed)) / \(Format.binary(gpu.memoryTotal))")
                        .font(Theme.mono(10.5))
                        .foregroundStyle(Theme.textSecondary)
                    Spacer(minLength: 4)
                    Text(Format.percent(gpu.memoryFraction, decimals: 0))
                        .font(Theme.numeral(24))
                        .padding(.vertical, -5)
                        .foregroundStyle(vramColor)
                    Text("%")
                        .font(Theme.label(10))
                        .foregroundStyle(Theme.textTertiary)
                }
            }

            Spacer(minLength: 0)

            HStack(alignment: .top, spacing: 11) {
                MeterCell(
                    label: "Util",
                    value: Format.percent(gpu.utilization, decimals: 0) + "%",
                    tint: Theme.purple,
                    fraction: gpu.utilization,
                    isActive: gpu.utilization > 0
                )
                MeterCell(
                    label: "Power",
                    value: "\(Format.decimal(gpu.watts, decimals: 0)) / \(Format.decimal(gpu.wattLimit, decimals: 0)) W",
                    fraction: gpu.powerFraction,
                    isActive: gpu.watts > 0
                )
            }
        }
    }
}
