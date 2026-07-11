import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins

/// Image cookery for stamps: alpha trimming, the white die-cut sticker border,
/// and flattened share renders.
enum StampRenderer {

    struct StickerResult {
        let image: UIImage
        /// The sticker's coverage rect in the source image's raster space,
        /// normalized 0–1 (drives the reveal's settle animation).
        let box: CGRect
        /// Fraction of the sticker image's height where the visible contour
        /// actually sits within the central column band — where the name
        /// label must anchor to fuse with the cut.
        let labelAnchor: CGFloat
    }

    /// Trim transparent margins (with breathing room) and add the white
    /// sticker border — CapWords-style die-cut. Runs once at analysis time.
    static func sticker(from cg: CGImage, borderFraction: CGFloat = 0.035) -> StickerResult? {
        guard let (trimmed, trimBox, centralBottom) = trimToAlpha(cg, paddingFraction: 0.09)
        else { return nil }
        let radius = max(3, CGFloat(max(trimmed.width, trimmed.height)) * borderFraction)

        let ci = CIImage(cgImage: trimmed)
        let dilate = CIFilter.morphologyMaximum()
        dilate.inputImage = ci
        dilate.radius = Float(radius)
        guard let dilated = dilate.outputImage else { return nil }

        // alpha → solid white shape
        let white = dilated.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputBiasVector": CIVector(x: 1, y: 1, z: 1, w: 0),
        ])

        let composed = ci.composited(over: white)
        let renderRect = ci.extent.insetBy(dx: -radius - 2, dy: -radius - 2).integral
        guard let out = CIContext.shared.createCGImage(composed, from: renderRect) else { return nil }

        // The rendered sticker covers trimBox grown by the border margin.
        let grow = radius + 2
        let coverage = CGRect(
            x: (trimBox.minX - grow) / CGFloat(cg.width),
            y: (trimBox.minY - grow) / CGFloat(cg.height),
            width: (trimBox.width + grow * 2) / CGFloat(cg.width),
            height: (trimBox.height + grow * 2) / CGFloat(cg.height)
        )
        // Contour row → fraction of the FINAL image height (content sits
        // grow points inside the rendered rect on every side).
        let anchor = (grow + (centralBottom - trimBox.minY) + radius)
            / (trimBox.height + grow * 2)
        return StickerResult(
            image: UIImage(cgImage: out, scale: 1, orientation: .up),
            box: coverage,
            labelAnchor: min(max(anchor, 0.2), 1.0)
        )
    }

    /// Bounding box of non-transparent pixels, padded, cropped to a new image.
    /// Returns the crop, its rect in source raster space, and the lowest
    /// opaque row within the central 50% of the subject's columns (source
    /// raster px) — the true contour under a centered label.
    static func trimToAlpha(
        _ cg: CGImage, paddingFraction: CGFloat
    ) -> (CGImage, CGRect, CGFloat)? {
        let side = 128
        var pixels = [UInt8](repeating: 0, count: side * side)
        guard let ctx = CGContext(
            data: &pixels, width: side, height: side,
            bitsPerComponent: 8, bytesPerRow: side,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue
        ) else { return nil }
        ctx.interpolationQuality = .low
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))

        var minX = side, minY = side, maxX = -1, maxY = -1
        for y in 0..<side {
            for x in 0..<side where pixels[y * side + x] > 12 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }

        // Lowest opaque row within the central 50% of the subject's columns.
        let bandLo = minX + (maxX - minX) / 4
        let bandHi = maxX - (maxX - minX) / 4
        var centralBottom = maxY
        for y in stride(from: side - 1, through: 0, by: -1) {
            var hit = false
            for x in bandLo...max(bandLo, bandHi) where pixels[y * side + x] > 12 {
                hit = true
                break
            }
            if hit {
                centralBottom = y
                break
            }
        }

        // Context memory rows and CGImage.cropping both use raster space
        // (row 0 = top), so the box maps directly.
        let sx = CGFloat(cg.width) / CGFloat(side)
        let sy = CGFloat(cg.height) / CGFloat(side)
        var box = CGRect(
            x: CGFloat(minX) * sx,
            y: CGFloat(minY) * sy,
            width: CGFloat(maxX - minX + 1) * sx,
            height: CGFloat(maxY - minY + 1) * sy
        )
        let pad = max(box.width, box.height) * paddingFraction
        box = box.insetBy(dx: -pad, dy: -pad)
            .intersection(CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
            .integral
        guard let cropped = cg.cropping(to: box) else { return nil }
        return (cropped, box, (CGFloat(centralBottom) + 0.5) * sy)
    }
}
