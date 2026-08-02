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

        guard var cg = scaled.cgImage else { return scaled.pngData() }

        // A camera photo arrives premultiplied-alpha with every alpha byte
        // at 255, and `downscaled` returns the image untouched when it's
        // already within bounds — so a 1280×1600 crop (exactly the 1600
        // limit) reaches the encoder still carrying a pointless alpha
        // channel. HEIC then logs an error, writes a larger file, and
        // doubles the memory needed to decode it later.
        //
        // Rebuilt through an explicit `noneSkipLast` context rather than by
        // asking UIGraphicsImageRenderer for an opaque format — this way the
        // absence of the channel is guaranteed by the bitmap layout instead
        // of by a hint the renderer is free to interpret.
        if carriesAlphaChannel(cg), !hasTransparency(cg),
           let flattened = withoutAlphaChannel(cg) {
            cg = flattened
        }

        #if DEBUG
        // Temporary: three attempts at the AlphaPremulLast warning have
        // missed, so stop inferring which writer runs and print it.
        print("[opt] \(cg.width)x\(cg.height) alpha=\(cg.alphaInfo.rawValue) "
              + "channel=\(carriesAlphaChannel(cg)) transparent=\(hasTransparency(cg))")
        #endif

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

    /// Decode a photo at bounded size without ever materializing the full
    /// bitmap — mandatory inside app extensions (~120 MB jetsam ceiling; a
    /// 48 MP decode plus an orientation redraw is an instant kill). The
    /// thumbnail transform applies EXIF orientation during decode.
    static func downsampled(url: URL, maxPixel: CGFloat = 2000) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return downsampled(source: source, maxPixel: maxPixel)
    }

    static func downsampled(data: Data, maxPixel: CGFloat = 2000) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return downsampled(source: source, maxPixel: maxPixel)
    }

    private static func downsampled(source: CGImageSource, maxPixel: CGFloat) -> UIImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }
        return UIImage(cgImage: cg, scale: 1, orientation: .up)
    }

    /// Library photos carry EXIF orientation; CGImage cropping ignores it.
    /// Redraw to .up before any pixel-space math.
    static func normalizedOrientation(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else { return image }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
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
    /// Whether the bitmap has an alpha channel at all. Says nothing about
    /// whether any pixel is actually see-through.
    static func carriesAlphaChannel(_ cg: CGImage) -> Bool {
        switch cg.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: return false
        default: return true
        }
    }

    /// Whether anything is genuinely see-through. Sampled at 32² — enough to
    /// catch a die cut's cleared background, cheap enough to run on every
    /// save. Errs toward `true`: wrongly flattening a cutout would destroy
    /// it, while wrongly keeping a channel only costs bytes.
    static func hasTransparency(_ cg: CGImage) -> Bool {
        let side = 32
        var px = [UInt8](repeating: 0, count: side * side * 4)
        guard let ctx = CGContext(
            data: &px, width: side, height: side, bitsPerComponent: 8,
            bytesPerRow: side * 4, space: CGColorSpaceDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return true }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))
        for i in stride(from: 3, to: px.count, by: 4) where px[i] < 250 {
            return true
        }
        return false
    }

    private static func CGColorSpaceDeviceRGB() -> CGColorSpace {
        CGColorSpaceCreateDeviceRGB()
    }

    /// The same pixels in a bitmap that has no alpha channel at all.
    ///
    /// Built with an explicit `noneSkipLast` layout rather than by asking
    /// `UIGraphicsImageRenderer` for an opaque format — the renderer treats
    /// `opaque` as a hint and can still hand back a premultiplied bitmap,
    /// which is how the encoder kept receiving alpha after two attempts to
    /// remove it.
    private static func withoutAlphaChannel(_ cg: CGImage) -> CGImage? {
        let space = cg.colorSpace.flatMap { $0.model == .rgb ? $0 : nil }
            ?? CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: cg.width, height: cg.height,
            bitsPerComponent: 8, bytesPerRow: 0, space: space,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        return ctx.makeImage()
    }

    static func downscaled(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let px = CGSize(width: image.size.width * image.scale,
                        height: image.size.height * image.scale)
        let longSide = max(px.width, px.height)
        guard longSide > maxDimension, longSide > 0 else { return image }

        let k = maxDimension / longSide
        let target = CGSize(width: floor(px.width * k), height: floor(px.height * k))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        // Follow the source instead of always assuming alpha. Die cuts need
        // it; a camera photo doesn't, and handing HEIC an opaque image in an
        // AlphaPremulLast bitmap makes it log an error, inflates the file,
        // and doubles the memory required to decode it later.
        format.opaque = !(image.cgImage.map {
            Self.carriesAlphaChannel($0) && Self.hasTransparency($0)
        } ?? true)
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
