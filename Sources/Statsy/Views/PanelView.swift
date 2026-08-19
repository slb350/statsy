import StatsyKit
import SwiftUI

/// The whole panel: header, three metric columns, thermal ribbon.
///
/// Laid out at exactly 1280x480 to match the target display one-to-one.
struct PanelView: View {
    let snapshot: Snapshot

    static let size = CGSize(width: 1280, height: 480)

    var body: some View {
        VStack(spacing: 8) {
            HeaderBar(snapshot: snapshot)
                .frame(height: 22)

            HStack(spacing: 9) {
                CPUPane(snapshot: snapshot)
                MemoryPane(snapshot: snapshot)
                StoragePane(snapshot: snapshot)
            }
            .frame(maxHeight: .infinity)

            ThermalRibbon(thermal: snapshot.thermal, network: snapshot.network)
                .frame(height: 54)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .frame(width: Self.size.width, height: Self.size.height)
        .background(Theme.ground)
        .environment(\.colorScheme, .dark)
    }
}
