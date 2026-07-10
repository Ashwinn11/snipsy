import SwiftUI
import UIKit
import Observation

/// The one flow state machine. Camera is always mounted underneath;
/// developing and reveal overlay it with pixel-continuous handoffs.
@MainActor
@Observable
final class AppModel {

    enum Phase {
        case camera
        case developing(Capture)
        case reveal(PendingStamp)

        var kind: Int {
            switch self {
            case .camera: 0
            case .developing: 1
            case .reveal: 2
            }
        }
    }

    var phase: Phase = .camera
    var showAlbum = false

    /// Collection pill frame in full-screen coordinates (fly-to-album target).
    var pillFrame: CGRect = .zero
    /// Incremented when a stamp lands in the pill — drives its bounce.
    var pillBump = 0

    var isCapturing = false
    /// Shutter blackout curtain, rendered above every phase in RootView. Held
    /// dark until DevelopOverlay's first frame has committed, so the heavy
    /// frozen-frame setup happens behind it and never as an on-screen snap.
    var blackout = false

    let camera = CameraController()
    let store = StampStore()
    let haptics = Haptics()

    var inCameraPhase: Bool {
        if case .camera = phase { return true }
        return false
    }

    // MARK: Capture

    func capture(viewfinderRect: CGRect, viewSize: CGSize) async {
        guard inCameraPhase, !isCapturing else { return }
        isCapturing = true
        defer { isCapturing = false }
        haptics.shutter()
        blackout = true
        let shutterMoment = Date()

        do {
            let shot = try await camera.capture()
            let image = shot.image
            let drift = shot.drift
            let fallback = shot.fallbackCutout

            // Bake the on-screen presentation (aspect-fill + demo drift) into a
            // screen-exact image so every later step shares one geometry.
            // Cropping and bitmap decode are heavy — do them off the main
            // thread, behind the blackout, so no frame is ever built late.
            let baked = await Task.detached(priority: .userInitiated) {
                () -> (screen: UIImage, crop: UIImage, cutout: UIImage?)? in
                let screenRect = CGRect(origin: .zero, size: viewSize)
                let screenPixels = FrameGeometry.imageCrop(
                    imageSize: image.size, viewSize: viewSize,
                    rectInView: screenRect, drift: drift
                )
                guard let screenImage = FrameGeometry.crop(image, to: screenPixels)
                else { return nil }

                let cropPixels = FrameGeometry.imageCrop(
                    imageSize: image.size, viewSize: viewSize,
                    rectInView: viewfinderRect, drift: drift
                )
                guard cropPixels.width > 16, cropPixels.height > 16,
                      let cropImage = FrameGeometry.crop(image, to: cropPixels)
                else { return nil }

                let fallbackCutout = fallback.flatMap {
                    FrameGeometry.crop($0, to: cropPixels)
                }
                return (screenImage.preparingForDisplay() ?? screenImage,
                        cropImage.preparingForDisplay() ?? cropImage,
                        fallbackCutout.map { $0.preparingForDisplay() ?? $0 })
            }.value

            guard let baked else {
                blackout = false
                return
            }

            // Hold the shutter blink long enough to read as a beat.
            let elapsed = Date().timeIntervalSince(shutterMoment)
            if elapsed < 0.26 {
                try? await Task.sleep(for: .seconds(0.26 - elapsed))
            }

            phase = .developing(Capture(
                screenImage: baked.screen,
                cropImage: baked.crop,
                viewfinderRect: viewfinderRect,
                fallbackCutout: baked.cutout,
                fallbackLabel: shot.fallbackLabel
            ))
            // DevelopOverlay lifts the blackout once its first frame is up.
        } catch {
            // Capture failed — remain in camera, no drama.
            blackout = false
        }
    }

    func developFinished(_ pending: PendingStamp) {
        phase = .reveal(pending)
    }

    func retake() {
        phase = .camera
    }

    /// Called by the reveal screen after the stamp has flown into the pill.
    func keep(_ pending: PendingStamp, title: String, variant: StampVariant) {
        store.add(pending, title: title, variant: variant)
        phase = .camera
        pillBump += 1
        haptics.success()
    }
}
