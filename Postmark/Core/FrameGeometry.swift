import UIKit

/// Aspect-fill mapping between an image and the view it fills, used to convert
/// the on-screen viewfinder rect into image pixels. One code path serves both
/// the live camera (AVCaptureVideoPreviewLayer, .resizeAspectFill) and the
/// simulator demo feed (which adds a Ken Burns transform on top).
enum FrameGeometry {

    /// The transform placing `imageSize` into `viewSize` with aspect-fill,
    /// then optionally scaled by `drift.scale` about the view center and
    /// translated by `drift.offset` (demo feed motion).
    struct Drift {
        var scale: CGFloat = 1
        var offset: CGPoint = .zero
        static let none = Drift()
    }

    /// Rect in image pixel coordinates corresponding to `rectInView`.
    static func imageCrop(
        imageSize: CGSize,
        viewSize: CGSize,
        rectInView: CGRect,
        drift: Drift = .none
    ) -> CGRect {
        let fill = max(viewSize.width / imageSize.width,
                       viewSize.height / imageSize.height)
        let drawn = CGSize(width: imageSize.width * fill, height: imageSize.height * fill)
        let origin = CGPoint(x: (viewSize.width - drawn.width) / 2,
                             y: (viewSize.height - drawn.height) / 2)
        let center = CGPoint(x: viewSize.width / 2, y: viewSize.height / 2)

        // view = ((fillMap(image) − center) · s + center) + offset
        // ⇒ fillMap(image) = (view − offset − center) / s + center
        func unmap(_ p: CGPoint) -> CGPoint {
            let ux = (p.x - drift.offset.x - center.x) / drift.scale + center.x
            let uy = (p.y - drift.offset.y - center.y) / drift.scale + center.y
            return CGPoint(x: (ux - origin.x) / fill, y: (uy - origin.y) / fill)
        }

        let tl = unmap(CGPoint(x: rectInView.minX, y: rectInView.minY))
        let br = unmap(CGPoint(x: rectInView.maxX, y: rectInView.maxY))
        let rect = CGRect(x: tl.x, y: tl.y, width: br.x - tl.x, height: br.y - tl.y)
        return rect.intersection(CGRect(origin: .zero, size: imageSize))
    }

    /// Crop a normalized-`.up` UIImage in pixel coordinates.
    static func crop(_ image: UIImage, to pixelRect: CGRect) -> UIImage? {
        guard let cg = image.cgImage else { return nil }
        let scaled = CGRect(x: pixelRect.origin.x * image.scale,
                            y: pixelRect.origin.y * image.scale,
                            width: pixelRect.width * image.scale,
                            height: pixelRect.height * image.scale)
        guard let cropped = cg.cropping(to: scaled.integral) else { return nil }
        return UIImage(cgImage: cropped, scale: image.scale, orientation: .up)
    }
}

extension UIImage {
    /// Redraw so `imageOrientation == .up` and pixel data matches display.
    func normalizedUp() -> UIImage {
        if imageOrientation == .up { return self }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }

    /// Force-decode so first display never stutters on JPEG decompression.
    func predecoded() -> UIImage {
        preparingForDisplay() ?? self
    }
}
