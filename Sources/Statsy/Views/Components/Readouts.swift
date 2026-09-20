import StatsyKit
import SwiftUI

/// A ribbon cell: caption, a large value with its unit, and a track beneath.
///
/// Shared by the temperature and fan readouts, which are the same shape and
/// differ only in their tint rule, their unit and whether they carry a sensor
/// count.
struct GaugeReadout<Caption: View>: View {
    let value: String
    let unit: String
    let tint: Color
    let fraction: Double
    /// Fixed width when the ribbon has few cells to show. Left flexible, three
    /// sensors share the width five were laid out for and the strip reads as
    /// half empty.
    var width: CGFloat?
    @ViewBuilder var caption: Caption

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            caption
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(Theme.numeral(21))
                    .foregroundStyle(tint)
                Text(unit)
                    .font(Theme.label(9))
                    .foregroundStyle(Theme.textTertiary)
            }
            MiniTrack(fraction: fraction, color: tint)
        }
        .frame(maxWidth: width ?? .infinity, alignment: .leading)
    }
}

/// One sensor cluster in a ribbon: label, average, and its place on the ramp.
struct TemperatureReadout: View {
    let label: String
    let reading: ClusterReading
    var width: CGFloat?

    var body: some View {
        let colour = Theme.temperature(reading.average)
        GaugeReadout(
            value: Format.decimal(reading.average, decimals: 1),
            unit: "°C",
            tint: colour,
            fraction: Theme.temperatureFraction(reading.average),
            width: width
        ) {
            HStack(spacing: 4) {
                SectionLabel(text: label)
                Spacer(minLength: 2)
                Text("\(reading.count) SENS")
                    .font(Theme.mono(8))
                    .foregroundStyle(Theme.rule)
            }
        }
    }
}

/// One fan's speed against its maximum.
struct FanReadout: View {
    let fan: FanReading

    var body: some View {
        GaugeReadout(
            value: Format.decimal(fan.actual, decimals: 0),
            unit: "rpm",
            tint: Theme.purpleLight,
            fraction: fan.fraction
        ) {
            SectionLabel(text: "Fan \(fan.id)")
        }
    }
}

/// A labelled figure with an optional track, as the panes show throughput and
/// a GPU card shows utilisation and power.
struct MeterCell: View {
    let label: String
    let value: String
    var tint: Color = Theme.channelWhite
    var valueSize: CGFloat = 16
    var fraction: Double?
    var isActive = true

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            SectionLabel(text: label)
            Text(value)
                .font(Theme.numeral(valueSize))
                .foregroundStyle(isActive ? tint : Theme.textFaint)
            if let fraction {
                MiniTrack(fraction: fraction, color: tint, height: 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Lifetime traffic in and out.
struct NetworkReadout: View {
    let network: NetworkMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            SectionLabel(text: "Network lifetime")
            HStack(spacing: 10) {
                traffic(bytes: network.lifetimeIn, symbol: "arrow.down", tint: Theme.purple)
                traffic(bytes: network.lifetimeOut, symbol: "arrow.up", tint: Theme.yellow)
            }
        }
        // Fixed rather than flexible: two byte figures need more room than a
        // single temperature, and were truncating at an equal share.
        .frame(width: 152, alignment: .leading)
    }

    private func traffic(bytes: UInt64, symbol: String, tint: Color) -> some View {
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

struct RibbonDivider: View {
    var body: some View {
        Rectangle().fill(Theme.rule).frame(width: 1, height: 34)
    }
}

/// The ribbon's surface, shared so both variants sit at the same weight.
struct RibbonBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 14)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.surface)
            .overlay(Rectangle().strokeBorder(Theme.rule, lineWidth: 1))
    }
}

extension View {
    func ribbonBackground() -> some View { modifier(RibbonBackground()) }
}
