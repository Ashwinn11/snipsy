import SwiftUI

/// Bundled, Vision-free inputs for the onboarding showcases. Every matte
/// was baked at build time by tools/prepare_assets.swift with the same
/// Vision pipeline the app uses; sticker geometry comes from the same
/// renderer as the live path. The hero (coffee) stars in the page-1 demo
/// and the Messages bubble; the robot fronts the share mock; all four
/// subjects fill the Messages drawer.
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

    func load() {
        guard hero == nil else { return }
        Task.detached(priority: .userInitiated) { [weak self] in
            let specs: [(file: String, title: String)] = [
                ("coffee", "Coffee"),
                ("robot", "Tin Robot"),
                ("teapot", "Teapot"),
                ("cactus", "Cactus"),
            ]
            var subjects: [Subject] = []
            for spec in specs {
                guard let s = await Self.loadSubject(spec.file, title: spec.title)
                else { continue }
                subjects.append(s)
                if subjects.count == 1 {
                    // Publish the hero early — page 1 starts while the
                    // drawer subjects are still cutting.
                    await MainActor.run { [weak self] in self?.hero = s }
                }
            }
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.share = subjects.count > 1 ? subjects[1] : subjects.first
                self.drawer = subjects.map(\.stickerRender)
            }
        }
    }

    private nonisolated static func loadSubject(
        _ file: String, title: String
    ) async -> Subject? {
        guard
            let photoURL = Bundle.main.url(forResource: file, withExtension: "jpg"),
            let cutoutURL = Bundle.main.url(
                forResource: "\(file).cutout", withExtension: "png"),
            let rawPhoto = UIImage(contentsOfFile: photoURL.path)?.cgImage,
            let rawCutout = UIImage(contentsOfFile: cutoutURL.path)?.cgImage
        else { return nil }

        // Center-crop BOTH to 4:5 identically: the overlay and the raw
        // photo must share one mapping inside StampView (the feed assets
        // aren't pre-cropped).
        guard let photoCG = centerCrop45(rawPhoto),
              let cutoutCG = centerCrop45(rawCutout),
              let result = StampRenderer.sticker(from: cutoutCG)
        else { return nil }
        let photo = UIImage(cgImage: photoCG).predecoded()
        let cutout = UIImage(cgImage: cutoutCG)

        // ImageRenderer is main-actor; raster the drawer artifact once,
        // exactly like StampStore.writeDrawerCopy.
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
