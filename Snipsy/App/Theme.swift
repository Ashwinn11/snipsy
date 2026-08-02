import SwiftUI
import UIKit

/// Snipsy design tokens. See docs/DESIGN.md.
enum Theme {
    // MARK: Palette — the off-white album (light-only).
    /// Screen "paper": a warm off-white. Deliberately NOT pure white —
    /// white is the die-cut outline, and the page must never compete with
    /// it — but close enough that stamps and folders read as objects
    /// sitting on a sheet rather than on a cream card.
    static let paper      = Color(hex: 0xF4F2ED)
    static let paperDeep  = Color(hex: 0xE8E5DD)
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
    /// The app's voice: Plus Jakarta Sans, bundled under Resources/Fonts.
    ///
    /// The chrome used to speak in SF Rounded Heavy — the same face the
    /// die cut prints in (see `DieCutText`). That made the app read as a
    /// sticker rather than as the shelf a sticker sits on. The two voices
    /// are now deliberately different: the die cut keeps SF Rounded Heavy,
    /// everything else speaks here.
    enum Face: String {
        case regular   = "PlusJakartaSans-Regular"
        case medium    = "PlusJakartaSans-Medium"
        case semibold  = "PlusJakartaSans-SemiBold"
        case bold      = "PlusJakartaSans-Bold"
        case extraBold = "PlusJakartaSans-ExtraBold"
    }

    /// Titles, headers and month names.
    static func display(_ size: CGFloat) -> Font {
        .custom(Face.extraBold.rawValue, fixedSize: size)
    }

    /// Everything else — counts, captions, controls, body.
    static func ui(_ size: CGFloat, _ face: Face = .medium) -> Font {
        .custom(face.rawValue, fixedSize: size)
    }
    /// Stamp ARTIFACT only — the printed collectible keeps its serif voice.
    static func stampEngraved(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .serif)
    }
    /// Pen-on-polaroid captions and canvas text. Bradley Hand ships with
    /// iOS; Noteworthy is the documented fallback.
    static func handwritten(_ size: CGFloat) -> Font {
        if UIFont(name: "BradleyHandITCTT-Bold", size: size) != nil {
            return .custom("BradleyHandITCTT-Bold", size: size)
        }
        return .custom("Noteworthy-Bold", size: size)
    }
    /// Flourished calligraphy for canvas text. Snell Roundhand ships with
    /// iOS; Savoye LET is the fallback.
    static func script(_ size: CGFloat) -> Font {
        if UIFont(name: "SnellRoundhand-Black", size: size) != nil {
            return .custom("SnellRoundhand-Black", size: size)
        }
        return .custom("SavoyeLetPlain", size: size)
    }
    /// Vintage typewriter voice for canvas text — more on-brand for the
    /// postal theme than the plain monospaced design.
    static func typewriter(_ size: CGFloat) -> Font {
        if UIFont(name: "AmericanTypewriter-Bold", size: size) != nil {
            return .custom("AmericanTypewriter-Bold", size: size)
        }
        return .system(size: size, weight: .bold, design: .monospaced)
    }
    /// A genuinely engraved-stamp voice for canvas text. Academy Engraved
    /// LET ships with iOS.
    static func engraved(_ size: CGFloat) -> Font {
        if UIFont(name: "AcademyEngravedLetPlain", size: size) != nil {
            return .custom("AcademyEngravedLetPlain", size: size)
        }
        return .system(size: size, weight: .semibold, design: .serif)
    }
    /// A playful marker voice for canvas text. Marker Felt ships with iOS.
    static func marker(_ size: CGFloat) -> Font {
        if UIFont(name: "MarkerFelt-Wide", size: size) != nil {
            return .custom("MarkerFelt-Wide", size: size)
        }
        return .system(size: size, weight: .bold, design: .rounded)
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
    var color: Color { Color(.sRGB, red: safe(r), green: safe(g), blue: safe(b)) }
    var uiColor: UIColor {
        UIColor(red: safe(r), green: safe(g), blue: safe(b), alpha: 1)
    }

    /// Components come out of Vision's frame sampling and are then written
    /// into the stamp index, so a single bad value would be baked into a
    /// saved stamp permanently and UIColor would log about it on every
    /// render. Clamp where the value leaves the model, not where it's made.
    private func safe(_ v: Double) -> Double {
        v.isFinite ? min(max(v, 0), 1) : 0
    }

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
