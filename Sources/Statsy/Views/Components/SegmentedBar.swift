import StatsyKit
import SwiftUI

/// A proportional composition bar with a remainder track.
struct SegmentedBar: View {
    struct Segment {
        let fraction: Double
        let color: Color
    }

    let segments: [Segment]

    private static let height: CGFloat = 7

    var body: some View {
        GeometryReader { geometry in
            // Each segment is separated by a one-point gap, including the gap
            // before the remainder, so widths come from what is left.
            let available = max(0, geometry.size.width - CGFloat(segments.count))
            HStack(spacing: 1) {
                // Indexed rather than Identifiable: a per-render UUID would make
                // SwiftUI treat every segment as new on each of these 1 Hz frames.
                ForEach(segments.indices, id: \.self) { index in
                    Rectangle()
                        .fill(segments[index].color)
                        .frame(width: available * segments[index].fraction.clamped01)
                }
                Rectangle().fill(Theme.trackEmpty)
            }
        }
        .frame(height: Self.height)
        .background(Theme.track)
    }
}

/// A thin single-value progress track.
struct MiniTrack: View {
    let fraction: Double
    let color: Color
    var height: CGFloat = 3

    var body: some View {
        GeometryReader { geometry in
            Rectangle()
                .fill(color)
                .frame(width: geometry.size.width * fraction.clamped01)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: height)
        .background(Theme.track)
    }
}
