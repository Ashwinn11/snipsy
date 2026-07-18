import SwiftUI
import UIKit

/// A stamp dressing — the paper world the die-cut sticker lands in. The
/// user picks one from the chooser after the die cut.
enum StampVariant: String, Codable, CaseIterable, Identifiable {
    /// Paper tinted from the photo's own palette (the signature look).
    case tinted
    /// Heirloom cameo: lavender sheet, the picture in an engraved oval.
    case ivory
    /// Poster: deep ink sheet, the picture bleeds, type prints airy and light.
    case ink
    /// Par avion: near-white sheet ringed by the red/blue chevron border.
    case airmail
    /// National issue: plum sheet, red keyline, denomination bar at the foot.
    case commemorative
    /// Special edition: gold-foil plate frame with a holographic sheen.
    case foil
    /// Official document: teal sheet, duty bars, monospace voice.
    case revenue
    /// Definitive series: the picture printed as a single green ink.
    case botanical
    /// After dark: midnight sheet, a neon keyline glowing around the picture.
    case night
    /// Keepsake: rose sheet, delicate engraved hairlines, italic caption.
    case sweetheart

    var id: String { rawValue }
}

/// What the user chose to make from a capture. A sticker is a first-class
/// collectible: bare die-cut in the album and the Messages drawer; a stamp
/// is the dressed artifact; a polaroid/card is the framed instant photo;
/// a canvas is a layered composition built in the editor.
enum ArtifactKind: String, Codable {
    case stamp
    case sticker
    case polaroid
    case card
    case canvas
}

/// A collected stamp.
struct Stamp: Identifiable, Codable, Equatable {
    enum Style: String, Codable {
        /// Vision lifted the subject; it sits die-cut on stamp paper.
        case cutout
        /// No mask available; the full crop fills the stamp frame.
        case classic
    }

    let id: UUID
    var title: String
    var date: Date
    var number: Int
    var style: Style
    var tint: RGBValue
    /// PNG in the store's images directory: the die-cut sticker (cutout style)
    /// or the viewfinder crop (classic style).
    var imageFile: String
    var variant: StampVariant = .tinted
    var kind: ArtifactKind = .stamp
    /// Sticker items: contour fraction where the name label anchors.
    /// nil = legacy item whose label was baked into the image.
    var labelAnchor: CGFloat? = nil
    /// Layered composition, nil for single-shot artifacts. Present ⇒
    /// imageFile is the flattened preview and the creation is re-editable.
    var canvas: CanvasDocument? = nil

    var displayTitle: String { title.isEmpty ? "Untitled" : title }

    /// Every image file this stamp owns under images/ — the flattened
    /// preview plus any canvas layer pixels. Deletion must remove all.
    var allImageFiles: [String] {
        var files = [imageFile]
        for layer in canvas?.layers ?? [] {
            switch layer.content {
            case .image(let file, let cutoutFile, _):
                files.append(file)
                if let cutoutFile { files.append(cutoutFile) }
            case .sticker(let file):
                files.append(file)
            case .text, .doodle:
                break
            }
        }
        return files
    }
}

extension Stamp {
    /// Backward-compatible decoding: stamps saved before variants existed
    /// decode as .tinted instead of failing (and losing the album).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        date = try c.decode(Date.self, forKey: .date)
        number = try c.decode(Int.self, forKey: .number)
        style = try c.decode(Style.self, forKey: .style)
        tint = try c.decode(RGBValue.self, forKey: .tint)
        imageFile = try c.decode(String.self, forKey: .imageFile)
        variant = (try? c.decodeIfPresent(StampVariant.self, forKey: .variant)) ?? .tinted
        kind = (try? c.decodeIfPresent(ArtifactKind.self, forKey: .kind)) ?? .stamp
        labelAnchor = try? c.decodeIfPresent(CGFloat.self, forKey: .labelAnchor)
        canvas = try? c.decodeIfPresent(CanvasDocument.self, forKey: .canvas)
    }
}

/// Result of a shutter press, before Vision has run.
struct Capture {
    /// Screen-exact frozen frame (what the user saw, edge to edge).
    let screenImage: UIImage
    /// Viewfinder-cropped image (what becomes the stamp).
    let cropImage: UIImage
    /// Viewfinder rect in full-screen view coordinates.
    let viewfinderRect: CGRect
}

/// A stamp being assembled on the reveal screen — not yet kept.
struct PendingStamp {
    var capture: Capture
    var style: Stamp.Style
    /// Subject-only image, aspect-aligned to the crop (drives the mask
    /// dissolve; sampled normalized, so resolution may differ).
    var cutout: UIImage?
    /// Trimmed cutout with white die-cut border (final display image).
    var sticker: UIImage?
    /// Sticker coverage in the crop, normalized (reveal settle start frame).
    var stickerBox: CGRect?
    /// Contour fraction for the sticker's name label.
    var stickerLabelAnchor: CGFloat?
    var suggestedTitle: String?
    var tint: RGBValue

    /// What gets persisted and shown on the finished stamp.
    var displayImage: UIImage { sticker ?? capture.cropImage }
}
