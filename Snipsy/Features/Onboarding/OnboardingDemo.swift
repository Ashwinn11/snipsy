import SwiftUI

/// Bundled inputs for the onboarding showcases. Every subject runs the real
/// Vision foreground-lift at onboarding time (first launch only) — the same
/// pipeline as the live camera path, just on bundled images.
///
/// Pages claim their subject BY NAME, never by position in the loaded array:
/// load order is an async race, and letting it pick the imagery is how page
/// 2's "the two of you" ended up illustrated with a cup of coffee.
@MainActor
@Observable
final class OnboardingDemo {

    struct Subject {
        /// The bundled file this came from — pages ask for the subject they
        /// mean by name. Picking by position is what let page 2's "THE TWO
        /// OF YOU, KEPT" end up illustrated with a cup of coffee: `hero` was
        /// simply whichever subject finished loading first.
        let key: String
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
        /// The paper tint Vision derived from THIS photo — the same value a
        /// real capture gets. Hand-picked constants kept ending up on the
        /// wrong image every time a page changed subject.
        let tint: RGBValue
    }

    /// Page 2 — "THE TWO OF YOU, KEPT".
    private static let heroKey = "couple2"
    /// Page 3 — the share sheet demo.
    private static let shareKey = "couple1"
    /// Page 4 — the Messages bubble literally reads "coffee first".
    static let messagesKey = "coffee"
    /// Page 5 — the paywall's stamp.
    static let paywallKey = "lily"

    private(set) var hero: Subject?
    private(set) var share: Subject?
    private(set) var drawer: [UIImage] = []

    /// Every loaded subject; pages look theirs up by key.
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
            // Loaded in screen order, so each page's subject is ready
            // about when you reach it.
            let specs: [(file: String, title: String)] = [
                ("couple2", "Us"),      // page 2 hero
                ("couple1", "Together"),// page 3 share sheet
                ("coffee",  "Coffee"),  // page 4 Messages
                ("lily",    "Lily"),    // page 5 paywall
                ("puppy",   "Buddy"),   // drawer + canvas
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
                    self.subjects = soFar
                    self.assignRoles(from: soFar)
                }
            }
            let finalLoaded = loaded
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.subjects = finalLoaded
                self.assignRoles(from: finalLoaded)
                self.drawer = finalLoaded.map(\.stickerRender)
            }
        }
    }

    /// Bind the named roles against whatever has loaded so far, falling
    /// back to anything available — a subject whose Vision lift failed must
    /// leave a page illustrated, not blank.
    private func assignRoles(from list: [Subject]) {
        hero = list.first { $0.key == Self.heroKey } ?? list.first
        share = list.first { $0.key == Self.shareKey }
            ?? list.first { $0.key != Self.heroKey }
            ?? list.first
    }

    /// A whole loaded subject, by bundled file name.
    func subject(_ key: String) -> Subject? {
        subjects.first { $0.key == key }
    }

    /// A loaded subject's die cut, by bundled file name.
    func sticker(_ key: String) -> UIImage? {
        subjects.first { $0.key == key }?.sticker
    }

    /// The die cut as Messages would render it — label and all.
    func stickerRender(_ key: String) -> UIImage? {
        subjects.first { $0.key == key }?.stickerRender
    }

    /// The plain 4:5 crop, no subject lift. What a STAMP shows: the app's
    /// own rule is that `.classic` fills the frame with the photo, and only
    /// a sticker wears the die cut.
    func photo(_ key: String) -> UIImage? {
        subjects.first { $0.key == key }?.photo
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

        // The real pipeline — the same call the live camera path makes. It
        // yields both the subject lift and the paper tint, so an onboarding
        // stamp is coloured by its own photo exactly like a real capture.
        //
        // (A `<file>.cutout.png` branch used to sit here, described as a
        // pre-baked fast path for coffee. No such file has ever shipped, so
        // it never ran — and its comment made coffee look like the
        // deliberate hero when it was only the first array entry.)
        let analysis = await VisionService.analyze(UIImage(cgImage: photoCG))
        guard let cutoutCG = analysis.cutout?.cgImage else { return nil }

        guard let result = StampRenderer.sticker(from: cutoutCG) else { return nil }
        let cutout = UIImage(cgImage: cutoutCG)

        return await MainActor.run {
            let renderer = ImageRenderer(content: StickerArtifact(
                image: result.image, title: title, anchor: result.labelAnchor))
            renderer.scale = 1
            renderer.isOpaque = false
            guard let render = renderer.uiImage else { return nil }
            return Subject(
                key: file,
                photo: photo, cutout: cutout, sticker: result.image,
                box: result.box, labelAnchor: result.labelAnchor,
                stickerRender: render, title: title, tint: analysis.tint)
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
