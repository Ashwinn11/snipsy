import SwiftUI

/// Page 3: the pain.
///
/// The flow used to go straight from "what's worth keeping?" to a run of
/// demos, so every screen after it answered a question nobody had asked —
/// which is exactly why it read as a feature tour. This asks what has
/// actually stopped them, and the next screen replies to it directly.
///
/// Multi-select and entirely skippable: picking nothing leaves `blockers`
/// empty and the following screen keeps its neutral line.
struct OnboardingBlockerPage: View {
    let model: AppModel
    let screenSize: CGSize

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            VStack(spacing: 10) {
                OnboardingTitle("WHAT USUALLY STOPS YOU?")
                Text("Pick whatever's true.")
                    .font(.system(size: 14.5, design: .rounded))
                    .foregroundStyle(Theme.inkSoft)
                    .multilineTextAlignment(.center)
            }

            Spacer(minLength: 0)

            VStack(spacing: 10) {
                ForEach(MemoryBlocker.allCases) { blocker in
                    row(blocker)
                }
            }
            .padding(.horizontal, 26)

            Spacer(minLength: 0)
            Spacer(minLength: 0)
        }
        .padding(.top, 30)
    }

    private func row(_ blocker: MemoryBlocker) -> some View {
        let picked = model.blockers.contains(blocker)
        return Button {
            model.haptics.tick()
            withAnimation(Theme.springTight) {
                if picked {
                    model.blockers.remove(blocker)
                } else {
                    model.blockers.insert(blocker)
                }
            }
        } label: {
            HStack(spacing: 13) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(picked ? Theme.postalRed
                                             : Theme.inkSoft.opacity(0.35),
                                      lineWidth: picked ? 0 : 1.2)
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Theme.postalRed)
                        .opacity(picked ? 1 : 0)
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .opacity(picked ? 1 : 0)
                }
                .frame(width: 22, height: 22)

                Text(blocker.label)
                    .font(.system(size: 14.5, design: .rounded))
                    .foregroundStyle(picked ? Theme.ink : Theme.ink.opacity(0.85))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background(
                RoundedRectangle(cornerRadius: 13)
                    .fill(picked ? Theme.postalRed.opacity(0.05)
                                 : .white.opacity(0.6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 13)
                    .strokeBorder(picked ? Theme.postalRed
                                         : Theme.inkSoft.opacity(0.25),
                                  lineWidth: picked ? 1.8 : 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
    }
}
