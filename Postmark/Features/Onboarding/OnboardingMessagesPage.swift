import SwiftUI

/// Page 3: the Messages pitch — a mock thread with the demo sticker
/// slapped half-on a bubble, and the drawer beneath with the collection
/// growing. All chrome is drawn here; the sticker itself is the exact
/// StickerArtifact raster Messages would show.
struct OnboardingMessagesPage: View {
    let demo: OnboardingDemo
    let isActive: Bool
    let screenSize: CGSize

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sway = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            VStack(spacing: 10) {
                Text("PEEL THEM IN MESSAGES")
                    .font(Theme.engraved(21))
                    .tracking(4)
                    .foregroundStyle(Theme.ink)
                Text("Every sticker you keep waits in your iMessage drawer.")
                    .font(.system(size: 14.5, design: .serif))
                    .italic()
                    .foregroundStyle(Theme.inkSoft)
                    .multilineTextAlignment(.center)
            }

            Spacer(minLength: 0)

            mockThread

            Spacer(minLength: 0)
            Spacer(minLength: 0)
        }
        .padding(.top, 30)
        .onAppear { if !reduceMotion { sway = true } }
    }

    @ViewBuilder
    private var mockThread: some View {
        let cardWidth = min(screenSize.width * 0.74, 330)

        VStack(spacing: 0) {
            VStack(spacing: 12) {
                HStack {
                    bubble("long day 😮‍💨", fill: Color(hex: 0x26262B))
                    Spacer(minLength: 0)
                }
                HStack {
                    Spacer(minLength: 0)
                    bubble("coffee first", fill: Color(hex: 0x0A84FF))
                }
                // The peeled sticker rides as its own outgoing message,
                // tilted and overlapping the bubble above — the drawer's
                // whole point in one image.
                HStack {
                    Spacer(minLength: 0)
                    if let hero = demo.hero {
                        Image(uiImage: hero.stickerRender)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 118)
                            .rotationEffect(.degrees(sway ? -6.5 : -9.5))
                            .animation(
                                .easeInOut(duration: 2.6)
                                    .repeatForever(autoreverses: true),
                                value: sway)
                            .shadow(color: Theme.shadow.opacity(0.35),
                                    radius: 6, y: 4)
                            .padding(.trailing, 30)
                    }
                }
                .padding(.top, -16)
            }
            .padding(.horizontal, 18)
            .padding(.top, 22)
            .padding(.bottom, 20)

            drawer
        }
        .frame(width: cardWidth)
        .background(
            RoundedRectangle(cornerRadius: 28)
                .fill(Theme.paperDeep)
                .overlay(
                    RoundedRectangle(cornerRadius: 28)
                        .strokeBorder(Theme.inkSoft.opacity(0.15), lineWidth: 1)
                )
                .shadow(color: Theme.shadow.opacity(0.5), radius: 22, y: 12)
        )
        .clipShape(RoundedRectangle(cornerRadius: 28))
        .allowsHitTesting(false)
    }

    private func bubble(_ text: String, fill: Color) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(.white)
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .background(fill, in: RoundedRectangle(cornerRadius: 15))
    }

    /// The drawer: exactly the sticker-browser look — Postmark paper
    /// background, a grabber, and the grid the collection fills in.
    private var drawer: some View {
        VStack(spacing: 12) {
            Capsule()
                .fill(Theme.inkSoft.opacity(0.35))
                .frame(width: 30, height: 4)
                .padding(.top, 9)

            // The full four-subject collection, exactly as the drawer
            // grid would show it.
            HStack(spacing: 14) {
                ForEach(Array(demo.drawer.prefix(4).enumerated()),
                        id: \.offset) { _, render in
                    Image(uiImage: render)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 58, height: 62)
                }
                // Until the cuts land (or if any failed): dashed slots.
                ForEach(0..<max(0, 4 - demo.drawer.count), id: \.self) { _ in
                    PerforatedRect()
                        .stroke(Theme.inkSoft.opacity(0.25),
                                style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                        .frame(width: 46, height: 58)
                }
            }
            .frame(maxWidth: .infinity)

            Text("Your collection grows here")
                .font(.system(size: 11.5, design: .serif))
                .italic()
                .foregroundStyle(Theme.inkSoft.opacity(0.7))
                .padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 16, topTrailingRadius: 16)
                .fill(Theme.paper)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Theme.inkSoft.opacity(0.12))
                        .frame(height: 1)
                }
        )
    }
}
