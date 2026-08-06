import SwiftUI

/// First run (and after Delete All Data): eight pages on paper, ordered as an
/// argument rather than a reel of demos —
///
///   1 the problem · 2 what's worth keeping (goal) · 3 what stops you (pain)
///   4 the reply, die-cut with the real choreography · 5 they keep a real one
///   6 old photos count too · 7 it becomes a sticker · 8 the close
///
/// Screens 2 and 3 are what stop the rest reading as a feature tour: every
/// screen after them is answering something the user said.
struct OnboardingScreen: View {
    let model: AppModel
    let screenSize: CGSize
    let safeArea: EdgeInsets

    private static let pageCount = 8
    private static let lastPage = pageCount - 1

    @State private var demo = OnboardingDemo()
    @State private var page = 0
    @State private var showPaywall = false
    /// Between paying and landing in the app: the one moment where asking
    /// for the camera has full context. See `CameraPermissionPrimerView`.
    @State private var showCameraPrimer = false

    var body: some View {
        ZStack {
            PaperBackdrop()

            TabView(selection: $page) {
                OnboardingCanvasPage(
                    demo: demo, haptics: model.haptics,
                    isActive: page == 0, screenSize: screenSize)
                    .tag(0)
                // Asked immediately after the problem is named, so it reads
                // as "so what's yours?" — and everything after it is an
                // answer rather than another demo.
                OnboardingOccasionPage(model: model, screenSize: screenSize)
                    .tag(1)
                // Goal, then pain, then the reply — without the pain screen
                // everything downstream answered a question never asked.
                OnboardingBlockerPage(model: model, screenSize: screenSize)
                    .tag(2)
                OnboardingDemoPage(
                    demo: demo, haptics: model.haptics,
                    isActive: page == 3, screenSize: screenSize,
                    blocker: model.leadBlocker)
                    .tag(3)
                OnboardingCapturePage(model: model, screenSize: screenSize,
                                      safeArea: safeArea)
                    .tag(4)
                OnboardingSharePage(
                    demo: demo, haptics: model.haptics,
                    isActive: page == 5, screenSize: screenSize)
                    .tag(5)
                OnboardingMessagesPage(
                    demo: demo, haptics: model.haptics,
                    isActive: page == 6, screenSize: screenSize)
                    .tag(6)
                // Closes on the outcome — what a year of this leaves you
                // with — then asks. The paywall is the gate, always: an
                // existing entitlement doesn't skip it. Premium users
                // restore from inside it.
                OnboardingFinalPage(model: model, safeArea: safeArea) {
                    showPaywall = true
                }
                .tag(Self.lastPage)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            // Perforation-hole page dots.
            HStack(spacing: 9) {
                ForEach(0..<Self.pageCount, id: \.self) { i in
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
            // One top row rather than two fixed points. `.position()` centres
            // a view on a coordinate, so a longer translation grew straight
            // off the edge — "Skip" is 4 characters, "Überspringen" is 12.
            // Anchoring the row keeps both inset from the margin at any width.
            VStack {
                HStack(alignment: .center, spacing: 12) {
                    if page == 0 {
                        LanguageBadge()
                            .transition(.opacity)
                    }
                    Spacer(minLength: 8)
                    if page < Self.lastPage {
                        // Metrics and material copied from `LanguageBadge`,
                        // not approximated: the two share this row, and a
                        // bare label beside a glass capsule read as an
                        // unfinished control rather than a quieter one.
                        Button {
                            withAnimation(.easeInOut(duration: 0.35)) { page = Self.lastPage }
                        } label: {
                            Text("Skip")
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(Theme.inkSoft)
                                .lineLimit(1)
                                .padding(.horizontal, 12)
                                .frame(height: 32)
                                .contentShape(Capsule())
                        }
                        .glassEffect(.regular.interactive(), in: .capsule)
                        .transition(.opacity)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, max(safeArea.top, 20))
                Spacer(minLength: 0)
            }
            .frame(width: screenSize.width, height: screenSize.height, alignment: .top)
        }
        .frame(width: screenSize.width, height: screenSize.height)
        .fullScreenCover(isPresented: $showPaywall) {
            PaywallScreen(
                purchases: model.purchases,
                demo: demo,
                occasion: model.occasion,
                screenSize: screenSize,
                safeArea: safeArea,
                onUnlocked: {
                    showPaywall = false
                    // The capture page normally asks in context and this
                    // never runs. It's the backstop for anyone who swiped
                    // straight past it, so the app is never entered with an
                    // unasked camera and a dead viewfinder.
                    if model.camera.authorization == .undetermined {
                        showCameraPrimer = true
                    } else {
                        withAnimation(.easeInOut(duration: 0.55)) {
                            model.completeOnboarding()
                        }
                    }
                },
                onClose: { showPaywall = false }   // back to the last slide
            )
        }
        .fullScreenCover(isPresented: $showCameraPrimer) {
            // Onboarding isn't complete until this resolves, so the app is
            // never entered with an unasked camera and a black viewfinder.
            CameraPermissionPrimerView(model: model) {
                showCameraPrimer = false
                withAnimation(.easeInOut(duration: 0.55)) {
                    model.completeOnboarding()
                }
            }
        }
        .onAppear { demo.load() }
    }
}
