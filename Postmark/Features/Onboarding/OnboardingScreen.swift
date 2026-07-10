import SwiftUI

/// First run (and after Delete All Data): the pitch, the ritual in three
/// beats, and the legal gate — all on paper.
struct OnboardingScreen: View {
    let model: AppModel
    let screenSize: CGSize
    let safeArea: EdgeInsets

    @State private var stage = 0
    @State private var breathe = false
    @State private var doc: LegalDoc? = nil

    var body: some View {
        ZStack {
            PaperBackdrop(showsGrid: true)

            VStack(spacing: 0) {
                Spacer(minLength: 0)

                // The die-cut motif, breathing.
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
                    .entrance(shown: stage >= 1)

                VStack(spacing: 10) {
                    Text("POSTMARK")
                        .font(Theme.engraved(24))
                        .tracking(7)
                        .foregroundStyle(Theme.ink)
                    Text("Turn what you see into stamps.")
                        .font(.system(size: 16, design: .serif))
                        .italic()
                        .foregroundStyle(Theme.inkSoft)
                }
                .padding(.top, 30)
                .entrance(shown: stage >= 2)

                VStack(alignment: .leading, spacing: 20) {
                    step("camera.fill", "Shoot",
                         "Frame something you love in the viewfinder.")
                        .entrance(shown: stage >= 3)
                    step("scissors", "Die-cut",
                         "Your subject is lifted and cut, right on device.")
                        .entrance(shown: stage >= 4)
                    step("books.vertical.fill", "Collect",
                         "Choose its paper, stamp the date, keep it forever.")
                        .entrance(shown: stage >= 5)
                }
                .padding(.top, 40)
                .padding(.horizontal, 54)

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

                    legalLine
                }
                .padding(.bottom, max(safeArea.bottom, 16) + 18)
                .entrance(shown: stage >= 6)
            }
        }
        .frame(width: screenSize.width, height: screenSize.height)
        .sheet(item: $doc) { LegalDocView(doc: $0) }
        .onAppear {
            breathe = true
            Task { @MainActor in
                await afterNextCommit()
                for s in 1...6 {
                    withAnimation(.spring(response: 0.55, dampingFraction: 0.85)) {
                        stage = s
                    }
                    try? await Task.sleep(for: .seconds(0.14))
                }
            }
        }
    }

    private var legalLine: some View {
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

    private func step(_ icon: String, _ title: String, _ line: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Theme.postalRed)
                .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(Theme.engraved(15))
                    .foregroundStyle(Theme.ink)
                Text(line)
                    .font(.system(size: 14, design: .serif))
                    .foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private extension View {
    /// Staged entrance: fade up in order.
    func entrance(shown: Bool) -> some View {
        opacity(shown ? 1 : 0).offset(y: shown ? 0 : 16)
    }
}
