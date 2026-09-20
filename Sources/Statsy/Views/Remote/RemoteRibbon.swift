import StatsyKit
import SwiftUI

/// The remote panel's bottom strip: sensors, traffic, service health, and how
/// current any of it is.
///
/// The freshness readout is the part that earns its place. Two cadences land
/// on this panel — node_exporter answers every scrape, while the fleet
/// collector's units and endpoints are up to a minute old — and a panel that
/// showed both as equally current would be lying about one of them.
struct RemoteRibbon: View {
    let thermal: ThermalMetrics
    let network: NetworkMetrics
    let services: ServiceHealth
    let link: LinkStatus

    var body: some View {
        HStack(spacing: 14) {
            ForEach(SensorCluster.allCases, id: \.self) { cluster in
                if let reading = thermal[cluster] {
                    TemperatureReadout(label: cluster.label, reading: reading, width: 128)
                }
            }

            Spacer(minLength: 8)

            RibbonDivider()

            NetworkReadout(network: network)

            RibbonDivider()

            serviceReadout

            RibbonDivider()

            freshness
        }
        .ribbonBackground()
    }

    private var serviceReadout: some View {
        VStack(alignment: .leading, spacing: 3) {
            SectionLabel(text: "Services")
            HStack(spacing: 8) {
                ForEach(services.endpoints) { endpoint in
                    HStack(spacing: 4) {
                        Circle()
                            .fill(endpoint.ready ? Theme.yellow : Theme.purpleLight)
                            .frame(width: 6, height: 6)
                        Text(endpoint.ready ? "READY" : "DOWN")
                            .font(Theme.numeral(15))
                            .foregroundStyle(Theme.text)
                    }
                }
                if services.totalUnits > 0 {
                    Text("\(services.activeUnits)/\(services.totalUnits)")
                        .font(Theme.numeral(15))
                        .foregroundStyle(services.allUnitsActive ? Theme.text : Theme.purpleLight)
                    Text("UNITS")
                        .font(Theme.label(8))
                        .foregroundStyle(Theme.textFaint)
                }
            }
        }
        .frame(width: 148, alignment: .leading)
    }

    private var freshness: some View {
        VStack(alignment: .leading, spacing: 3) {
            SectionLabel(text: linkLabel, color: linkColor)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(collectionAge)
                    .font(Theme.numeral(18))
                    .foregroundStyle(Theme.textSecondary)
                Text("COLLECTOR")
                    .font(Theme.label(8))
                    .foregroundStyle(Theme.textFaint)
            }
        }
        .frame(width: 104, alignment: .leading)
    }

    private var linkLabel: String {
        switch link.state {
        case .stale: "STALE \(Format.decimal(link.age, decimals: 0))S"
        case .down: "NO DATA"
        // .local never reaches this ribbon; the local panel has its own.
        case .local, .live: "LIVE"
        }
    }

    private var linkColor: Color {
        switch link.state {
        case .stale: Theme.yellow
        case .down: Theme.purpleLight
        case .local, .live: Theme.textFaint
        }
    }

    private var collectionAge: String {
        guard let age = services.collectionAge else { return "—" }
        return "\(Format.decimal(age, decimals: 0))s"
    }
}
