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
    enum DesignValue: String, Codable, CaseIterable {
        case rounded, serif, monospaced, condensed, handwritten, script
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
        case .handwritten: Theme.handwritten(size)
        case .script: Theme.script(size)
        }
        if italic { f = f.italic() }
        return f
    }
}

/// What one canvas layer holds. Pixels live in files under the store's
/// images/ directory; the model carries only references.
enum LayerContent: Codable, Equatable {
    /// cutoutFile appears once Vision has run on this layer; showCutout
    /// picks which renders — toggling back never re-runs Vision.
    case image(file: String, cutoutFile: String?, showCutout: Bool)
    case text(string: String, style: TextStyleValue)
    /// A saved die-cut copied into the creation — survives source deletion.
    case sticker(file: String)
    /// Namespaced id resolved by DoodleCatalog: "washi.rose", "emoji.❤️".
    case doodle(id: String)
}

/// One draggable element of a composition. Z-order is the layer's position
/// in the document's array.
struct CanvasLayer: Identifiable, Codable, Equatable {
    let id: UUID
    var content: LayerContent
    var transform: LayerTransform = LayerTransform()

    init(id: UUID = UUID(), content: LayerContent,
         transform: LayerTransform = LayerTransform()) {
        self.id = id
        self.content = content
        self.transform = transform
    }
}

/// A layered composition — the canvas editor's document, embedded in the
/// stamp index (layer payloads are bytes; pixels live in files).
struct CanvasDocument: Codable, Equatable {
    enum Background: Codable, Equatable {
        case paper(StampVariant)
        case polaroid
        case card
    }
    var background: Background = .card
    /// Canvas height / width. Stamp paper 1.3125, polaroid ≈1.22, card 1.30.
    var aspect: CGFloat = 1.30
    var layers: [CanvasLayer] = []

    /// The stage aspect each background stock wants.
    static func aspect(for background: Background) -> CGFloat {
        switch background {
        case .paper: 1.3125
        case .polaroid: 1.22
        case .card: 1.30
        }
    }
}
