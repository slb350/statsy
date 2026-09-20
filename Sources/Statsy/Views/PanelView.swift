import StatsyKit
import SwiftUI

/// The whole panel, laid out at exactly 1280x480 to match the target display
/// one-to-one.
///
/// Two arrangements share that frame. A local target spends the lower half of
/// each column on ranked processes. A remote one has no process telemetry to
/// show — node_exporter publishes none — so that space becomes a full-width
/// band of GPUs, which is the more useful thing to know about the machine this
/// panel points at anyway.
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
            // The flexible row. Everything below it is pinned, so the panes
            // absorb whatever the fixed sections leave and the 480 is never
            // over-allocated.
            .frame(maxHeight: .infinity)

            if snapshot.showsGPUBand {
                GPUBand(gpus: snapshot.gpus)
                    .frame(height: GPUBand.height)
            }

            ribbon
                .frame(height: 54)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .frame(width: Self.size.width, height: Self.size.height)
        .background(Theme.ground)
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder
    private var ribbon: some View {
        if snapshot.isLocal {
            ThermalRibbon(thermal: snapshot.thermal, network: snapshot.network)
        } else {
            RemoteRibbon(
                thermal: snapshot.thermal,
                network: snapshot.network,
                services: snapshot.services,
                link: snapshot.link
            )
        }
    }
}

// What the panel shows is decided here and nowhere else. Each of these answers
// a different question about the snapshot, so a target that is remote but has
// no GPUs, or local but cannot rank processes, still gets a layout somebody
// designed rather than an accidental fourth one.
extension Snapshot {
    /// Sampled in this process, so there is no link to report on.
    var isLocal: Bool { link.state == .local }

    /// Whether there are discrete cards worth a band of their own.
    var showsGPUBand: Bool { !gpus.isEmpty }

    /// Whether this target ranks processes.
    ///
    /// Read from the source's own declaration rather than inferred from the
    /// target being remote, so a privileged helper or a Linux process
    /// collector could turn the pane back on without the views changing.
    /// Asked of the capability rather than of the table because `top` discards
    /// its first block: a table-driven test would leave the pane reflowing a
    /// second after the panel appeared.
    var hasProcessTelemetry: Bool { machine.ranksProcesses }

    /// Height for a pane's trailing bar, which grows into the room a process
    /// list would otherwise have taken.
    var barHeight: CGFloat { hasProcessTelemetry ? 30 : 78 }
}
