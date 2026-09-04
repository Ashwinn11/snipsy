import SwiftUI

struct RootView: View {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase
    private let language = LanguageController.shared

    var body: some View {
        content
            // SwiftUI resolves every `Text("…")` against this. The bundle
            // swap in LanguageController covers `L()`; the
            // `id` forces a rebuild so a change lands instantly instead of
            // on next launch.
            .environment(\.locale, language.locale)
            .id(language.code)
    }

    private var content: some View {
        ZStack {
            TabView(selection: $model.selectedTab) {
                GeometryHost { size, insets in
                    // Onboarding sits on top of this TabView, not instead of
                    // it, so the camera tab would otherwise mount and call
                    // `camera.start()` while the user is still on slide one:
                    // a live session running invisibly under the overlay,
                    // and — once onboarding opens its own capture surface —
                    // a second preview layer on the same AVCaptureSession,
                    // both instances sharing one `phase` and stopping each
                    // other. One capture surface at a time.
                    if model.hasOnboarded {
                        StampCaptureFlow(model: model, screenSize: size,
                                         safeArea: insets)
                    } else {
                        Color.black
                    }
                }
                .tabItem { Label("Camera", systemImage: "camera") }
                .tag(AppModel.RootTab.camera)

                GeometryHost { _, insets in
                    AlbumScreen(model: model, safeArea: insets)
                }
                .tabItem { Label("Collection", systemImage: "rectangle.stack") }
                .tag(AppModel.RootTab.collection)

                GeometryHost { size, insets in
                    CanvasTabScreen(model: model, screenSize: size, safeArea: insets)
                }
                .tabItem { Label("Canvas", systemImage: "paintbrush.pointed") }
                .tag(AppModel.RootTab.canvas)

                GeometryHost { _, insets in
                    SettingsSheet(model: model, safeArea: insets) {
                        Task { @MainActor in
                            try? await Task.sleep(for: .seconds(0.35))
                            withAnimation(.easeInOut(duration: 0.5)) {
                                model.deleteAllData()
                            }
                        }
                    }
                }
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(AppModel.RootTab.settings)
            }
            .tint(Theme.postalRed)

            if !model.hasOnboarded {
                GeometryHost { size, insets in
                    OnboardingScreen(model: model, screenSize: size, safeArea: insets)
                }
                .transition(.opacity)
            }
        }
        .statusBarHidden()
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
                .float2(1, 1), .float4(0, 0, 1, 1),
                .float(PerforatedRect.defaultHoleRadiusFraction),
                .float(PerforatedRect.defaultSpacingFactor),
                .float(0), .float(9)),
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

/// The stamp/sticker ceremony as a self-contained surface: the live camera,
/// the grain-dissolve develop, and the reveal — the camera tab's content.
/// The camera runs only while this tab is selected.
struct StampCaptureFlow: View {
    let model: AppModel
    let screenSize: CGSize
    let safeArea: EdgeInsets

    var body: some View {
        ZStack {
            CameraScreen(model: model, screenSize: screenSize,
                         safeArea: safeArea)

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

            // Import curtain — above every phase, so the frozen frame's
            // heavy first render happens behind it, never as a visible snap.
            //
            // A shutter press never raises this. `CameraScreen` freezes the
            // preview on the tap instead, which leaves the shot itself on
            // the glass — a curtain there was covering the picture the user
            // had just asked for. An import genuinely needs one: it
            // dismisses a full-screen cover back onto a running camera, and
            // the live feed would flash through before the develop lands.
            Color.black
                .opacity(model.blackout ? 1 : 0)
                .animation(.easeOut(duration: model.blackout ? 0.12 : 0.22),
                           value: model.blackout)
                .allowsHitTesting(false)
        }
        .frame(width: screenSize.width, height: screenSize.height)
        .ignoresSafeArea()
        .toolbar(model.inCameraPhase ? .visible : .hidden, for: .tabBar)
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

/// Measures the real device safe area for content that expands edge-to-edge,
/// re-measured fresh per tab so it correctly reflects that tab's own
/// tab-bar visibility (`.toolbar(_:for:.tabBar)` can hide/show independently
/// per tab — this is what lets bottom-anchored chrome never collide with it).
private struct GeometryHost<Content: View>: View {
    @ViewBuilder let content: (CGSize, EdgeInsets) -> Content

    var body: some View {
        GeometryReader { geo in
            let insets = geo.safeAreaInsets
            let fullSize = CGSize(
                width: geo.size.width + insets.leading + insets.trailing,
                height: geo.size.height + insets.top + insets.bottom
            )
            content(fullSize, insets)
                .frame(width: fullSize.width, height: fullSize.height)
                .ignoresSafeArea()
        }
    }
}


