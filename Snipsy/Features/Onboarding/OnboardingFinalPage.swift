import SwiftUI

/// Page 5: the gate. The app icon breathes over the closing pitch and the
/// CTA hands off to the paywall (or straight to the canvas, once unlocked).
struct OnboardingFinalPage: View {
    let safeArea: EdgeInsets
    var onStart: () -> Void

    @State private var breathe = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            AppIconView(size: 108)
                .shadow(color: Theme.shadow.opacity(0.22), radius: 16, y: 8)
                .scaleEffect(breathe ? 1.03 : 0.99)
                .animation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true),
                           value: breathe)

            VStack(spacing: 10) {
                RansomText(text: "MAKE THE FIRST ONE", fontSize: 14, ink: Theme.ink)
                Text("One page after every date.\nThey'll start waiting for it.")
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
                Text("Make a Memory")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 42)
                    .frame(height: 54)
                    .background(Theme.postalRed, in: Capsule())
            }
            .buttonStyle(PressableButtonStyle())
            .padding(.bottom, max(safeArea.bottom, 16) + 54)
        }
        .padding(.top, 30)
        .onAppear { breathe = true }
    }
}
