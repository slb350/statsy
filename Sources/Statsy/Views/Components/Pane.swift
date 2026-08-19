import SwiftUI

/// One of the three metric columns: a titled, ruled panel.
struct Pane<Content: View>: View {
    let title: String
    let accent: Color
    let meta: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Rectangle().fill(accent).frame(width: 7, height: 7)
                Text(title.uppercased())
                    .font(Theme.label(13))
                    .tracking(1.9)
                    .foregroundStyle(accent)
                Spacer(minLength: 4)
                Text(meta)
                    .font(Theme.mono(9.5))
                    .foregroundStyle(Theme.textFaint)
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
    var trailing: String?
    var trailingColor: Color = Theme.textFaint

    var body: some View {
        HStack(spacing: 4) {
            Text(text.uppercased())
                .font(Theme.label(8.5))
                .tracking(1.2)
                .foregroundStyle(Theme.textFaint)
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
