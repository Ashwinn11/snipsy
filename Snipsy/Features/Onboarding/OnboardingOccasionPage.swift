import SwiftUI

/// Page 2: the one question. What the user picks is not flavour text — it
/// chooses the paper on the very next page (`OnboardingBuildPage`) and then
/// leads the real template chooser for good (`CanvasTemplateChooserSheet`).
/// Skipping is free: `occasion` stays nil and every surface keeps its
/// default, nothing is hidden either way.
struct OnboardingOccasionPage: View {
    let model: AppModel
    let screenSize: CGSize

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            VStack(spacing: 10) {
                OnboardingTitle("WHAT'S WORTH KEEPING TO YOU?")
                Text("Answer once, and everything after\nis about yours.")
                    .font(.system(size: 14.5, design: .rounded))
                    .foregroundStyle(Theme.inkSoft)
                    .multilineTextAlignment(.center)
            }

            Spacer(minLength: 0)

            VStack(spacing: 11) {
                ForEach(MemoryOccasion.allCases) { choice in
                    row(choice)
                }
            }
            .padding(.horizontal, 30)

            Text("Pick again whenever you like.")
                .font(.system(size: 12.5, design: .rounded))
                .foregroundStyle(Theme.inkSoft.opacity(0.8))
                .padding(.top, 20)

            Spacer(minLength: 0)
            Spacer(minLength: 0)
        }
        .padding(.top, 30)
    }

    private func row(_ choice: MemoryOccasion) -> some View {
        let selected = model.occasion == choice
        return Button {
            model.haptics.tick()
            withAnimation(Theme.springTight) {
                // Tapping the current pick clears it — the question stays
                // genuinely optional after it's been answered.
                model.occasion = selected ? nil : choice
            }
        } label: {
            HStack(spacing: 14) {
                // The paper each answer opens on, shown at thumbnail size —
                // the choice previews its own consequence rather than
                // describing it.
                CanvasBackgroundView(background: choice.background)
                    .frame(width: 34)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .shadow(color: Theme.shadow.opacity(0.18), radius: 3, y: 2)

                VStack(alignment: .leading, spacing: 2) {
                    Text(choice.label)
                        .font(.system(size: 15.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(selected ? Theme.postalRed : Theme.ink)
                    Text(choice.blurb)
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(Theme.inkSoft)
                }

                Spacer(minLength: 0)

                Image(systemName: selected ? "checkmark.circle.fill" : choice.symbol)
                    .font(.system(size: selected ? 17 : 14, weight: .medium))
                    .foregroundStyle(selected ? Theme.postalRed : Theme.inkSoft.opacity(0.7))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 13)
                    .fill(selected ? Theme.postalRed.opacity(0.05) : .white.opacity(0.6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 13)
                    .strokeBorder(selected ? Theme.postalRed : Theme.inkSoft.opacity(0.25),
                                  lineWidth: selected ? 1.8 : 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
    }
}
