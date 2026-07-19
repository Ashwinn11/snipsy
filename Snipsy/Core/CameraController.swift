@preconcurrency import AVFoundation
import UIKit
import Observation

enum CameraError: Error { case noImage }

/// AVFoundation camera front-end: session lifecycle, focus, and a
/// continuation-bridged still capture returning an orientation-normalized
/// image.
@MainActor
@Observable
final class CameraController: NSObject, AVCapturePhotoCaptureDelegate {

    enum Authorization { case undetermined, authorized, denied }

    var authorization: Authorization = .undetermined
    var isRunning = false
    var flashOn = false
    var frontCamera = false

    nonisolated let session = AVCaptureSession()
    @ObservationIgnored private let sessionQueue = DispatchQueue(label: "snipsy.camera.session")
    @ObservationIgnored nonisolated private let photoOutput = AVCapturePhotoOutput()
    @ObservationIgnored private var photoContinuation: CheckedContinuation<UIImage, Error>?

    @ObservationIgnored private var currentDevice: AVCaptureDevice?

    // MARK: Lifecycle

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            authorization = .authorized
            configureAndRun()
        case .notDetermined:
            Task {
                let granted = await AVCaptureDevice.requestAccess(for: .video)
                self.authorization = granted ? .authorized : .denied
                if granted { self.configureAndRun() }
            }
        default:
            authorization = .denied
        }
    }

    private func configureAndRun() {
        sessionQueue.async { [self] in
            if session.inputs.isEmpty {
                session.beginConfiguration()
                session.sessionPreset = .photo
                attachInput(position: .back)
                if session.canAddOutput(photoOutput) { session.addOutput(photoOutput) }
                // The photo becomes a ≤1600 px stamp; Deep Fusion-class
                // processing would burn 300–600 ms buying detail the
                // pipeline immediately throws away.
                photoOutput.maxPhotoQualityPrioritization = .speed
                session.commitConfiguration()
            }
            if !session.isRunning { session.startRunning() }
            Task { @MainActor in self.isRunning = true }
        }
    }

    /// Must be called on sessionQueue, inside begin/commitConfiguration.
    nonisolated private func attachInput(position: AVCaptureDevice.Position) {
        for input in session.inputs { session.removeInput(input) }
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input)
        else { return }
        session.addInput(input)
        Task { @MainActor in self.currentDevice = device }
    }

    func flip() {
        frontCamera.toggle()
        let position: AVCaptureDevice.Position = frontCamera ? .front : .back
        sessionQueue.async { [self] in
            session.beginConfiguration()
            attachInput(position: position)
            session.commitConfiguration()
        }
    }

    func focus(atDevicePoint point: CGPoint) {
        guard let device = currentDevice else { return }
        sessionQueue.async {
            guard (try? device.lockForConfiguration()) != nil else { return }
            if device.isFocusPointOfInterestSupported {
                device.focusPointOfInterest = point
                device.focusMode = .autoFocus
            }
            if device.isExposurePointOfInterestSupported {
                device.exposurePointOfInterest = point
                device.exposureMode = .autoExpose
            }
            device.unlockForConfiguration()
        }
    }

    // MARK: Capture

    /// One still, orientation-normalized `.up`.
    func capture() async throws -> UIImage {
        try await withCheckedThrowingContinuation { cont in
            photoContinuation = cont
            let settings = AVCapturePhotoSettings()
            settings.photoQualityPrioritization = .speed
            if photoOutput.supportedFlashModes.contains(.on) {
                settings.flashMode = flashOn ? .on : .off
            }
            sessionQueue.async { [photoOutput] in
                photoOutput.capturePhoto(with: settings, delegate: self)
            }
        }
    }

    nonisolated func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: (any Error)?
    ) {
        // Decode here, on the delegate's private queue, at a bounded size:
        // CGImageSource applies EXIF orientation during the subsampled
        // decode, so the full-resolution UIImage(data:) + orientation
        // redraw (previously on the main actor) never happens. 3072 px
        // out-resolves the screen-exact crop on any current display.
        let image = photo.fileDataRepresentation().flatMap {
            ImageOptimizer.downsampled(data: $0, maxPixel: 3072)
        }
        Task { @MainActor in
            defer { photoContinuation = nil }
            if let error {
                photoContinuation?.resume(throwing: error)
            } else if let image {
                photoContinuation?.resume(returning: image)
            } else {
                photoContinuation?.resume(throwing: CameraError.noImage)
            }
        }
    }
}
