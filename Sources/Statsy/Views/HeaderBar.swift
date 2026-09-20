import StatsyKit
import SwiftUI

struct HeaderBar: View {
    let snapshot: Snapshot

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("STATSY")
                .font(Theme.numeral(20))
                .tracking(0.8)
                .foregroundStyle(Theme.channelWhite)
            Rectangle()
                .fill(markerColor)
                .frame(width: 5, height: 5)
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
            Text(snapshot.machine.summary)
                .font(Theme.mono(10))
                .foregroundStyle(Theme.textTertiary)
            Spacer(minLength: 8)
            Text(snapshot.machine.platformVersion)
                .font(Theme.mono(10))
                .foregroundStyle(Theme.textTertiary)
            Text(snapshot.uptimeDescription)
                .font(Theme.mono(10))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    /// The one mark that says which machine is on screen without reading a
    /// word of it: purple for this Mac, yellow once the panel is pointed
    /// somewhere else, and the warning tint when that somewhere has gone quiet.
    private var markerColor: Color {
        switch snapshot.link.state {
        case .local: Theme.purple
        case .live: Theme.yellow
        case .stale, .down: Theme.purpleLight
        }
    }
}
