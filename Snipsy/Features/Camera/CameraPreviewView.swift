import SwiftUI
import AVFoundation

/// AVCaptureVideoPreviewLayer host with tap-to-focus.
struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    /// (point in view coords, point in capture-device coords)
    var onTap: (CGPoint, CGPoint) -> Void

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.videoGravity = .resizeAspectFill
        let tap = UITapGestureRecognizer(
            target: context.coordinator, action: #selector(Coordinator.tapped(_:))
        )
        view.addGestureRecognizer(tap)
        context.coordinator.view = view
        attachSession(to: view)
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {
        context.coordinator.onTap = onTap
        // The layer is created before permission is granted, so the first
        // real attach usually lands here rather than in makeUIView.
        attachSession(to: view)
    }

    /// Hand the session to the layer on the *next* main-loop turn, never
    /// inline.
    ///
    /// `-[AVCaptureVideoPreviewLayer setSession:]` commits session
    /// configuration, and that blocks on a nested `CFRunLoop`. Called from
    /// inside `makeUIView`/`updateUIView` — i.e. in the middle of SwiftUI's
    /// view-graph update — that nested loop drains pending UIKit touches,
    /// the hit test asks SwiftUI for its responder node, and AttributeGraph
    /// aborts on the re-entrant update. Hopping a turn puts the nested loop
    /// safely outside the update.
    ///
    /// This became reachable when the camera stopped asking for permission
    /// on entry: the preview is now built in response to authorization
    /// flipping to `.authorized`, which is exactly a graph update with a
    /// live touch still in flight.
    private func attachSession(to view: PreviewView) {
        guard view.previewLayer.session !== session else { return }
        DispatchQueue.main.async {
            guard view.previewLayer.session !== session else { return }
            view.previewLayer.session = session
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(onTap: onTap) }

    final class Coordinator: NSObject {
        var onTap: (CGPoint, CGPoint) -> Void
        weak var view: PreviewView?

        init(onTap: @escaping (CGPoint, CGPoint) -> Void) { self.onTap = onTap }

        @objc func tapped(_ gr: UITapGestureRecognizer) {
            guard let view else { return }
            let p = gr.location(in: view)
            let device = view.previewLayer.captureDevicePointConverted(fromLayerPoint: p)
            onTap(p, device)
        }
    }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
