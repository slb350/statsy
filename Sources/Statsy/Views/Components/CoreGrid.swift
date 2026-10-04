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

    /// The narrowest bar that still reads as a bar. Below it the grid wraps
    /// onto two rows; on Linux the second row is then each core's SMT
    /// sibling, since the kernel numbers first threads before seconds.
    /// Width rather than core count decides, because a fourth column narrows
    /// this pane: 48 threads fit one row in three columns and not in four.
    private static let minimumBarWidth: CGFloat = 7

    private func rows(width: CGFloat, dividers: Int) -> [ArraySlice<CoreLoad>] {
        let gaps = CGFloat(max(cores.count - 1, 0)) * 2 + CGFloat(dividers) * 5
        let barWidth = (width - gaps) / CGFloat(max(cores.count, 1))
        guard barWidth < Self.minimumBarWidth, cores.count > 1 else { return [cores[...]] }
        let half = (cores.count + 1) / 2
        return [cores[..<half], cores[half...]]
    }

    var body: some View {
        // Bound once: read inside the ForEach body this rebuilt per core.
        let dividers = dividerIndices
        GeometryReader { geometry in
            let rows = rows(width: geometry.size.width, dividers: dividers.count)
            let rowHeight = (height - CGFloat(rows.count - 1) * 2) / CGFloat(rows.count)
            VStack(spacing: 2) {
                ForEach(rows.indices, id: \.self) { row in
                    HStack(alignment: .bottom, spacing: 2) {
                        ForEach(rows[row]) { core in
                            if dividers.contains(core.id) {
                                Rectangle()
                                    .fill(Theme.rule)
                                    .frame(width: 1, height: rowHeight)
                                    .padding(.horizontal, 2)
                            }
                            CoreBar(busy: core.busy, height: rowHeight)
                        }
                    }
                }
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
