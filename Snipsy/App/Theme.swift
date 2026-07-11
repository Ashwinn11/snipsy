import SwiftUI
import UIKit

/// Snipsy design tokens. See docs/DESIGN.md.
enum Theme {
    // MARK: Palette — the sunny cream album (light-only).
    /// Screen "paper": warm cream pages, a hair lighter than any stamp
    /// paper (stampTint caps V at 0.90) so stamps read as objects on it.
    static let paper      = Color(hex: 0xF8F2E3)
    static let paperDeep  = Color(hex: 0xEFE6D0)
    /// Screen ink: dark warm coffee brown for text/marks ON the cream pages.
    static let ink        = Color(hex: 0x4A3728)
    static let inkSoft    = Color(hex: 0x7E6E58)
    static let postalRed  = Color(hex: 0xD6503A)

    /// Ink INSIDE stamp artifacts — stamps keep their light papers, so
    /// their captions/frames/marks still print dark.
    static let stampInk   = Color(hex: 0x221F1A)
    /// Warm sepia shadow — pure black reads as soot on cream.
    static let shadow     = Color(hex: 0x4A3220)

    // MARK: Springs
    static let spring       = Animation.spring(response: 0.45, dampingFraction: 0.78)
    static let springBouncy = Animation.spring(response: 0.5,  dampingFraction: 0.68)
    static let springTight  = Animation.spring(response: 0.32, dampingFraction: 0.85)

    // MARK: Type
    /// UI chrome — SF Rounded heavy, the die-cut voice. Titles, headers,
    /// and brand marks all speak in this one weight.
    static func display(_ size: CGFloat) -> Font {
        .system(size: size, weight: .heavy, design: .rounded)
    }
    /// Stamp ARTIFACT only — the printed collectible keeps its serif voice.
    static func stampEngraved(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .serif)
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
struct RGBValue: Codable, Equatable {
    var r: Double, g: Double, b: Double
    var color: Color { Color(.sRGB, red: r, green: g, blue: b) }
    var uiColor: UIColor { UIColor(red: r, green: g, blue: b, alpha: 1) }

    static let paper = RGBValue(r: 0.957, g: 0.937, b: 0.902)

    /// Perceived lightness — decides whether a tinted paper takes dark or
    /// cream caption ink (legacy pale tints stay dark-inked and readable).
    var luminance: Double { 0.299 * r + 0.587 * g + 0.114 * b }

    /// Pull an arbitrary color toward rich stamp-paper stock: saturation
    /// floored high and brightness pulled deep, so every photo yields a
    /// saturated collectible that stands off the cream album page.
    static func stampTint(from color: UIColor) -> RGBValue {
        var h: CGFloat = 0, s: CGFloat = 0, v: CGFloat = 0, a: CGFloat = 0
        color.getHue(&h, saturation: &s, brightness: &v, alpha: &a)
        let mutedS = min(max(s * 0.85, 0.42), 0.68)
        let mutedV = min(max(v * 0.85, 0.55), 0.74)
        let out = UIColor(hue: h, saturation: mutedS, brightness: mutedV, alpha: 1)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        out.getRed(&r, green: &g, blue: &b, alpha: &a)
        return RGBValue(r: r, g: g, b: b)
    }
}
