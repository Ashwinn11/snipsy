import AVFoundation
import UIKit
import Observation

enum CameraError: Error { case noImage, notReady }

/// Unified camera front-end: real AVFoundation capture on device, a drifting
/// bundled sample feed on the simulator. Downstream geometry is identical.
@MainActor
@Observable
final class CameraController: NSObject, AVCapturePhotoCaptureDelegate {

    enum Authorization { case undetermined, authorized, denied }

    struct Shot {
        let image: UIImage                 // orientation-normalized .up
        let drift: FrameGeometry.Drift     // demo Ken Burns transform at capture
        let fallbackCutout: UIImage?       // demo precomputed subject (full image coords)
        let fallbackLabel: String?
    }

    static let isDemo: Bool = {
        #if targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }()

    var authorization: Authorization = .undetermined
    var isRunning = false
    var flashOn = false
    var frontCamera = false

    let session = AVCaptureSession()
    let demoFeed = DemoFeed()

    @ObservationIgnored private let sessionQueue = DispatchQueue(label: "postmark.camera.session")
    @ObservationIgnored private let photoOutput = AVCapturePhotoOutput()
    @ObservationIgnored private var photoContinuation: CheckedContinuation<UIImage, Error>?
    @ObservationIgnored private var currentDevice: AVCaptureDevice?

    // MARK: Lifecycle

    func start() {
        if Self.isDemo {
            authorization = .authorized
            isRunning = true
            return
        }
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
        guard !Self.isDemo else { demoFeed.advance(); return }
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

    func capture() async throws -> Shot {
        if Self.isDemo {
            guard let (image, drift, sample) = demoFeed.captureCurrent() else {
                throw CameraError.notReady
            }
            return Shot(image: image, drift: drift,
                        fallbackCutout: sample.cutout, fallbackLabel: sample.label)
        }
        let image: UIImage = try await withCheckedThrowingContinuation { cont in
            photoContinuation = cont
            let settings = AVCapturePhotoSettings()
            if photoOutput.supportedFlashModes.contains(.on) {
                settings.flashMode = flashOn ? .on : .off
            }
            sessionQueue.async { [photoOutput] in
                photoOutput.capturePhoto(with: settings, delegate: self)
            }
        }
        return Shot(image: image, drift: .none, fallbackCutout: nil, fallbackLabel: nil)
    }

    nonisolated func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: (any Error)?
    ) {
        let data = photo.fileDataRepresentation()
        Task { @MainActor in
            defer { photoContinuation = nil }
            if let error {
                photoContinuation?.resume(throwing: error)
            } else if let data, let image = UIImage(data: data) {
                photoContinuation?.resume(returning: image.normalizedUp())
            } else {
                photoContinuation?.resume(throwing: CameraError.noImage)
            }
        }
    }
}

// MARK: - Demo feed (simulator)

/// Bundled sample scenes shown as a living feed: slow Ken Burns drift, swipe to
/// change scenes. Drift is a pure function of time so the view and the capture
/// path always agree on geometry.
@MainActor
@Observable
final class DemoFeed {

    struct Sample: Identifiable {
        let id: String
        let label: String
        let image: UIImage
        let cutout: UIImage?
    }

    private(set) var samples: [Sample] = []
    private(set) var index = 0
    let epoch = Date()

    var current: Sample? { samples.isEmpty ? nil : samples[index] }

    init() {
        // Decode bundle images off the main thread, publishing each sample as
        // it becomes ready — the feed appears the moment the first JPEG lands.
        Task.detached(priority: .userInitiated) {
            var any = false
            for sample in Self.sampleLoaders() {
                if let loaded = sample() {
                    any = true
                    await MainActor.run { self.samples.append(loaded) }
                }
            }
            if !any {
                let fallback = Self.placeholder()
                await MainActor.run { self.samples = [fallback] }
            }
        }
    }

    func advance(_ delta: Int = 1) {
        guard !samples.isEmpty else { return }
        index = (index + delta % samples.count + samples.count) % samples.count
    }

    func drift(at date: Date) -> FrameGeometry.Drift {
        let t = date.timeIntervalSince(epoch)
        return FrameGeometry.Drift(
            scale: 1.09 + 0.035 * sin(t * 0.21),
            offset: CGPoint(x: 12 * sin(t * 0.27), y: 9 * sin(t * 0.16 + 1.2))
        )
    }

    func captureCurrent() -> (UIImage, FrameGeometry.Drift, Sample)? {
        guard let sample = current else { return nil }
        return (sample.image, drift(at: Date()), sample)
    }

    private struct ManifestEntry: Decodable {
        let file: String
        let cutout: String?
        let label: String
    }

    nonisolated private static func sampleLoaders() -> [() -> Sample?] {
        guard let url = Bundle.main.url(forResource: "feed", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([ManifestEntry].self, from: data)
        else { return [] }
        return entries.map { entry in
            {
                guard let image = bundleImage(entry.file)?.predecoded() else { return nil }
                return Sample(
                    id: entry.file,
                    label: entry.label,
                    image: image,
                    cutout: entry.cutout.flatMap(bundleImage)
                )
            }
        }
    }

    nonisolated private static func bundleImage(_ name: String) -> UIImage? {
        let parts = name.split(separator: ".", maxSplits: 1).map(String.init)
        guard parts.count == 2,
              let url = Bundle.main.url(forResource: parts[0], withExtension: parts[1]),
              let image = UIImage(contentsOfFile: url.path)
        else { return nil }
        return image
    }

    /// Keeps the app alive even if sample assets are missing from the bundle.
    nonisolated private static func placeholder() -> Sample {
        let size = CGSize(width: 1200, height: 1600)
        let image = UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor(red: 0.16, green: 0.17, blue: 0.19, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            UIColor(red: 0.85, green: 0.55, blue: 0.25, alpha: 1).setFill()
            ctx.cgContext.fillEllipse(in: CGRect(x: 400, y: 560, width: 400, height: 400))
        }
        return Sample(id: "placeholder", label: "Circle", image: image, cutout: nil)
    }
}
