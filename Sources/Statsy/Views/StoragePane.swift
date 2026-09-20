import StatsyKit
import SwiftUI

struct StoragePane: View {
    let snapshot: Snapshot

    private var storage: StorageMetrics { snapshot.storage }

    var body: some View {
        Pane(
            title: "Storage",
            accent: Theme.channelWhite,
            meta: "\(Format.binary(storage.total)) NVME"
        ) {
            HeroNumber(
                value: Format.percent(storage.usedFraction, decimals: 0),
                color: Theme.channelWhite,
                captionLabel: "Free",
                caption: Format.binary(storage.free)
            )

            VStack(alignment: .leading, spacing: 4) {
                SegmentedBar(segments: [
                    .init(fraction: storage.usedFraction, color: Theme.channelWhite)
                ])
                HStack {
                    Text("USED \(Format.binary(storage.used))").foregroundStyle(Theme.channelWhite)
                    Spacer()
                    Text("CAP \(Format.binary(storage.total))").foregroundStyle(Theme.textTertiary)
                }
                .font(Theme.mono(9))
            }

            VStack(alignment: .leading, spacing: 4) {
                SectionLabel(text: "Volumes")
                ForEach(storage.volumes) { volume in
                    HStack(spacing: 7) {
                        Text(volume.name)
                            .font(Theme.mono(9.5))
                            .foregroundStyle(Theme.textSecondary)
                            .frame(width: 46, alignment: .leading)
                        MiniTrack(
                            fraction: volume.fraction,
                            color: Theme.volume(volume.role),
                            height: 5
                        )
                        Text(Format.binary(volume.used))
                            .font(Theme.mono(9.5))
                            .foregroundStyle(Theme.textTertiary)
                            .frame(width: 58, alignment: .trailing)
                    }
                    .frame(height: 13)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                SectionLabel(
                    text: showsRateCells ? "Lifetime I/O" : "Throughput",
                    trailing: showsRateCells ? lifetimeTotal : rateSummary
                )
                // The GPU band takes this space on a remote target, so both
                // the lifetime split and the rate cells go and the throughput
                // figures move up onto the section label.
                if showsRateCells {
                    GeometryReader { geometry in
                        let available = max(0, geometry.size.width - 2)
                        HStack(spacing: 2) {
                            lifetimeCell(
                                "READ \(Format.binary(storage.lifetimeRead))",
                                tint: Theme.channelWhite.opacity(0.16),
                                text: Theme.channelWhite
                            )
                            .frame(width: available * readShare)
                            lifetimeCell(
                                "WRITE \(Format.binary(storage.lifetimeWritten))",
                                tint: Theme.purple.opacity(0.2),
                                text: Theme.purpleLight
                            )
                        }
                    }
                    .frame(height: 22)

                    HStack(spacing: 9) {
                        MeterCell(
                            label: "Read now",
                            value: Format.rate(storage.readRate),
                            valueSize: 22,
                            isActive: storage.readRate > 0
                        )
                        MeterCell(
                            label: "Write now",
                            value: Format.rate(storage.writeRate),
                            valueSize: 22,
                            isActive: storage.writeRate > 0
                        )
                    }
                }
            }
        }
    }

    private var showsRateCells: Bool { !snapshot.showsGPUBand }

    private var rateSummary: String {
        "↓ \(Format.rate(storage.readRate))  ↑ \(Format.rate(storage.writeRate))"
    }

    private var readShare: Double {
        let total = storage.lifetimeRead + storage.lifetimeWritten
        return total == 0 ? 0.5 : Double(storage.lifetimeRead) / Double(total)
    }

    private var lifetimeTotal: String {
        Format.binary(storage.lifetimeRead + storage.lifetimeWritten) + " total"
    }

    private func lifetimeCell(
        _ text: String, tint: Color, text textColor: Color
    ) -> some View {
        ZStack(alignment: .leading) {
            Rectangle().fill(tint)
            Text(text)
                .font(Theme.mono(10))
                .foregroundStyle(textColor)
                .lineLimit(1)
                .padding(.leading, 7)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
