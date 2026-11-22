import SwiftUI
import UIKit

/// Colour tokens from the design plan (§6.3), with light and dark values.
enum Theme {
    static let background = Color.dynamic(light: 0xF4F2EE, dark: 0x121214)
    static let surface = Color.dynamic(light: 0xFFFFFF, dark: 0x1C1C1F)
    static let surface2 = Color.dynamic(light: 0xEEEBE5, dark: 0x26262A)
    static let ink = Color.dynamic(light: 0x1C1B19, dark: 0xF2F1EE)
    static let ink2 = Color.dynamic(light: 0x6B6862, dark: 0xA3A09A)
    static let line = Color.dynamic(light: 0xE2DED6, dark: 0x34343A)
    static let accent = Color.dynamic(light: 0x1F7F74, dark: 0x5CC8B8)
    static let accentSoft = Color.dynamic(light: 0xDDEFEC, dark: 0x1E3532)

    static let again = Color(hex: 0xE5484D)
    static let hard = Color(hex: 0xE8930C)
    static let good = Color(hex: 0x2E9E62)
    static let easy = Color(hex: 0x3B7BF5)

    static let cornerRadius: CGFloat = 18
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

extension CourseColour {
    var color: Color { Color(hex: hex) }
}

/// A white rounded card used for Today blocks and course panels.
struct Panel<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
    }
}
