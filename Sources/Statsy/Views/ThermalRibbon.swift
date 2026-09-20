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
                    TemperatureReadout(label: cluster.label, reading: reading)
                }
            }

            RibbonDivider()

            ForEach(thermal.fans) { fan in
                FanReadout(fan: fan)
            }

            RibbonDivider()

            NetworkReadout(network: network)
        }
        .ribbonBackground()
    }
}
