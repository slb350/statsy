import StatsyKit
import SwiftUI

/// The whole panel, laid out at exactly 1280x480 to match the target display
/// one-to-one.
///
/// Every target gets the local panel's three columns, each spending its lower
/// half on ranked processes. A host with discrete GPUs adds a fourth column
/// for them. A unified-memory host does not: its GPU's memory is already the
/// memory pane's GPU segment and its utilisation rides beside the processor's
/// hero number, so strix draws the same three columns this Mac does.
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
                if snapshot.showsGPUPane {
                    GPUPane(gpus: snapshot.gpus, barHeight: snapshot.barHeight)
                }
            }
            // The flexible row. Everything below it is pinned, so the panes
            // absorb whatever the fixed sections leave and the 480 is never
            // over-allocated.
            .frame(maxHeight: .infinity)

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

    /// Whether there are discrete cards worth a column of their own.
    ///
    /// A unified-memory GPU reports through the memory fold and the processor
    /// hero instead, so its readings draw no column.
    var showsGPUPane: Bool { !gpus.isEmpty && !machine.unifiedMemory }

    /// Whether the processor hero carries a GPU utilisation figure.
    ///
    /// The unified GPU's only reading that has no other home: its memory is
    /// the memory pane's GPU segment, its temperature is the ribbon's `.gpu`
    /// cluster, and its power goes undrawn. Discrete cards show utilisation
    /// per card in their column; a local target publishes no GPU reading.
    var showsInlineGPUUtilization: Bool { machine.unifiedMemory && !gpus.isEmpty }

    /// Whether this target ranks processes.
    ///
    /// Read from the source's own declaration rather than inferred from the
    /// target being remote, so a privileged helper or a Linux process
    /// collector could turn the pane back on without the views changing.
    /// Asked of the capability rather than of the table because `top` discards
    /// its first block: a table-driven test would leave the pane reflowing a
    /// second after the panel appeared.
    var hasProcessTelemetry: Bool { machine.ranksProcesses }

    /// The memory list's caption, naming what its figure measures.
    var processMemoryLabel: String {
        switch machine.processMemory {
        case .footprint: "footprint"
        case .resident: "resident"
        }
    }

    /// Height for a pane's trailing bar, which grows into the room a process
    /// list would otherwise have taken.
    var barHeight: CGFloat { hasProcessTelemetry ? 30 : 170 }
}
