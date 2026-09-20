import SwiftUI

/// One of the three metric columns: a titled, ruled panel.
struct Pane<Content: View>: View {
    let title: String
    let accent: Color
    let meta: String
    /// Sits immediately after the title, where `meta` is right-aligned.
    var subtitle: String?
    /// The end of the title row. A GPU card puts its temperature there; the
    /// three metric columns have nothing to put there. A string rather than a
    /// view slot, like `SectionLabel.trailing` below: the pane already owns the
    /// type for its title, subtitle and meta, and owning one more keeps the
    /// cards and the columns at the same weight.
    var trailing: String?
    var trailingColor: Color = Theme.text
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Rectangle().fill(accent).frame(width: 7, height: 7)
                Text(title.uppercased())
                    .font(Theme.label(13))
                    .tracking(1.9)
                    .foregroundStyle(accent)
                if let subtitle {
                    Text(subtitle)
                        .font(Theme.mono(9.5))
                        .foregroundStyle(Theme.textFaint)
                }
                Spacer(minLength: 4)
                Text(meta)
                    .font(Theme.mono(9.5))
                    .foregroundStyle(Theme.textFaint)
                if let trailing {
                    Text(trailing)
                        .font(Theme.numeral(16))
                        .foregroundStyle(trailingColor)
                }
            }
            content
        }
        .padding(.horizontal, 12)
        .padding(.top, 11)
        .padding(.bottom, 9)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.surface)
        .overlay(Rectangle().strokeBorder(Theme.rule, lineWidth: 1))
    }
}

/// A small uppercase caption, used above every sub-section.
struct SectionLabel: View {
    let text: String
    var color: Color = Theme.textFaint
    var trailing: String?
    var trailingColor: Color = Theme.textFaint

    var body: some View {
        HStack(spacing: 4) {
            Text(text.uppercased())
                .font(Theme.label(8.5))
                .tracking(1.2)
                .foregroundStyle(color)
            if let trailing {
                Spacer(minLength: 2)
                Text(trailing.uppercased())
                    .font(Theme.label(8.5))
                    .tracking(1.2)
                    .foregroundStyle(trailingColor)
            }
        }
    }
}
