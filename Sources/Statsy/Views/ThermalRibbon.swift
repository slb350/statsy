import StatsyKit
import SwiftUI

/// The full-width strip of sensor clusters, fans and network totals.
struct ThermalRibbon: View {
    let thermal: ThermalMetrics
    let network: NetworkMetrics

    var body: some View {
        HStack(spacing: 14) {
            ForEach(SensorCluster.allCases, id: \.self) { cluster in
                if let reading = thermal[cluster] {
                    temperature(cluster, reading)
                }
            }

            divider

            ForEach(thermal.fans) { fan in
                fanReadout(fan)
            }

            divider

            networkReadout
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.surface)
        .overlay(Rectangle().strokeBorder(Theme.rule, lineWidth: 1))
    }

    private var divider: some View {
        Rectangle().fill(Theme.rule).frame(width: 1, height: 34)
    }

    private func temperature(_ cluster: SensorCluster, _ reading: ClusterReading) -> some View {
        let colour = Theme.temperature(reading.average)
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(cluster.label.uppercased())
                    .font(Theme.label(8.5))
                    .tracking(1.2)
                    .foregroundStyle(Theme.textFaint)
                Spacer(minLength: 2)
                Text("\(reading.count) SENS")
                    .font(Theme.mono(8))
                    .foregroundStyle(Theme.rule)
            }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(Format.decimal(reading.average, decimals: 1))
                    .font(Theme.numeral(21))
                    .foregroundStyle(colour)
                Text("°C")
                    .font(Theme.label(9))
                    .foregroundStyle(Theme.textTertiary)
            }
            MiniTrack(fraction: Theme.temperatureFraction(reading.average), color: colour)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func fanReadout(_ fan: FanReading) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("FAN \(fan.id)")
                .font(Theme.label(8.5))
                .tracking(1.2)
                .foregroundStyle(Theme.textFaint)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(Format.decimal(fan.actual, decimals: 0))
                    .font(Theme.numeral(21))
                    .foregroundStyle(Theme.purpleLight)
                Text("rpm")
                    .font(Theme.label(9))
                    .foregroundStyle(Theme.textTertiary)
            }
            MiniTrack(fraction: fan.fraction, color: Theme.purple)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var networkReadout: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("NETWORK LIFETIME")
                .font(Theme.label(8.5))
                .tracking(1.2)
                .foregroundStyle(Theme.textFaint)
            HStack(spacing: 10) {
                trafficReadout(
                    bytes: network.lifetimeIn, symbol: "arrow.down", tint: Theme.purple
                )
                trafficReadout(
                    bytes: network.lifetimeOut, symbol: "arrow.up", tint: Theme.yellow
                )
            }
        }
        // Fixed rather than flexible: two byte figures need more room than a
        // single temperature, and were truncating at an equal share.
        .frame(width: 152, alignment: .leading)
    }

    private func trafficReadout(bytes: UInt64, symbol: String, tint: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(tint)
            Text(Format.binary(bytes, decimals: 1))
                .font(Theme.numeral(18))
                .foregroundStyle(Theme.channelWhite)
        }
    }
}
