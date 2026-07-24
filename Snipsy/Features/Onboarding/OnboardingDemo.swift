import SwiftUI

/// Bundled, inputs for the onboarding showcases. The coffee hero and its
/// pre-baked cutout star in the page-1 demo and the Messages bubble.
/// Couple2, lily, and puppy run Vision live at onboarding time (first launch
/// only) since they have no pre-baked cutout — the fallback path is identical
/// to the normal app pipeline.
@MainActor
@Observable
final class OnboardingDemo {

    struct Subject {
        /// 4:5 crop; pixel-aligned with its matte.
        let photo: UIImage
        /// Full-crop RGBA subject matte.
        let cutout: UIImage
        /// Die-cut sticker with the white border.
        let sticker: UIImage
        /// Sticker coverage in the crop, normalized.
        let box: CGRect
        let labelAnchor: CGFloat
        /// StickerArtifact raster — exactly what Messages would show.
        let stickerRender: UIImage
        let title: String
    }

    /// Hand-picked bases — deterministic, no Vision at onboarding runtime.
    static let heroTint = RGBValue.stampTint(from: UIColor(
        red: 0.62, green: 0.48, blue: 0.36, alpha: 1))
    static let shareTint = RGBValue.stampTint(from: UIColor(
        red: 0.55, green: 0.38, blue: 0.34, alpha: 1))

    private(set) var hero: Subject?
    private(set) var share: Subject?
    private(set) var drawer: [UIImage] = []

    /// All four loaded subjects — used by the canvas page for sticker access.
    private(set) var subjects: [Subject] = []

    /// couple1 raw photo — shown as a tilted photo card on the canvas page.
    /// No Vision needed: it's used as a flat photo, not a die-cut.
    private(set) var canvasPhoto: UIImage?

    func load() {
        guard hero == nil else { return }

        // Load couple1 raw (no cutout pipeline — flat photo for the canvas page).
        if let url = Bundle.main.url(forResource: "couple1", withExtension: "jpg"),
           let img = UIImage(contentsOfFile: url.path) {
            canvasPhoto = img
        }

        Task.detached(priority: .userInitiated) { [weak self] in
            // coffee has a pre-baked cutout; the rest run Vision live on first launch.
            let specs: [(file: String, title: String)] = [
                ("coffee",  "Coffee"),
                ("couple2", "Us"),
                ("lily",    "Lily"),
                ("puppy",   "Buddy"),
            ]
            var loaded: [Subject] = []
            for spec in specs {
                guard let s = await Self.loadSubject(spec.file, title: spec.title)
                else { continue }
                loaded.append(s)
                let soFar = loaded
                // Publish as each one lands. The memory page leads the
                // onboarding and draws from `subjects`, so waiting for all
                // four (three of which run Vision live on first launch)
                // would leave the very first screen half-built.
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    if self.hero == nil { self.hero = s }
                    self.subjects = soFar
                }
            }
            let finalLoaded = loaded
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.subjects = finalLoaded
                self.share = finalLoaded.count > 1 ? finalLoaded[1] : finalLoaded.first
                self.drawer = finalLoaded.map(\.stickerRender)
            }
        }
    }

    private nonisolated static func loadSubject(
        _ file: String, title: String
    ) async -> Subject? {
        guard
            let photoURL = Bundle.main.url(forResource: file, withExtension: "jpg"),
            let rawPhoto = UIImage(contentsOfFile: photoURL.path)?.cgImage
        else { return nil }

        guard let photoCG = centerCrop45(rawPhoto) else { return nil }
        let photo = UIImage(cgImage: photoCG).predecoded()

        // Try the pre-baked cutout first (coffee); fall back to live Vision
        // for any subject that doesn't have a bundled .cutout.png.
        let cutoutCG: CGImage
        if let cutoutURL = Bundle.main.url(
                forResource: "\(file).cutout", withExtension: "png"),
           let rawCutout = UIImage(contentsOfFile: cutoutURL.path)?.cgImage,
           let cropped = centerCrop45(rawCutout) {
            cutoutCG = cropped
        } else {
            // Run the real Vision foreground-lift pipeline — same as the
            // live camera path, just on a bundled image.
            let analysis = await VisionService.analyze(UIImage(cgImage: photoCG))
            guard let liveCutout = analysis.cutout?.cgImage else { return nil }
            cutoutCG = liveCutout
        }

        guard let result = StampRenderer.sticker(from: cutoutCG) else { return nil }
        let cutout = UIImage(cgImage: cutoutCG)

        return await MainActor.run {
            let renderer = ImageRenderer(content: StickerArtifact(
                image: result.image, title: title, anchor: result.labelAnchor))
            renderer.scale = 1
            renderer.isOpaque = false
            guard let render = renderer.uiImage else { return nil }
            return Subject(
                photo: photo, cutout: cutout, sticker: result.image,
                box: result.box, labelAnchor: result.labelAnchor,
                stickerRender: render, title: title)
        }
    }

    private nonisolated static func centerCrop45(_ cg: CGImage) -> CGImage? {
        let w = CGFloat(cg.width), h = CGFloat(cg.height)
        let targetW: CGFloat, targetH: CGFloat
        if w / h > 4.0 / 5.0 {
            targetH = h; targetW = h * 4 / 5
        } else {
            targetW = w; targetH = w * 5 / 4
        }
        return cg.cropping(to: CGRect(
            x: ((w - targetW) / 2).rounded(.down),
            y: ((h - targetH) / 2).rounded(.down),
            width: targetW.rounded(.down),
            height: targetH.rounded(.down)))
    }
}
