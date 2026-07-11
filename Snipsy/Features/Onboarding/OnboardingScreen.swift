import SwiftUI

/// First run (and after Delete All Data): four pages on paper. The pitch
/// is a performance — page 1 die-cuts a bundled photo with the real
/// product choreography; pages 2–3 preview the share sheet and Messages
/// drawer in miniature; page 4 holds the legal gate and the camera CTA.
struct OnboardingScreen: View {
    let model: AppModel
    let screenSize: CGSize
    let safeArea: EdgeInsets

    @State private var demo = OnboardingDemo()
    @State private var page = 0
    @State private var showPaywall = false

    var body: some View {
        ZStack {
            PaperBackdrop()

            TabView(selection: $page) {
                OnboardingDemoPage(
                    demo: demo, haptics: model.haptics,
                    isActive: page == 0, screenSize: screenSize)
                    .tag(0)
                OnboardingSharePage(
                    demo: demo, haptics: model.haptics,
                    isActive: page == 1, screenSize: screenSize)
                    .tag(1)
                OnboardingMessagesPage(
                    demo: demo, haptics: model.haptics,
                    isActive: page == 2, screenSize: screenSize)
                    .tag(2)
                OnboardingFinalPage(safeArea: safeArea) {
                    if model.purchases.unlocked {
                        withAnimation(.easeInOut(duration: 0.55)) {
                            model.completeOnboarding()
                        }
                    } else {
                        showPaywall = true
                    }
                }
                .tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            // Perforation-hole page dots.
            HStack(spacing: 9) {
                ForEach(0..<4, id: \.self) { i in
                    Circle()
                        .fill(Theme.inkSoft.opacity(page == i ? 0.9 : 0.3))
                        .frame(width: 6, height: 6)
                }
            }
            .animation(.easeOut(duration: 0.2), value: page)
            .position(x: screenSize.width / 2,
                      y: screenSize.height - max(safeArea.bottom, 16) - 18)

            // Skip to the gate — never past it.
            if page < 3 {
                Button {
                    withAnimation(Theme.spring) { page = 3 }
                } label: {
                    Text("Skip")
                        .font(.system(size: 14, design: .serif))
                        .italic()
                        .foregroundStyle(Theme.inkSoft)
                        .padding(.horizontal, 14)
                        .frame(height: 34)
                }
                .buttonStyle(.plain)
                .position(x: screenSize.width - 44,
                          y: max(safeArea.top, 20) + 18)
                .transition(.opacity)
            }
        }
        .frame(width: screenSize.width, height: screenSize.height)
        .fullScreenCover(isPresented: $showPaywall) {
            PaywallScreen(
                purchases: model.purchases,
                demo: demo,
                screenSize: screenSize,
                safeArea: safeArea,
                onUnlocked: {
                    showPaywall = false
                    withAnimation(.easeInOut(duration: 0.55)) {
                        model.completeOnboarding()
                    }
                },
                onClose: { showPaywall = false }   // back to the last slide
            )
        }
        .onAppear { demo.load() }
    }
}
