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
        let shutterMoment = Date()

        do {
            let shot = try await camera.capture()
            // Hold the shutter blink long enough to read as a beat.
            let elapsed = Date().timeIntervalSince(shutterMoment)
            if elapsed < 0.26 {
                try? await Task.sleep(for: .seconds(0.26 - elapsed))
            }
            let screenRect = CGRect(origin: .zero, size: viewSize)

            // Bake the on-screen presentation (aspect-fill + demo drift) into a
            // screen-exact image so every later step shares one geometry.
            let screenPixels = FrameGeometry.imageCrop(
                imageSize: shot.image.size, viewSize: viewSize,
                rectInView: screenRect, drift: shot.drift
            )
            guard let screenImage = FrameGeometry.crop(shot.image, to: screenPixels)
            else { return }

            let cropPixels = FrameGeometry.imageCrop(
                imageSize: shot.image.size, viewSize: viewSize,
                rectInView: viewfinderRect, drift: shot.drift
            )
            guard cropPixels.width > 16, cropPixels.height > 16,
                  let cropImage = FrameGeometry.crop(shot.image, to: cropPixels)
            else { return }

            let fallbackCutout = shot.fallbackCutout.flatMap {
                FrameGeometry.crop($0, to: cropPixels)
            }

            phase = .developing(Capture(
                screenImage: screenImage,
                cropImage: cropImage,
                viewfinderRect: viewfinderRect,
                fallbackCutout: fallbackCutout,
                fallbackLabel: shot.fallbackLabel
            ))
        } catch {
            // Capture failed — remain in camera, no drama.
        }
    }

    func developFinished(_ pending: PendingStamp) {
        phase = .reveal(pending)
    }

    func retake() {
        phase = .camera
    }

    /// Called by the reveal screen after the stamp has flown into the pill.
    func keep(_ pending: PendingStamp, title: String) {
        store.add(pending, title: title)
        phase = .camera
        pillBump += 1
        haptics.success()
    }
}
