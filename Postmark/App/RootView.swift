import SwiftUI

struct RootView: View {
    @State private var model = AppModel()

    var body: some View {
        GeometryReader { geo in
            ZStack {
                CameraScreen(model: model, screenSize: geo.size, safeArea: geo.safeAreaInsets)

                switch model.phase {
                case .camera:
                    EmptyView()
                case .developing(let capture):
                    DevelopOverlay(capture: capture, model: model, screenSize: geo.size)
                case .reveal(let pending):
                    RevealScreen(pending: pending, model: model,
                                 screenSize: geo.size, safeArea: geo.safeAreaInsets)
                }

                if model.showAlbum {
                    AlbumScreen(model: model)
                        .transition(.move(edge: .bottom))
                        .zIndex(10)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .onAppear { model.camera.start() }
    }
}

#Preview {
    RootView()
}
