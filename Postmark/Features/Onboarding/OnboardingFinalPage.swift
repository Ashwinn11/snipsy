import SwiftUI

/// Page 4: the gate. The breathing die-cut motif foreshadows the camera,
/// the copy sets the permission expectation, and the legal line + CTA
/// complete onboarding (which starts the camera and its prompt).
struct OnboardingFinalPage: View {
    let model: AppModel
    let safeArea: EdgeInsets
    @Binding var doc: LegalDoc?

    @State private var breathe = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            PerforatedRect()
                .stroke(Theme.inkSoft.opacity(0.55),
                        style: StrokeStyle(lineWidth: 1.4, dash: [4, 5]))
                .frame(width: 116, height: 152)
                .overlay {
                    Image(systemName: "camera")
                        .font(.system(size: 24))
                        .foregroundStyle(Theme.inkSoft.opacity(0.8))
                }
                .scaleEffect(breathe ? 1.03 : 0.99)
                .animation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true),
                           value: breathe)

            VStack(spacing: 10) {
                Text("START YOUR COLLECTION")
                    .font(Theme.engraved(21))
                    .tracking(4)
                    .foregroundStyle(Theme.ink)
                Text("Postmark opens straight into the camera —\nyou'll be asked for access once.\nEverything is cut and kept on your device.")
                    .font(.system(size: 14.5, design: .serif))
                    .italic()
                    .foregroundStyle(Theme.inkSoft)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }
            .padding(.top, 34)

            Spacer(minLength: 0)

            VStack(spacing: 18) {
                Button {
                    withAnimation(.easeInOut(duration: 0.55)) {
                        model.completeOnboarding()
                    }
                } label: {
                    Text("Start Collecting")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 42)
                        .frame(height: 54)
                        .background(Theme.postalRed, in: Capsule())
                }
                .buttonStyle(PressableButtonStyle())

                HStack(spacing: 4) {
                    Text("By continuing you agree to the")
                    Button { doc = .terms } label: {
                        Text("Terms").underline()
                    }
                    Text("and")
                    Button { doc = .privacy } label: {
                        Text("Privacy Policy").underline()
                    }
                }
                .font(.system(size: 12.5, design: .serif))
                .foregroundStyle(Theme.inkSoft)
                .buttonStyle(.plain)
            }
            .padding(.bottom, max(safeArea.bottom, 16) + 54)
        }
        .padding(.top, 30)
        .onAppear { breathe = true }
    }
}
