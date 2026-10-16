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
            // Darwin's node_exporter has no working thermal collector on the
            // minis. Said, so the empty strip does not read as a panel that
            // failed to draw.
            if thermal.clusters.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    SectionLabel(text: "Sensors")
                    Text("NONE PUBLISHED")
                        .font(Theme.numeral(15))
                        .foregroundStyle(Theme.textFaint)
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

    /// One dot for the whole host, then a count per kind of thing the
    /// collector watches. Counts rather than a mark per endpoint: Legion has
    /// two endpoints and another host dozens of containers, and neither fits
    /// one mark apiece.
    private var serviceReadout: some View {
        VStack(alignment: .leading, spacing: 3) {
            SectionLabel(text: "Services")
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Circle()
                    .fill(services.isHealthy ? Theme.yellow : Theme.purpleLight)
                    .frame(width: 6, height: 6)
                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] }
                if services.totalUnits > 0 {
                    count(services.activeUnits, of: services.totalUnits, "UNITS")
                }
                if services.totalContainers > 0 {
                    count(services.runningContainers, of: services.totalContainers, "CTRS")
                }
                if !services.endpoints.isEmpty {
                    count(services.readyEndpoints, of: services.endpoints.count, "READY")
                }
            }
        }
        .fixedSize()
    }

    private func count(_ active: Int, of total: Int, _ label: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text("\(active)/\(total)")
                .font(Theme.numeral(15))
                .foregroundStyle(active == total ? Theme.text : Theme.purpleLight)
            Text(label)
                .font(Theme.label(8))
                .foregroundStyle(Theme.textFaint)
        }
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
        return Format.age(age)
    }
}
