import StatsyKit
import SwiftUI

/// The panel's visual system.
///
/// Colours are the nonbinary pride flag's — purple and yellow as the two data
/// hues, white as the third channel, near-black ground. Type is sized for a
/// 1280x480 panel at backing scale 1.0 over seven inches (~195 PPI), where
/// everything renders at roughly 56% of its usual physical size.
enum Theme {
    static let ground = Color(hex: 0x0A0910)
    static let surface = Color(hex: 0x131118)
    static let rule = Color(hex: 0x2C2C2C)

    static let purple = Color(hex: 0x9C59D1)
    static let purpleLight = Color(hex: 0xC79BEA)
    static let yellow = Color(hex: 0xFCF434)
    static let yellowDim = Color(hex: 0x8E8A24)
    static let channelWhite = Color.white

    static let text = Color(hex: 0xF4F2F7)
    static let textSecondary = Color(hex: 0x9E98AE)
    static let textTertiary = Color(hex: 0x635D73)
    static let textFaint = Color(hex: 0x4E4960)

    static let track = Color(hex: 0x1E1B26)
    static let trackEmpty = Color(hex: 0x221F2B)

    /// Large figures. SF Pro Compressed stands in for the mockup's Saira Condensed.
    static func numeral(_ size: CGFloat) -> Font {
        .system(size: size, weight: .heavy).width(.compressed).monospacedDigit()
    }

    /// Small uppercase labels.
    static func label(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold).width(.condensed)
    }

    /// Tabular data and process names.
    static func mono(_ size: CGFloat) -> Font {
        .system(size: size, weight: .regular, design: .monospaced)
    }

    /// Maps a temperature onto the purple-to-yellow ramp used throughout.
    ///
    /// 30C reads as purple and 90C as yellow, which keeps idle sensors calm and
    /// makes a hot cluster unmistakable.
    static func temperature(_ celsius: Double) -> Color {
        let t = temperatureFraction(celsius)
        return Color(
            red: (0x9C + (0xFC - 0x9C) * t) / 255,
            green: (0x59 + (0xF4 - 0x59) * t) / 255,
            blue: (0xD1 + (0x34 - 0xD1) * t) / 255
        )
    }

    /// Where a temperature sits on that ramp, 0...1.
    ///
    /// Shared so a reading's colour and its track cannot disagree about what
    /// counts as hot.
    static func temperatureFraction(_ celsius: Double) -> Double {
        ((celsius - 30) / 60).clamped01
    }

    /// Volume colours, keyed by role rather than by display name.
    static func volume(_ role: VolumeRole) -> Color {
        switch role {
        case .data: channelWhite
        case .swap: yellow
        case .system: purple
        }
    }

    /// A core bar turns yellow once it is carrying real load.
    static func coreColor(_ busy: Double) -> Color {
        busy > 0.4 ? yellow : purple
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
