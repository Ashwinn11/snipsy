import SwiftUI
import UIKit
import Observation

/// What the canvas editor opens with: a blank page, or a saved creation
/// seeded/re-loaded for decorating.
struct CanvasSession {
    /// nil = new creation; set = re-editing this stamp in place.
    var stampID: UUID? = nil
    var seed = CanvasDocument()
    var seedTitle = ""
    /// A non-canvas artifact to open with: the editor copies its pixels
    /// into a fresh layer file (never shares the source's file — deleting
    /// the composition must not orphan the source stamp).
    var seedArtifact: Stamp? = nil
}

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

    /// The four persistent tabs — Camera, Collection, Canvas, Settings.
    enum RootTab: Hashable { case camera, collection, canvas, settings }
    var selectedTab: RootTab = .camera

    /// The canvas tab's live session — always has a document, fresh or
    /// loaded. Decorating an existing stamp (`StampDetailView.openInCanvas`)
    /// replaces this and switches to the canvas tab; Keep resets it back to
    /// a fresh template in place.
    var canvasSession = CanvasSession(seed: CanvasDocument.newMemory())
    /// True while the canvas tab has unsaved content — hides the tab bar and
    /// swaps its leading button to a back button (`CanvasEditorScreen`).
    var canvasEditing = false

    /// Collection pill frame in full-screen coordinates (fly-to-album target).
    var pillFrame: CGRect = .zero
    /// Incremented when a stamp lands in the pill — drives its bounce.
    var pillBump = 0

    var isCapturing = false
    /// First-run gate; deleting all data returns here.
    var hasOnboarded = UserDefaults.standard.bool(forKey: "snipsy.hasOnboarded")
    /// What onboarding's occasion question answered, if it was answered at
    /// all. Leads the template chooser with a matching paper and dresses the
    /// first canvas — never hides or locks anything. `nil` = skipped, and
    /// every surface stays at its default.
    var occasion: MemoryOccasion? = UserDefaults.standard.string(forKey: "snipsy.occasion")
        .flatMap(MemoryOccasion.init(rawValue:)) {
        didSet {
            UserDefaults.standard.set(occasion?.rawValue, forKey: "snipsy.occasion")
        }
    }
    /// Onboarding's second answer — what has stopped them keeping things.
    /// Empty means skipped, and the how-it-works screen keeps its neutral
    /// line rather than mirroring anything back.
    var blockers: Set<MemoryBlocker> = Set(
        (UserDefaults.standard.array(forKey: "snipsy.blockers") as? [String] ?? [])
            .compactMap(MemoryBlocker.init(rawValue:))
    ) {
        didSet {
            UserDefaults.standard.set(blockers.map(\.rawValue),
                                      forKey: "snipsy.blockers")
        }
    }

    /// The one their answer gets mirrored with — first in declaration order
    /// so the reply is stable across launches rather than set-order random.
    var leadBlocker: MemoryBlocker? {
        MemoryBlocker.allCases.first { blockers.contains($0) }
    }
    /// Shutter blackout curtain, rendered above every phase in RootView. Held
    /// dark until DevelopOverlay's first frame has committed, so the heavy
    /// frozen-frame setup happens behind it and never as an on-screen snap.
    var blackout = false

    let camera = CameraController()
    let store = StampStore()
    let haptics = Haptics()
    let purchases = PurchaseController()
    let reviews = ReviewPrompter()

    /// Vision kicked off the moment the crop is baked — the shutter beat
    /// and the grain dissolve run on top of it, so the reveal is usually
    /// ready the instant the last grain dies. Consumed by DevelopOverlay.
    @ObservationIgnored var pendingAnalysis: Task<VisionService.Analysis, Never>?

    init() {
        // Pick up a prior unlock before onboarding's gate can ask again.
        Task { await purchases.refresh() }
        camera.prewarm()
    }

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
            let image = try await camera.capture()

            // Bake the on-screen presentation (aspect-fill) into a
            // screen-exact image so every later step shares one geometry.
            // Cropping and bitmap decode are heavy — do them off the main
            // thread, behind the blackout, so no frame is ever built late.
            let baked = await Task.detached(priority: .userInitiated) {
                () -> (screen: UIImage, crop: UIImage)? in
                let screenRect = CGRect(origin: .zero, size: viewSize)
                let screenPixels = FrameGeometry.imageCrop(
                    imageSize: image.size, viewSize: viewSize,
                    rectInView: screenRect
                )
                guard let screenImage = FrameGeometry.crop(image, to: screenPixels)
                else { return nil }

                let cropPixels = FrameGeometry.imageCrop(
                    imageSize: image.size, viewSize: viewSize,
                    rectInView: viewfinderRect
                )
                guard cropPixels.width > 16, cropPixels.height > 16,
                      let cropImage = FrameGeometry.crop(image, to: cropPixels)
                else { return nil }

                return (screenImage.preparingForDisplay() ?? screenImage,
                        cropImage.preparingForDisplay() ?? cropImage)
            }.value

            guard let baked else {
                blackout = false
                return
            }

            pendingAnalysis = Task { await VisionService.analyze(baked.crop) }

            // Hold the shutter blink long enough to read as a beat.
            let elapsed = Date().timeIntervalSince(shutterMoment)
            if elapsed < 0.26 {
                try? await Task.sleep(for: .seconds(0.26 - elapsed))
            }

            phase = .developing(Capture(
                screenImage: baked.screen,
                cropImage: baked.crop,
                viewfinderRect: viewfinderRect
            ))
            // DevelopOverlay lifts the blackout once its first frame is up.
        } catch {
            // Capture failed — remain in camera, no drama.
            blackout = false
        }
    }

    /// Bring an existing photo through the exact capture pipeline: bake a
    /// screen-exact frame, crop the viewfinder, then dissolve → die-cut →
    /// papers, identical to a live shot.
    func importPhoto(_ raw: UIImage, viewfinderRect: CGRect, viewSize: CGSize) async {
        guard inCameraPhase, !isCapturing else { return }
        isCapturing = true
        defer { isCapturing = false }
        haptics.tick()
        blackout = true

        let image = ImageOptimizer.normalizedOrientation(raw)
        let baked = await Task.detached(priority: .userInitiated) {
            () -> (screen: UIImage, crop: UIImage)? in
            let screenRect = CGRect(origin: .zero, size: viewSize)
            let screenPixels = FrameGeometry.imageCrop(
                imageSize: image.size, viewSize: viewSize, rectInView: screenRect)
            guard let screenImage = FrameGeometry.crop(image, to: screenPixels)
            else { return nil }
            let cropPixels = FrameGeometry.imageCrop(
                imageSize: image.size, viewSize: viewSize, rectInView: viewfinderRect)
            guard cropPixels.width > 16, cropPixels.height > 16,
                  let cropImage = FrameGeometry.crop(image, to: cropPixels)
            else { return nil }
            return (screenImage.preparingForDisplay() ?? screenImage,
                    cropImage.preparingForDisplay() ?? cropImage)
        }.value

        guard let baked else {
            blackout = false
            return
        }
        pendingAnalysis = Task { await VisionService.analyze(baked.crop) }
        try? await Task.sleep(for: .seconds(0.2))
        phase = .developing(Capture(
            screenImage: baked.screen,
            cropImage: baked.crop,
            viewfinderRect: viewfinderRect
        ))
    }

    func developFinished(_ pending: PendingStamp) {
        phase = .reveal(pending)
    }

    func retake() {
        pendingAnalysis = nil
        phase = .camera
    }

    func completeOnboarding() {
        hasOnboarded = true
        UserDefaults.standard.set(true, forKey: "snipsy.hasOnboarded")
        // The camera now starts on demand (stamp ceremony / canvas camera),
        // not on entry — the home is the memory canvas.
        haptics.success()
    }

    /// Settings → Delete All Data: wipes the collection and returns to
    /// onboarding, exactly like a fresh install.
    func deleteAllData() {
        store.deleteAll()
        selectedTab = .camera
        phase = .camera
        hasOnboarded = false
        UserDefaults.standard.set(false, forKey: "snipsy.hasOnboarded")
        occasion = nil
        blockers = []
        haptics.thunk()
    }

    /// Called by the reveal screen after the stamp has flown into the pill.
    func keep(_ pending: PendingStamp, title: String, variant: StampVariant,
              kind: ArtifactKind = .stamp) {
        store.add(pending, title: title, variant: variant, kind: kind)
        phase = .camera
        pillBump += 1
        haptics.success()
        reviews.stampKept(count: store.stamps.count)
    }

    /// Stickers the share extension couldn't cut in-process (its memory
    /// budget can't hold the subject-lift model on older devices): finish
    /// them here, where the model has room. Consumes the inbox.
    func drainShareInbox() {
        let items = ShareInbox.drain()
        guard !items.isEmpty else { return }
        Task { @MainActor in
            for item in items {
                let analysis = await VisionService.analyze(
                    item.image)
                let pending = PendingStamp(
                    capture: Capture(
                        screenImage: item.image, cropImage: item.image,
                        viewfinderRect: .zero),
                    style: analysis.cutout != nil && analysis.sticker != nil
                        ? .cutout : .classic,
                    cutout: analysis.cutout,
                    sticker: analysis.sticker,
                    stickerBox: analysis.stickerBox,
                    stickerLabelAnchor: analysis.labelAnchor,
                    suggestedTitle: analysis.label,
                    tint: analysis.tint
                )
                // No liftable subject → keep the photo as a classic stamp
                // rather than dropping the share silently.
                let kind: ArtifactKind =
                    pending.style == .cutout ? .sticker : .stamp
                // A name typed in the share sheet wins over the classifier.
                let typed = item.title?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                store.add(pending, title: typed.isEmpty ? (analysis.label ?? "") : typed,
                          variant: .tinted, kind: kind)
                pillBump += 1
            }
            reviews.stampKept(count: store.stamps.count)
        }
    }
}
