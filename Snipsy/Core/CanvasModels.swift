import SwiftUI

/// One normalized placement on the canvas: x/y are the layer's center as a
/// fraction of the canvas, scale is the layer's width as a fraction of the
/// canvas width, rotation in radians. Resolution-independent, so the editor
/// and the flatten render agree at any size.
struct LayerTransform: Codable, Equatable {
    var x: CGFloat = 0.5
    var y: CGFloat = 0.5
    var scale: CGFloat = 0.5
    var rotation: CGFloat = 0
}

/// A text layer's persisted voice. System font designs only — the app
/// bundles no font files.
struct TextStyleValue: Codable, Equatable {
    /// What a fresh text layer holds so it is visible on the stage before
    /// anything is typed. Treated as a placeholder, not as content: the
    /// editor clears it on entry and puts it back if you leave without
    /// typing. Nothing should ever compare against the bare literal.
    static let placeholder = "Your words"

    enum DesignValue: String, Codable, CaseIterable {
        case rounded, serif, monospaced, condensed, typewriter, engraved,
             marker, handwritten, script, ransom
    }
    var design: DesignValue = .rounded
    /// UIFont.Weight bucket 1...9 (ultraLight...black). Heavy (8) is the
    /// app's chrome voice.
    var weight: Int = 8
    var italic: Bool = false
    var color: RGBValue = RGBValue(r: 0.133, g: 0.122, b: 0.102)
    /// Render through DieCutText — ink glyphs wearing the white sticker
    /// contour.
    var dieCut: Bool = false

    var font: Font { Self.font(design: design, weight: weight,
                               italic: italic, size: 17) }

    /// The resolved Font at a given size.
    func font(size: CGFloat) -> Font {
        Self.font(design: design, weight: weight, italic: italic, size: size)
    }

    private static func font(design: DesignValue, weight: Int,
                             italic: Bool, size: CGFloat) -> Font {
        let w: Font.Weight = switch weight {
        case ...1: .ultraLight
        case 2: .thin
        case 3: .light
        case 4: .regular
        case 5: .medium
        case 6: .semibold
        case 7: .bold
        case 8: .heavy
        default: .black
        }
        var f: Font = switch design {
        case .rounded: .system(size: size, weight: w, design: .rounded)
        case .serif: .system(size: size, weight: w, design: .serif)
        case .monospaced: .system(size: size, weight: w, design: .monospaced)
        case .condensed: .system(size: size, weight: w).width(.condensed)
        case .typewriter: Theme.typewriter(size)
        case .engraved: Theme.engraved(size)
        case .marker: Theme.marker(size)
        case .handwritten: Theme.handwritten(size)
        case .script: Theme.script(size)
        // Ransom is a per-glyph treatment (RansomText), not a Font. Nothing
        // on the stage uses this any more — the layer render and the inline
        // editor both go through RansomText — but the toolbar's "Aa" chip
        // still needs *some* Font to draw itself with.
        case .ransom: .system(size: size, weight: w, design: .rounded)
        }
        if italic { f = f.italic() }
        return f
    }
}

/// How a photo layer is presented. The chooser after a multi-pick applies
/// one of these to the whole batch; a placed layer can switch later.
enum ImageTreatment: String, Codable, Equatable {
    /// The photo as-is, softly rounded.
    case plain
    /// Vision lifts the subject and drops the background (uses cutoutFile).
    case dieCut
    /// The photo in a white instant-photo frame.
    case polaroid
    /// The rectangular photo wearing a plain white sticker border — no
    /// subject recognition.
    case outline
}

/// What one canvas layer holds. Pixels live in files under the store's
/// images/ directory; the model carries only references.
enum LayerContent: Equatable {
    /// cutoutFile appears once a die-cut lift has run on this layer; the
    /// treatment decides how the layer renders (toggling never re-runs
    /// Vision — the lift is cached in cutoutFile).
    case image(file: String, cutoutFile: String?, treatment: ImageTreatment)
    case text(string: String, style: TextStyleValue)
    /// A saved die-cut copied into the creation — survives source deletion.
    case sticker(file: String)
    /// Namespaced id resolved by DoodleCatalog: "washi.rose", "emoji.❤️".
    case doodle(id: String)
}

extension LayerContent: Codable {
    private enum CaseKey: String, CodingKey { case image, text, sticker, doodle }
    private enum ImageKey: String, CodingKey {
        case file, cutoutFile, treatment, showCutout
    }
    private enum TextKey: String, CodingKey { case string, style }
    private enum StickerKey: String, CodingKey { case file }
    private enum DoodleKey: String, CodingKey { case id }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CaseKey.self)
        if let img = try? c.nestedContainer(keyedBy: ImageKey.self, forKey: .image) {
            let file = try img.decode(String.self, forKey: .file)
            let cutoutFile = try img.decodeIfPresent(String.self, forKey: .cutoutFile)
            let treatment: ImageTreatment
            if let t = try img.decodeIfPresent(ImageTreatment.self, forKey: .treatment) {
                treatment = t
            } else {
                // Migrate legacy `showCutout` flag: true → die-cut, else plain.
                let showCutout = (try? img.decode(Bool.self, forKey: .showCutout)) ?? false
                treatment = showCutout ? .dieCut : .plain
            }
            self = .image(file: file, cutoutFile: cutoutFile, treatment: treatment)
        } else if let txt = try? c.nestedContainer(keyedBy: TextKey.self, forKey: .text) {
            self = .text(string: try txt.decode(String.self, forKey: .string),
                         style: try txt.decode(TextStyleValue.self, forKey: .style))
        } else if let stk = try? c.nestedContainer(keyedBy: StickerKey.self, forKey: .sticker) {
            self = .sticker(file: try stk.decode(String.self, forKey: .file))
        } else if let ddl = try? c.nestedContainer(keyedBy: DoodleKey.self, forKey: .doodle) {
            self = .doodle(id: try ddl.decode(String.self, forKey: .id))
        } else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "Unknown LayerContent case"))
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CaseKey.self)
        switch self {
        case .image(let file, let cutoutFile, let treatment):
            var img = c.nestedContainer(keyedBy: ImageKey.self, forKey: .image)
            try img.encode(file, forKey: .file)
            try img.encodeIfPresent(cutoutFile, forKey: .cutoutFile)
            try img.encode(treatment, forKey: .treatment)
        case .text(let string, let style):
            var txt = c.nestedContainer(keyedBy: TextKey.self, forKey: .text)
            try txt.encode(string, forKey: .string)
            try txt.encode(style, forKey: .style)
        case .sticker(let file):
            var stk = c.nestedContainer(keyedBy: StickerKey.self, forKey: .sticker)
            try stk.encode(file, forKey: .file)
        case .doodle(let id):
            var ddl = c.nestedContainer(keyedBy: DoodleKey.self, forKey: .doodle)
            try ddl.encode(id, forKey: .id)
        }
    }
}

/// One draggable element of a composition. Z-order is the layer's position
/// in the document's array.
struct CanvasLayer: Identifiable, Codable, Equatable {
    let id: UUID
    var content: LayerContent
    var transform: LayerTransform = LayerTransform()
    /// Universal white sticker contour — any layer can be cut. (Photos cut
    /// through Vision's subject lift instead; this flag stays false there.)
    var dieCut: Bool = false

    init(id: UUID = UUID(), content: LayerContent,
         transform: LayerTransform = LayerTransform(), dieCut: Bool = false) {
        self.id = id
        self.content = content
        self.transform = transform
        self.dieCut = dieCut
    }

    private enum CodingKeys: String, CodingKey {
        case id, content, transform, dieCut
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        content = try c.decode(LayerContent.self, forKey: .content)
        transform = try c.decodeIfPresent(LayerTransform.self, forKey: .transform)
            ?? LayerTransform()
        if let flag = try c.decodeIfPresent(Bool.self, forKey: .dieCut) {
            dieCut = flag
        } else if case .text(_, let style) = content {
            // Migrate: text layers once carried the cut on their style.
            dieCut = style.dieCut
        } else {
            dieCut = false
        }
    }
}

/// A plain page stock — no collectible chrome, just a surface to decorate
/// freely with stickers and tape. Named and drawn for Snipsy's own
/// correspondence/keepsake voice, not a generic craft-paper aisle.
enum CanvasTexture: String, Codable, CaseIterable, Identifiable {
    /// Warm ivory, soft grain — the blank writing page.
    case parchment
    /// Soft diffused blush/lavender watercolor wash.
    case watercolorBloom
    /// Sun-washed dusty blue-sand gradient.
    case coastalWash
    /// Parcel brown, a whisper of crosshatched string.
    case twine
    /// Cream scattered with faint cancellation-mark rings.
    case postmark
    /// Charcoal-blue — a page for after dark.
    case slate
    /// Dusty rose gingham check.
    case sweetheartCheck
    /// Sage wash, scattered pressed petals and leaves.
    case fadedBloom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .parchment: "Parchment"
        case .watercolorBloom: "Watercolor Bloom"
        case .coastalWash: "Coastal Wash"
        case .twine: "Twine"
        case .postmark: "Postmark"
        case .slate: "Slate"
        case .sweetheartCheck: "Sweetheart Check"
        case .fadedBloom: "Faded Bloom"
        }
    }
}

/// A layered composition — the canvas editor's document, embedded in the
/// stamp index (layer payloads are bytes; pixels live in files).
struct CanvasDocument: Codable, Equatable {
    enum Background: Codable, Equatable {
        case paper(StampVariant)
        case polaroid
        case card
        /// A plain page stock — no collectible chrome, no printed date.
        case texture(CanvasTexture)
    }
    var background: Background = .card
    /// Canvas height / width. Stamp paper 1.3125, polaroid ≈1.22, card 1.30.
    var aspect: CGFloat = 1.30
    var layers: [CanvasLayer] = []
    /// The memory's date — printed as the stamp template's header
    /// ("JUL 14 / TUESDAY").
    var date: Date = Date()

    init(background: Background = .card, aspect: CGFloat = 1.30,
         layers: [CanvasLayer] = [], date: Date = Date()) {
        self.background = background
        self.aspect = aspect
        self.layers = layers
        self.date = date
    }

    /// A fresh stamp-template document — the memory maker's default page.
    static func newMemory(variant: StampVariant = .tinted) -> CanvasDocument {
        CanvasDocument(background: .paper(variant),
                       aspect: aspect(for: .paper(variant)))
    }

    /// The stage aspect each background stock wants.
    static func aspect(for background: Background) -> CGFloat {
        switch background {
        case .paper: 1.3125
        case .polaroid: 1.22
        case .card, .texture: 1.30
        }
    }

    private enum CodingKeys: String, CodingKey {
        case background, aspect, layers, date
    }

    /// Backward-compatible decode: canvases saved before the template
    /// header existed have no `date` — default it instead of failing (and
    /// losing the creation).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        background = try c.decode(Background.self, forKey: .background)
        aspect = try c.decode(CGFloat.self, forKey: .aspect)
        layers = try c.decodeIfPresent([CanvasLayer].self, forKey: .layers) ?? []
        date = try c.decodeIfPresent(Date.self, forKey: .date) ?? Date()
    }
}
