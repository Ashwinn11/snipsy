import SwiftUI
import UIKit

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

    var displayTitle: String { title.isEmpty ? "Untitled" : title }
    var year: String { Stamp.yearFormatter.string(from: date) }

    private static let yearFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy"
        return f
    }()
}

/// Result of a shutter press, before Vision has run.
struct Capture {
    /// Screen-exact frozen frame (what the user saw, edge to edge).
    let screenImage: UIImage
    /// Viewfinder-cropped image (what becomes the stamp).
    let cropImage: UIImage
    /// Viewfinder rect in full-screen view coordinates.
    let viewfinderRect: CGRect
    /// Demo-mode fallbacks (precomputed on macOS with the same Vision API),
    /// already cropped to the viewfinder.
    let fallbackCutout: UIImage?
    let fallbackLabel: String?
}

/// A stamp being assembled on the reveal screen — not yet kept.
struct PendingStamp {
    var capture: Capture
    var style: Stamp.Style
    /// Full-crop-size subject-only image (drives the mask dissolve).
    var cutout: UIImage?
    /// Trimmed cutout with white die-cut border (final display image).
    var sticker: UIImage?
    /// Sticker coverage in the crop, normalized (reveal settle start frame).
    var stickerBox: CGRect?
    var suggestedTitle: String?
    var tint: RGBValue

    /// What gets persisted and shown on the finished stamp.
    var displayImage: UIImage { sticker ?? capture.cropImage }
}
