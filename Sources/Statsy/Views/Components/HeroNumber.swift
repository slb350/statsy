import SwiftUI

/// The large headline figure at the top of each pane.
struct HeroNumber: View {
    let value: String
    let color: Color
    let captionLabel: String
    let caption: String
    var secondary: Secondary?

    /// A smaller figure beside the headline, at the same baseline. The
    /// processor pane uses it for a unified GPU's utilisation, which has no
    /// pane of its own.
    struct Secondary {
        let label: String
        let value: String
        let color: Color
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Text(value)
                .font(Theme.numeral(72))
                .foregroundStyle(color)
                // The compressed face carries generous leading; trimming it is
                // what keeps the pane's vertical budget workable at 480px.
                .padding(.vertical, -12)
            Text("%")
                .font(Theme.label(16))
                .foregroundStyle(Theme.textTertiary)
            if let secondary {
                Text(secondary.label.uppercased())
                    .font(Theme.label(9))
                    .tracking(1.3)
                    .foregroundStyle(Theme.textFaint)
                Text(secondary.value)
                    .font(Theme.numeral(26))
                    .foregroundStyle(secondary.color)
                    .padding(.vertical, -4)
                Text("%")
                    .font(Theme.label(10))
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 2) {
                Text(captionLabel.uppercased())
                    .font(Theme.label(9))
                    .tracking(1.3)
                    .foregroundStyle(Theme.textFaint)
                Text(caption)
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }
}
