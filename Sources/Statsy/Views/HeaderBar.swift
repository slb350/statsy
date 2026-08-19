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
                .fill(Theme.purple)
                .frame(width: 5, height: 5)
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
            Text(snapshot.machine.summary)
                .font(Theme.mono(10))
                .foregroundStyle(Theme.textTertiary)
            Spacer(minLength: 8)
            Text("macOS \(snapshot.machine.osVersion)")
                .font(Theme.mono(10))
                .foregroundStyle(Theme.textTertiary)
            Text(snapshot.uptimeDescription)
                .font(Theme.mono(10))
                .foregroundStyle(Theme.textSecondary)
        }
    }
}
