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

    private static let height: CGFloat = 30

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
                        .frame(width: 1, height: Self.height)
                        .padding(.horizontal, 2)
                }
                CoreBar(busy: core.busy)
            }
        }
        .frame(height: Self.height)
    }
}

private struct CoreBar: View {
    let busy: Double

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                Rectangle()
                    .fill(Theme.coreColor(busy))
                    // An idle core keeps a visible stub so the grid reads as a
                    // row of cores rather than gaps.
                    .frame(height: max(3, geometry.size.height * busy.clamped01))
            }
        }
        .background(Theme.track)
        .frame(maxWidth: .infinity)
    }
}
