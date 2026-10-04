import StatsyKit
import SwiftUI

/// Discrete GPUs, as a fourth column beside the three every target draws.
///
/// A column rather than the full-width band it replaced: the band took the
/// height the process lists need, and a column keeps the other three panes
/// laid out exactly as the local panel lays them out. VRAM gets the largest
/// figure because it decides whether a model fits; utilisation and power sit
/// at idle until a request arrives, so they get tracks.
struct GPUPane: View {
    let gpus: [GPUReading]
    let barHeight: CGFloat

    var body: some View {
        Pane(
            title: "Graphics",
            accent: Theme.yellow,
            meta: gpus.count == 1 ? "1 CARD" : "\(gpus.count) CARDS"
        ) {
            if gpus.count == 1, let gpu = gpus.first {
                LoneCard(gpu: gpu, barHeight: barHeight)
            } else {
                VStack(spacing: 0) {
                    ForEach(gpus) { gpu in
                        if gpu.id != gpus.first?.id {
                            Rectangle().fill(Theme.rule).frame(height: 1)
                                .padding(.vertical, 5)
                        }
                        CompactCard(gpu: gpu)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

/// VRAM leaves the memory channel's yellow once the card is nearly full.
/// Nothing else on the panel changes colour under pressure, so it reads as a
/// state change rather than decoration.
private func vramColor(_ gpu: GPUReading) -> Color {
    gpu.memoryFraction > 0.95 ? Theme.purpleLight : Theme.yellow
}

/// Power against the card's limit, with a track only when there is a limit to
/// measure against.
private func powerCell(_ gpu: GPUReading, valueSize: CGFloat = 16) -> MeterCell {
    MeterCell(
        label: "Power",
        value: gpu.powerDescription,
        valueSize: valueSize,
        fraction: gpu.wattLimit > 0 ? gpu.powerFraction : nil,
        isActive: gpu.watts > 0
    )
}

/// One card given the whole column, arranged like the panes beside it: a hero
/// figure, its bar and legend, then a section at the shared bar height.
private struct LoneCard: View {
    let gpu: GPUReading
    let barHeight: CGFloat

    var body: some View {
        HeroNumber(
            value: Format.percent(gpu.memoryFraction, decimals: 0),
            color: vramColor(gpu),
            captionLabel: gpu.memoryLabel,
            caption: Format.binary(gpu.memoryUsed, of: gpu.memoryTotal)
        )

        VStack(alignment: .leading, spacing: 4) {
            SegmentedBar(segments: [.init(fraction: gpu.memoryFraction, color: vramColor(gpu))])
            HStack {
                Text("USED \(Format.binary(gpu.memoryUsed))").foregroundStyle(vramColor(gpu))
                Spacer()
                Text("CAP \(Format.binary(gpu.memoryTotal))").foregroundStyle(Theme.textTertiary)
            }
            .font(Theme.mono(9))
        }

        VStack(alignment: .leading, spacing: 5) {
            SectionLabel(
                text: "Utilisation",
                trailing: "\(Format.percent(gpu.utilization, decimals: 0))%",
                trailingColor: Theme.purple
            )
            MiniTrack(fraction: gpu.utilization, color: Theme.purple, height: barHeight)
        }

        HStack(spacing: 9) {
            powerCell(gpu, valueSize: 22)
            MeterCell(
                label: "Temperature",
                value: "\(Format.decimal(gpu.celsius, decimals: 0))°C",
                tint: Theme.temperature(gpu.celsius),
                valueSize: 22,
                fraction: Theme.temperatureFraction(gpu.celsius)
            )
        }
    }
}

/// One of several cards sharing the column.
private struct CompactCard: View {
    let gpu: GPUReading

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("GPU \(gpu.id)")
                    .font(Theme.label(11))
                    .tracking(1.5)
                    .foregroundStyle(Theme.yellow)
                Text(gpu.memoryLabel)
                    .font(Theme.mono(9))
                    .foregroundStyle(Theme.textFaint)
                Spacer(minLength: 4)
                Text("\(Format.decimal(gpu.celsius, decimals: 0))°")
                    .font(Theme.numeral(16))
                    .foregroundStyle(Theme.temperature(gpu.celsius))
            }
            MiniTrack(fraction: gpu.memoryFraction, color: vramColor(gpu), height: 10)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(Format.binary(gpu.memoryUsed, of: gpu.memoryTotal))
                    .font(Theme.mono(10))
                    .foregroundStyle(Theme.textSecondary)
                Spacer(minLength: 4)
                Text(Format.percent(gpu.memoryFraction, decimals: 0))
                    .font(Theme.numeral(22))
                    .padding(.vertical, -4)
                    .foregroundStyle(vramColor(gpu))
                Text("%")
                    .font(Theme.label(10))
                    .foregroundStyle(Theme.textTertiary)
            }
            HStack(alignment: .top, spacing: 11) {
                MeterCell(
                    label: "Util",
                    value: Format.percent(gpu.utilization, decimals: 0) + "%",
                    tint: Theme.purple,
                    fraction: gpu.utilization,
                    isActive: gpu.utilization > 0
                )
                powerCell(gpu)
            }
        }
    }
}
