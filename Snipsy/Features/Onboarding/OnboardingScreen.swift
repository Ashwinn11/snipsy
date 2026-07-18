import SwiftUI

/// First run (and after Delete All Data): five pages on paper. The pitch
/// is a performance — page 1 die-cuts a bundled photo with the real
/// product choreography; page 2 builds a live canvas collage; pages 3–4
/// preview the share sheet and Messages drawer in miniature; page 5 holds
/// the legal gate and the camera CTA.
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
                OnboardingCanvasPage(
                    demo: demo, haptics: model.haptics,
                    isActive: page == 1, screenSize: screenSize)
                    .tag(1)
                OnboardingSharePage(
                    demo: demo, haptics: model.haptics,
                    isActive: page == 2, screenSize: screenSize)
                    .tag(2)
                OnboardingMessagesPage(
                    demo: demo, haptics: model.haptics,
                    isActive: page == 3, screenSize: screenSize)
                    .tag(3)
                OnboardingFinalPage(safeArea: safeArea) {
                    if model.purchases.unlocked {
                        withAnimation(.easeInOut(duration: 0.55)) {
                            model.completeOnboarding()
                        }
                    } else {
                        showPaywall = true
                    }
                }
                .tag(4)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            // Perforation-hole page dots.
            HStack(spacing: 9) {
                ForEach(0..<5, id: \.self) { i in
                    Circle()
                        .fill(page == i ? Theme.postalRed : Theme.inkSoft.opacity(0.3))
                        .frame(width: 6, height: 6)
                }
            }
            .animation(.easeOut(duration: 0.2), value: page)
            .position(x: screenSize.width / 2,
                      y: screenSize.height - max(safeArea.bottom, 16) - 18)

            // Skip to the gate — never past it. Plain ease: a spring's
            // overshoot makes the page-style TabView drop multi-page
            // programmatic jumps on the floor.
            if page < 4 {
                Button {
                    withAnimation(.easeInOut(duration: 0.35)) { page = 4 }
                } label: {
                    Text("Skip")
                        .font(.system(size: 14, design: .rounded))
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
