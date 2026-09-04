import SwiftUI

/// Page 4: the interactive beat — the user takes a real photo and watches it
/// become a real stamp that lands in their collection.
///
/// The whole loop, run for real rather than mimed: the live camera, the
/// Vision die-cut, the develop and reveal choreography, and a Keep that
/// writes to the store. They reach the paywall already owning something —
/// which is the point, since the app is gated anyway.
///
/// This is also where the camera permission gets asked, because here it
/// explains itself: a photo is about to be taken. It used to trail after the
/// paywall with no context at all.
struct OnboardingCapturePage: View {
    let model: AppModel
    let screenSize: CGSize
    let safeArea: EdgeInsets

    /// Stamps held before the ceremony opened — anything above this when it
    /// closes means they kept one.
    @State private var countBefore = 0
    @State private var capturing = false
    @State private var madeOne = false
    @State private var asking = false

    private var auth: CameraController.Authorization { model.camera.authorization }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            VStack(spacing: 10) {
                OnboardingTitle(madeOne ? "THAT'S YOURS" : "MAKE YOUR FIRST ONE")
                Text(subhead)
                    .font(.system(size: 14.5, design: .rounded))
                    .foregroundStyle(Theme.inkSoft)
                    .multilineTextAlignment(.center)
                    .animation(.easeOut(duration: 0.25), value: madeOne)
            }

            Spacer(minLength: 0)

            stage

            Spacer(minLength: 0)

            action
                .padding(.bottom, 8)

            Spacer(minLength: 0)
        }
        .padding(.top, 30)
        .fullScreenCover(isPresented: $capturing) {
            ceremony
        }
    }

    private var subhead: LocalizedStringKey {
        if madeOne { return "It's in your collection now —\nand it works as a sticker too." }
        switch auth {
        case .denied:
            return "Camera's off — you can still\nmake one from your library."
        default:
            // Calls back to the occasion answer, so the question they
            // answered two screens ago visibly aimed at this one.
            guard let cue = model.occasion?.captureCue else {
                return "Snap anything — watch it get cut\nand pressed into a stamp."
            }
            return "\(cue)\nWatch it get cut, and kept."
        }
    }

    // MARK: Stage

    private var stampWidth: CGFloat { min(screenSize.width * 0.5, 210) }

    @ViewBuilder
    private var stage: some View {
        if madeOne, let stamp = model.store.stamps.last {
            // `store.image(for:)` hands back the source photo, not the
            // finished piece — the stamp is composed at render time from
            // the stored fields. `ArtifactView` is the app's one renderer
            // for a collected artifact (and handles sticker/polaroid/canvas
            // kinds too), so it's what belongs here.
            ArtifactView(stamp: stamp, image: model.store.image(for: stamp))
                .frame(width: stampWidth)
                .rotationEffect(.degrees(-2))
                .shadow(color: Theme.shadow.opacity(0.28), radius: 18, y: 9)
                .transition(.scale(scale: 0.7).combined(with: .opacity))
        } else {
            PerforatedRect()
                .stroke(Theme.inkSoft.opacity(0.5),
                        style: StrokeStyle(lineWidth: 1.4, dash: [4, 5]))
                .frame(width: stampWidth * 0.78,
                       height: stampWidth * 0.78 * 1.3125)
                .overlay {
                    Image(systemName: auth == .denied ? "photo.on.rectangle" : "camera")
                        .font(.system(size: 26))
                        .foregroundStyle(Theme.inkSoft.opacity(0.8))
                }
        }
    }

    // MARK: Action

    @ViewBuilder
    private var action: some View {
        VStack(spacing: 12) {
            switch auth {
            case .undetermined:
                // Our ask first; the system prompt only fires if they say
                // yes here, so declining leaves it unspent.
                primary(icon: "camera.fill", title: "Enable Camera") {
                    guard !asking else { return }
                    asking = true
                    Task { @MainActor in
                        await model.camera.requestPermission()
                        asking = false
                    }
                }
                .disabled(asking)
                Text("Nothing leaves your device.")
                    .font(.system(size: 12.5, design: .rounded))
                    .foregroundStyle(Theme.inkSoft.opacity(0.85))

            case .denied:
                primary(icon: "gearshape.fill", title: "Open Settings") {
                    model.haptics.tick()
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Text("Or swipe on — add photos\nfrom your library any time.")
                    .font(.system(size: 12.5, design: .rounded))
                    .foregroundStyle(Theme.inkSoft.opacity(0.85))
                    .multilineTextAlignment(.center)

            case .authorized:
                primary(icon: madeOne ? "plus" : "camera.fill",
                        title: madeOne ? "Make another" : "Take a photo") {
                    model.haptics.tick()
                    countBefore = model.store.stamps.count
                    capturing = true
                }
                Text(madeOne ? "One more, or swipe on."
                             : "About ten seconds.")
                    .font(.system(size: 12.5, design: .rounded))
                    .foregroundStyle(Theme.inkSoft.opacity(0.85))
            }
        }
    }

    private func primary(icon: String, title: LocalizedStringKey,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                Text(title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 28)
            .frame(height: 50)
            .background(Theme.postalRed, in: Capsule())
        }
        .buttonStyle(PressableButtonStyle())
    }

    // MARK: The real ceremony

    private var ceremony: some View {
        ZStack {
            // The genuine capture surface — the same one the Camera tab
            // mounts, including its own camera start/stop and phase reset.
            StampCaptureFlow(model: model, screenSize: screenSize,
                             safeArea: safeArea)

            // An exit, since nothing else here offers one while the
            // viewfinder is up. Bottom-left is the one corner the camera
            // chrome leaves empty (the collection pill moved to a tab).
            if model.inCameraPhase {
                Button {
                    model.haptics.tick()
                    capturing = false
                } label: {
                    Text("Not now")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.55), radius: 4, y: 1)
                        .padding(.horizontal, 16)
                        .frame(height: 40)
                        .background(.black.opacity(0.32), in: Capsule())
                }
                .position(x: 68,
                          y: screenSize.height - max(safeArea.bottom, 16) - 54)
            }
        }
        .ignoresSafeArea()
        .onChange(of: model.store.stamps.count) { _, count in
            // Keep lands the stamp in the store — that's the finish line.
            guard count > countBefore else { return }
            withAnimation(Theme.springBouncy) { madeOne = true }
            capturing = false
        }
    }
}
