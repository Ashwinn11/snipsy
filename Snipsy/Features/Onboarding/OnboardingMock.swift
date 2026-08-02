import SwiftUI

/// Shared pieces for the onboarding journey mockups: the phone-shaped card
/// both journeys play inside, the real app icon, and deliberately generic
/// stand-ins for other apps (nothing third-party is imitated — only
/// Snipsy is named).

/// Every page's headline. Plus Jakarta Sans ExtraBold — the app's own title
/// voice, the same one Settings and the permission screens use.
///
/// These were set in `RansomText` (per-glyph tiles, each in a different face,
/// colour and rotation). That treatment is right on the canvas, where it's a
/// craft object the user places deliberately, but as onboarding chrome it
/// cost more legibility than it bought character — a headline has one job.
/// `RansomText` is untouched and still available as a text style in the
/// editor.
struct OnboardingTitle: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(Theme.display(19))
            .tracking(1.4)
            .foregroundStyle(Theme.ink)
            .multilineTextAlignment(.center)
            .lineLimit(1)
            // The longest line ("IT LANDS IN THEIR CHAT") still fits the
            // narrowest supported width; this only guards the edges.
            .minimumScaleFactor(0.75)
    }
}

/// The mini phone the journeys play inside — the card shell both showcase
/// pages already shared, with a fixed height so beats never resize it.
struct MockPhoneCard<Content: View>: View {
    let width: CGFloat
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(width: width, height: width * 1.30)
            .background(
                RoundedRectangle(cornerRadius: 28)
                    .fill(Theme.paperDeep)
                    .shadow(color: Theme.shadow.opacity(0.25), radius: 22, y: 12)
            )
            .clipShape(RoundedRectangle(cornerRadius: 28))
            // Cut-line outline: drawn above the clipped content so the demo
            // card reads as a piece set onto the page, not a floating beat.
            .overlay(
                RoundedRectangle(cornerRadius: 28)
                    .strokeBorder(Theme.inkSoft.opacity(0.5),
                                  style: StrokeStyle(lineWidth: 1.4, dash: [5, 5]))
            )
            .allowsHitTesting(false)
    }
}

/// The real app icon, straight from the bundle — the one honest anchor in
/// every mock (share-sheet row, drawer tab).
enum AppIconLoader {
    static let image: UIImage? = {
        // The full 1024² icon art, kept as its own imageset — the bundle's
        // CFBundleIconFiles entry resolves to the 60-pt variant (≤180 px),
        // which visibly upscales at the onboarding's 108-pt size.
        if let art = UIImage(named: "AppIconArt") { return art }
        // Fallback: the largest icon iOS baked into the bundle.
        guard
            let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
            let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
            let files = primary["CFBundleIconFiles"] as? [String],
            let name = files.last
        else { return nil }
        return UIImage(named: name)
    }()
}

struct AppIconView: View {
    let size: CGFloat

    var body: some View {
        if let icon = AppIconLoader.image {
            Image(uiImage: icon)
                .resizable()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.2237))
        } else {
            // Fallback: the die-cut motif on postal red.
            RoundedRectangle(cornerRadius: size * 0.2237)
                .fill(Theme.postalRed)
                .frame(width: size, height: size)
                .overlay {
                    PerforatedRect()
                        .stroke(.white.opacity(0.9), lineWidth: 1)
                        .frame(width: size * 0.4, height: size * 0.52)
                }
        }
    }
}

/// A neutral app tile for light share-sheet rows (white rounded square).
struct MockAppTile: View {
    let size: CGFloat
    var symbol: String? = nil

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.2237)
            .fill(.white)
            .frame(width: size, height: size)
            .overlay {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: size * 0.38, weight: .medium))
                        .foregroundStyle(Color(hex: 0x8E8E93))
                }
            }
    }
}

/// A redacted text stand-in (labels that shouldn't read as real words).
struct MockLabelBar: View {
    enum Tone { case light, dark }
    var width: CGFloat
    var height: CGFloat = 6
    var tone: Tone = .light

    var body: some View {
        Capsule()
            .fill(tone == .light
                  ? Theme.inkSoft.opacity(0.25)
                  : Color(hex: 0xC7C7CC))
            .frame(width: width, height: height)
    }
}
