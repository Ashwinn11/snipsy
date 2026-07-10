import SwiftUI

struct RootView: View {
    @State private var model = AppModel()

    @State private var screenSize: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            ZStack {
                CameraScreen(model: model, screenSize: geo.size, safeArea: geo.safeAreaInsets)

                // Crossfaded so camera chrome never pops out under an overlay.
                // The frozen frame matches the live feed pixel-for-pixel, so
                // only the chrome visibly fades.
                Group {
                    switch model.phase {
                    case .camera:
                        EmptyView()
                    case .developing(let capture):
                        DevelopOverlay(capture: capture, model: model, screenSize: geo.size)
                            .transition(.opacity)
                    case .reveal(let pending):
                        RevealScreen(pending: pending, model: model,
                                     screenSize: geo.size, safeArea: geo.safeAreaInsets)
                            .transition(.opacity)
                    }
                }
                .animation(.easeOut(duration: 0.2), value: model.phase.kind)

                if model.showAlbum {
                    AlbumScreen(model: model)
                        .transition(.move(edge: .bottom))
                        .zIndex(10)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .onAppear { screenSize = geo.size }
        }
        .ignoresSafeArea()
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .onAppear { model.camera.start() }
        .task { await runDebugScript() }
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
        guard env["POSTMARK_AUTOCAPTURE"] == "1" else { return }
        try? await Task.sleep(for: .seconds(1.6))
        let size = screenSize
        guard size != .zero else { return }
        await model.capture(
            viewfinderRect: CameraScreen.viewfinderRect(in: size),
            viewSize: size
        )
        #endif
    }
}

#Preview {
    RootView()
}
