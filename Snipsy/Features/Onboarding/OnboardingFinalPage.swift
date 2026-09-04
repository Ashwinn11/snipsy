import SwiftUI

/// Page 8: the close.
///
/// Shows the one stamp they actually made, and nothing else. An earlier
/// version drew a twelve-slot shelf filling up to sell "a year of this" —
/// but eleven of those twelve were fabricated, the same blank paper
/// repeated. A collection they don't have is a lie to look at and dull to
/// look at. The future belongs in the copy; the screen shows only what's
/// real.
///
/// One idea only: celebrate what they just made (or the habit they're
/// about to start) and hand off into the paywall. Canvas is not named
/// here — this screen's whole job is the stamp habit; the paywall's own
/// bridging line is where the next idea belongs, not stacked onto this one.
struct OnboardingFinalPage: View {
    let model: AppModel
    let safeArea: EdgeInsets
    var onStart: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var shown = false
    @State private var breathe = false

    /// Their own first artifact, if the capture screen produced one.
    private var mine: Stamp? { model.store.stamps.last }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            hero

            VStack(spacing: 10) {
                OnboardingTitle(mine == nil ? "MAKE THE FIRST ONE" : "THAT'S NUMBER ONE")
                Text(mine == nil
                     ? "One a day, and by next year —\na shelf of them."
                     : "One down. Do it again tomorrow.\nBy next year, a shelf of them.")
                    .font(.system(size: 14.5, design: .rounded))
                    .foregroundStyle(Theme.inkSoft)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }
            .padding(.top, 34)

            Spacer(minLength: 0)

            Button {
                onStart()
            } label: {
                Text(mine == nil ? "Make My First One" : "Start my collection")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 38)
                    .frame(height: 54)
                    .background(Theme.postalRed, in: Capsule())
            }
            .buttonStyle(PressableButtonStyle())
            .padding(.bottom, max(safeArea.bottom, 16) + 54)
        }
        .padding(.top, 30)
        .onAppear {
            breathe = true
            if reduceMotion {
                shown = true
            } else {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.78)) {
                    shown = true
                }
            }
        }
    }

    @ViewBuilder
    private var hero: some View {
        if let mine {
            // The app's one renderer for a collected artifact — the stamp
            // is composed from the stored fields, not read off disk (the
            // file is just the source photo).
            ArtifactView(stamp: mine, image: model.store.image(for: mine))
                .frame(width: 170)
                .rotationEffect(.degrees(-2))
                .shadow(color: Theme.shadow.opacity(0.28), radius: 18, y: 9)
                .scaleEffect(shown ? 1 : 0.85)
                .opacity(shown ? 1 : 0)
        } else {
            // They skipped the capture — nothing of theirs to show.
            AppIconView(size: 108)
                .shadow(color: Theme.shadow.opacity(0.22), radius: 16, y: 8)
                .scaleEffect(breathe ? 1.03 : 0.99)
                .animation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true),
                           value: breathe)
        }
    }
}
