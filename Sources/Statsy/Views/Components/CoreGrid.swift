import StatsyKit
import SwiftUI

/// Per-core load, grouped by hardware cluster.
///
/// Cluster names come from the hardware rather than being assumed: this
/// machine's M5 Max reports "Super" (6) and "Performance" (12), not the usual
/// performance/efficiency split.
struct CoreGrid: View {
    let cores: [CoreLoad]
    let clusters: [CPUCluster]
    /// Taller where nothing follows it in the pane. Forty-eight threads at the
    /// compact height are a row of stubs; given the room a process list would
    /// have taken, the grid reads as a chart.
    let height: CGFloat

    /// Index of the first core in each cluster after the first, where a divider goes.
    private var dividerIndices: Set<Int> {
        var result: Set<Int> = []
        var index = 0
        for cluster in clusters.dropLast() {
            index += cluster.coreCount
            result.insert(index)
        }
        return result
    }

    var body: some View {
        // Bound once: read inside the ForEach body this rebuilt per core.
        let dividers = dividerIndices
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(cores) { core in
                if dividers.contains(core.id) {
                    Rectangle()
                        .fill(Theme.rule)
                        .frame(width: 1, height: height)
                        .padding(.horizontal, 2)
                }
                CoreBar(busy: core.busy, height: height)
            }
        }
        .frame(height: height)
    }
}

private struct CoreBar: View {
    let busy: Double
    /// Passed down rather than measured: the grid is told its height, so 48
    /// `GeometryReader`s per redraw were reading back a number already in hand.
    let height: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            Rectangle()
                .fill(Theme.coreColor(busy))
                // An idle core keeps a visible stub so the grid reads as a
                // row of cores rather than gaps.
                .frame(height: max(3, height * busy.clamped01))
        }
        .frame(maxWidth: .infinity)
        .background(Theme.track)
    }
}
