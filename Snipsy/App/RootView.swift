import SwiftUI

struct RootView: View {
    @State private var model = AppModel()
    /// The home surface's blank memory — a fresh stamp template. Held in
    /// State so the base editor keeps its in-progress work for the session.
    @State private var homeSession = CanvasSession(seed: CanvasDocument.newMemory())
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        // Read the real device insets from a safe-area-respecting reader, then
        // let the content expand edge-to-edge. (A reader that itself ignores
        // the safe area reports zero insets.)
        GeometryReader { geo in
            let insets = geo.safeAreaInsets
            let fullSize = CGSize(
                width: geo.size.width + insets.leading + insets.trailing,
                height: geo.size.height + insets.top + insets.bottom
            )

            ZStack {
                // The memory maker is the app's home — always mounted.
                CanvasEditorScreen(model: model, session: homeSession,
                                   screenSize: fullSize, safeArea: insets,
                                   mode: .home)

                if model.showAlbum {
                    AlbumScreen(model: model, safeArea: insets)
                        .transition(.move(edge: .bottom))
                        .zIndex(10)
                }

                if let session = model.canvasSession {
                    CanvasEditorScreen(model: model, session: session,
                                       screenSize: fullSize, safeArea: insets)
                        .transition(.move(edge: .bottom))
                        .zIndex(20)
                }

                if !model.hasOnboarded {
                    OnboardingScreen(model: model, screenSize: fullSize,
                                     safeArea: insets)
                        .transition(.opacity)
                        .zIndex(30)
                }
            }
            .frame(width: fullSize.width, height: fullSize.height)
            .ignoresSafeArea()
            // The stamp/sticker ceremony — the original camera flow, now a
            // secondary modal launched from the collection.
            .fullScreenCover(isPresented: Binding(
                get: { model.showStampCapture },
                set: { model.showStampCapture = $0 }
            )) {
                StampCaptureFlow(model: model, screenSize: fullSize,
                                 safeArea: insets) {
                    model.showStampCapture = false
                }
            }
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .onChange(of: scenePhase) { _, phase in
            // Stamps kept via the share extension land while we're away —
            // and shares whose sticker couldn't be cut in the extension
            // wait in the inbox for this process to finish them.
            if phase == .active {
                model.store.reload()
                model.drainShareInbox()
            }
        }
        .task { await Self.warmUpShaders() }
    }

    /// Precompile every Metal pipeline the capture moment needs — the first
    /// shutter press must never stall on shader compilation.
    private static func warmUpShaders() async {
        let mask = Image(uiImage: UIImage())
        let layerShaders = [
            ShaderLibrary.grainDissolveRect(
                .float2(1, 1), .float4(0, 0, 1, 1), .float(1), .float(0), .float(9)),
            ShaderLibrary.grainDissolveWaste(
                .float2(1, 1), .float2(0, 0), .image(mask), .float4(0, 0, 1, 1),
                .float(0.5), .float(9)),
        ]
        let colorShaders = [
            ShaderLibrary.paperGrain(.float(0), .float(0.5)),
            ShaderLibrary.fineGrain(.float(0.045)),
            ShaderLibrary.inkBleed(.float(0)),
            ShaderLibrary.holoShimmer(.boundingRect, .float(0), .float2(1, 0), .float(0.5)),
        ]
        for shader in layerShaders {
            try? await shader.compile(as: .layerEffect)
        }
        for shader in colorShaders {
            try? await shader.compile(as: .colorEffect)
        }
        try? await ShaderLibrary.liquidPoke(
            .float2(CGPoint.zero), .float(10), .float(13)
        ).compile(as: .distortionEffect)
    }
}

/// The stamp/sticker ceremony as a self-contained modal: the live camera,
/// the grain-dissolve develop, and the reveal — the app's original flow,
/// now a secondary path reached from the collection. The camera runs only
/// while this cover is up.
struct StampCaptureFlow: View {
    let model: AppModel
    let screenSize: CGSize
    let safeArea: EdgeInsets
    var onClose: () -> Void

    var body: some View {
        ZStack {
            CameraScreen(model: model, screenSize: screenSize,
                         safeArea: safeArea, onClose: onClose)

            // Crossfaded so camera chrome never pops out under an overlay.
            // The frozen frame matches the live feed pixel-for-pixel, so
            // only the chrome visibly fades.
            Group {
                switch model.phase {
                case .camera:
                    EmptyView()
                case .developing(let capture):
                    DevelopOverlay(capture: capture, model: model, screenSize: screenSize)
                        .transition(.opacity)
                case .reveal(let pending):
                    RevealScreen(pending: pending, model: model,
                                 screenSize: screenSize, safeArea: safeArea)
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.2), value: model.phase.kind)

            // Shutter blackout — above every phase, so the frozen frame's
            // heavy first render happens behind it, never as a visible snap.
            Color.black
                .opacity(model.blackout ? 0.88 : 0)
                .animation(.easeOut(duration: model.blackout ? 0.12 : 0.22),
                           value: model.blackout)
                .allowsHitTesting(false)
        }
        .frame(width: screenSize.width, height: screenSize.height)
        .ignoresSafeArea()
        .onAppear { model.camera.start() }
        .onDisappear {
            // Leaving the ceremony: release the camera and reset to idle so
            // reopening always starts clean at the viewfinder.
            model.camera.stop()
            model.phase = .camera
            model.blackout = false
        }
    }
}


