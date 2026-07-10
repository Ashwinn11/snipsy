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
            }
            .frame(width: fullSize.width, height: fullSize.height)
            .ignoresSafeArea()
            .onAppear {
                screenSize = fullSize
                dbgMark("root.fullSize \(fullSize) geo \(geo.size) insets top \(insets.top) bottom \(insets.bottom)")
            }
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        #if DEBUG
        // Audit-tooling probe: records tap locations so external drivers can
        // calibrate their click mapping. No effect on real gestures.
        .simultaneousGesture(
            SpatialTapGesture(coordinateSpace: .global).onEnded { value in
                let docs = FileManager.default.urls(
                    for: .documentDirectory, in: .userDomainMask)[0]
                try? "\(value.location.x),\(value.location.y)"
                    .write(to: docs.appendingPathComponent("tapprobe.txt"),
                           atomically: true, encoding: .utf8)
            }
        )
        #endif
        .onAppear {
            model.camera.start()
            #if DEBUG
            HitchMonitor.shared.start()
            #endif
        }
        .task { await Self.warmUpShaders() }
        .task { await runDebugScript() }
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
    }

    /// Deterministic flow driver for simulator audits (screenshots/videos).
    /// POSTMARK_AUTOCAPTURE=1 launches straight into a capture;
    /// POSTMARK_AUTOKEEP=1 also keeps the stamp; =2 keeps then opens the album.
    private func runDebugScript() async {
        #if DEBUG
        let env = ProcessInfo.processInfo.environment
        if env["POSTMARK_RESET"] == "1" {
            model.store.wipe()
        }
        guard let count = env["POSTMARK_AUTOCAPTURE"].flatMap(Int.init), count > 0 else { return }
        try? await Task.sleep(for: .seconds(3.5))
        for _ in 0..<count {
            let size = screenSize
            guard size != .zero else { return }
            await model.capture(
                viewfinderRect: CameraScreen.viewfinderRect(in: size),
                viewSize: size
            )
            // Wait until the flow returns to the camera before the next shot.
            while !model.inCameraPhase {
                try? await Task.sleep(for: .seconds(0.25))
            }
            try? await Task.sleep(for: .seconds(1.5))
            model.camera.demoFeed.advance()
            try? await Task.sleep(for: .seconds(1.0))
        }
        #endif
    }
}

#Preview {
    RootView()
}
