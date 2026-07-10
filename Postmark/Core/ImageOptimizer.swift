import UIKit
import ImageIO
import UniformTypeIdentifiers

/// Keeps the collection light: stamps are stored downscaled and HEIC-encoded
/// (alpha preserved for die-cut stickers) instead of full-resolution PNGs —
/// typically 10–20× smaller with no visible difference at display sizes.
enum ImageOptimizer {

    /// Encoded bytes ready to write. Falls back to PNG when HEIC encoding
    /// is unavailable; readers sniff content, so the extension never lies
    /// in a way that matters.
    static func optimized(_ image: UIImage, maxDimension: CGFloat = 1600) -> Data? {
        let scaled = downscaled(image, maxDimension: maxDimension)
        guard let cg = scaled.cgImage else { return scaled.pngData() }

        let out = NSMutableData()
        if let dest = CGImageDestinationCreateWithData(
            out, UTType.heic.identifier as CFString, 1, nil
        ) {
            let options: [CFString: Any] = [
                kCGImageDestinationLossyCompressionQuality: 0.88
            ]
            CGImageDestinationAddImage(dest, cg, options as CFDictionary)
            if CGImageDestinationFinalize(dest), out.length > 0 {
                return out as Data
            }
        }
        return scaled.pngData()
    }

    /// Messages-drawer sticker: PNG (MSSticker cannot read HEIC) within
    /// Apple's limits — ≤618 px and, critically, ≤500 KB or MSSticker
    /// throws and the sticker silently vanishes from the drawer.
    static func stickerPNG(_ image: UIImage) -> Data? {
        var dimension: CGFloat = 618
        while dimension >= 250 {
            if let data = downscaled(image, maxDimension: dimension).pngData(),
               data.count <= 480_000 {
                return data
            }
            dimension -= 80
        }
        return nil
    }

    /// Aspect-preserving downscale in pixel space; returns the original
    /// when it is already small enough. Alpha is preserved.
    static func downscaled(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let px = CGSize(width: image.size.width * image.scale,
                        height: image.size.height * image.scale)
        let longSide = max(px.width, px.height)
        guard longSide > maxDimension, longSide > 0 else { return image }

        let k = maxDimension / longSide
        let target = CGSize(width: floor(px.width * k), height: floor(px.height * k))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
