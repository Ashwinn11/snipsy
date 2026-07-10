import SwiftUI
import UIKit

/// Postmark design tokens. See docs/DESIGN.md.
enum Theme {
    // MARK: Palette — the collector's black album (dark-only).
    /// Screen "paper": deep warm charcoal pages.
    static let paper      = Color(hex: 0x18150F)
    static let paperDeep  = Color(hex: 0x0F0D0A)
    /// Screen ink: warm light for text/marks ON the dark pages.
    static let ink        = Color(hex: 0xEBE4D6)
    static let inkSoft    = Color(hex: 0x9C9482)
    static let postalRed  = Color(hex: 0xD6503A)

    /// Ink INSIDE stamp artifacts — stamps keep their light papers, so
    /// their captions/frames/marks still print dark.
    static let stampInk   = Color(hex: 0x221F1A)
    /// True shadow color (screen ink is light now; it would glow).
    static let shadow     = Color.black

    // MARK: Springs
    static let spring       = Animation.spring(response: 0.45, dampingFraction: 0.78)
    static let springBouncy = Animation.spring(response: 0.5,  dampingFraction: 0.68)
    static let springTight  = Animation.spring(response: 0.32, dampingFraction: 0.85)

    // MARK: Type
    /// Engraved caps used on stamp captions and day headers.
    static func engraved(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .serif)
    }
    static func serifDisplay(_ size: CGFloat) -> Font {
        .system(size: size, weight: .bold, design: .serif)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red:   Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8)  & 0xFF) / 255,
            blue:  Double(hex & 0xFF) / 255
        )
    }
}

/// A codable sRGB triple used to persist stamp tints.
extension Color {
    /// A juicy, subject-matched label ink: same hue as the stamp tint,
    /// re-saturated for sticker lettering (the tint itself is muted
    /// toward paper).
    var vividLabel: Color {
        let ui = UIColor(self)
        var h: CGFloat = 0, s: CGFloat = 0, v: CGFloat = 0, a: CGFloat = 0
        ui.getHue(&h, saturation: &s, brightness: &v, alpha: &a)
        return Color(hue: h,
                     saturation: min(max(s * 2.4, 0.52), 0.80),
                     brightness: min(max(v * 0.85, 0.55), 0.80))
    }
}

struct RGBValue: Codable, Equatable {
    var r: Double, g: Double, b: Double
    var color: Color { Color(.sRGB, red: r, green: g, blue: b) }
    var uiColor: UIColor { UIColor(red: r, green: g, blue: b, alpha: 1) }

    static let paper = RGBValue(r: 0.957, g: 0.937, b: 0.902)

    /// Mute an arbitrary color toward collectible stamp paper:
    /// clamp saturation + lift brightness so photos of anything yield a
    /// harmonious album.
    static func stampTint(from color: UIColor) -> RGBValue {
        var h: CGFloat = 0, s: CGFloat = 0, v: CGFloat = 0, a: CGFloat = 0
        color.getHue(&h, saturation: &s, brightness: &v, alpha: &a)
        // Floor saturation and cap brightness so the stamp always sits
        // clearly deeper than the album paper behind it (S≈0.06, V≈0.96).
        let mutedS = min(max(s * 0.6, 0.16), 0.34)
        let mutedV = min(max(v, 0.84), 0.90)
        let out = UIColor(hue: h, saturation: mutedS, brightness: mutedV, alpha: 1)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        out.getRed(&r, green: &g, blue: &b, alpha: &a)
        return RGBValue(r: r, g: g, b: b)
    }
}
