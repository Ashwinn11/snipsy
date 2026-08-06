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
        view.wants = session
        view.syncSession()
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {
        context.coordinator.onTap = onTap
        // The layer is created before permission is granted, so the first
        // real attach usually lands here rather than in makeUIView.
        view.wants = session
        view.syncSession()
    }

    /// Leaving for good releases the session immediately — a torn-down
    /// preview that still holds a connection is exactly the stale claimant
    /// `syncSession` exists to prevent.
    static func dismantleUIView(_ view: PreviewView, coordinator: Coordinator) {
        view.wants = nil
        view.syncSession()
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

        /// The session this view shows *while it is on screen*. The layer's
        /// own `session` is derived from this and the window, never set
        /// directly.
        var wants: AVCaptureSession?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            syncSession()
        }

        /// A preview holds the session only while it is actually visible.
        ///
        /// This is the whole reason the canvas camera used to open slowly
        /// while the camera tab was instant. Two views host a preview layer
        /// — the camera tab's and the canvas cover's — and the tab's is
        /// never torn down: `TabView` keeps a visited tab's view tree alive,
        /// so its layer went on owning a preview connection forever. The
        /// canvas cover then claimed the SAME session as a *second*
        /// layer, and `AVCaptureSession` answers that with a full
        /// begin/commitConfiguration cycle to build another connection —
        /// synchronously, inside `setSession:`, on the main thread. The tab
        /// never paid it because it was always the first claimant.
        ///
        /// Releasing on `window == nil` means there is only ever one
        /// claimant, so every attach is a first attach.
        ///
        /// Never inline, in either direction: `-[AVCaptureVideoPreviewLayer
        /// setSession:]` commits session configuration and blocks on a
        /// nested `CFRunLoop`. Called from inside `makeUIView`/
        /// `updateUIView` — the middle of SwiftUI's view-graph update — that
        /// nested loop drains pending UIKit touches, the hit test asks
        /// SwiftUI for its responder node, and AttributeGraph aborts on the
        /// re-entrant update. Hopping a turn puts the nested loop safely
        /// outside the update; `didMoveToWindow` can land inside one too.
        ///
        /// Ordering is safe by FIFO: the tab's release is scheduled when the
        /// tab goes away, the cover's claim when the cover appears, so the
        /// release always drains first.
        func syncSession() {
            guard previewLayer.session !== target else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                // Re-read: window and `wants` may both have moved on while
                // this hop was in the queue.
                guard previewLayer.session !== target else { return }
                previewLayer.session = target
            }
        }

        /// What the layer should be holding right now.
        private var target: AVCaptureSession? {
            window == nil ? nil : wants
        }
    }
}
