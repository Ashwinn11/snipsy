import SwiftUI

struct RootView: View {
    @State private var model = AppModel()

    @State private var screenSize: CGSize = .zero

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
                CameraScreen(model: model, screenSize: fullSize, safeArea: insets)

                // Crossfaded so camera chrome never pops out under an overlay.
                // The frozen frame matches the live feed pixel-for-pixel, so
                // only the chrome visibly fades.
                Group {
                    switch model.phase {
                    case .camera:
                        EmptyView()
                    case .developing(let capture):
                        DevelopOverlay(capture: capture, model: model, screenSize: fullSize)
                            .transition(.opacity)
                    case .reveal(let pending):
                        RevealScreen(pending: pending, model: model,
                                     screenSize: fullSize, safeArea: insets)
                            .transition(.opacity)
                    }
                }
                .animation(.easeOut(duration: 0.2), value: model.phase.kind)

                // Shutter blackout — above every phase, so the frozen frame's
                // heavy first render happens behind it, never as a visible
                // snap. Fades in fast on capture, eases out once the develop
                // overlay has actually committed a frame.
                Color.black
                    .opacity(model.blackout ? 0.88 : 0)
                    .animation(.easeOut(duration: model.blackout ? 0.12 : 0.22),
                               value: model.blackout)
                    .allowsHitTesting(false)

                if model.showAlbum {
                    AlbumScreen(model: model, safeArea: insets)
                        .transition(.move(edge: .bottom))
                        .zIndex(10)
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
            .onAppear { screenSize = fullSize }
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .onAppear {
            // The camera (and its permission prompt) waits for onboarding.
            if model.hasOnboarded { model.camera.start() }
        }
        .task { await Self.warmUpShaders() }
    }

    /// Precompile every Metal pipeline the capture moment needs — the first
    /// shutter press must never stall on shader compilation.
    private static func warmUpShaders() async {
        let layerShaders = [
            ShaderLibrary.grainDissolveRect(
                .boundingRect, .float4(0, 0, 1, 1), .float(1), .float(0), .float(9)),
        ]
        let colorShaders = [
            ShaderLibrary.paperGrain(.float(0), .float(0.5)),
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
