import Vision
import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

/// Apple Vision pipeline: lift the subject, name it, pick a stamp tint.
/// Every step degrades gracefully — worst case the stamp is a classic
/// full-frame photo titled by hand.
enum VisionService {

    struct Analysis {
        /// Subject-only RGBA at the crop's full pixel size (mask-aligned, used
        /// by the grain-dissolve shader and reveal continuity).
        var cutout: UIImage?
        /// Trimmed cutout with the white die-cut sticker border (display).
        var sticker: UIImage?
        /// The sticker's coverage in the crop, normalized 0–1 raster coords.
        var stickerBox: CGRect?
        var label: String?
        var tint: RGBValue
    }

    static func analyze(
        _ image: UIImage,
        fallbackCutout: UIImage?,
        fallbackLabel: String?
    ) async -> Analysis {
        let work = Task.detached(priority: .userInitiated) { () -> Analysis in
            guard let cg = image.cgImage else {
                return Analysis(tint: .paper)
            }

            var cutout = subjectCutout(from: cg)
            if cutout == nil, let fallback = fallbackCutout?.cgImage,
               alphaCoverage(of: fallback) > 0.02 {
                cutout = fallback
            }
            if let c = cutout {
                let coverage = alphaCoverage(of: c)
                if coverage < 0.025 || coverage > 0.92 { cutout = nil }
            }

            let label = classify(cutout ?? cg) ?? fallbackLabel
            let tintSource = dominantColor(of: cutout ?? cg)
            let tint = RGBValue.stampTint(from: tintSource)

            var sticker: UIImage? = nil
            var stickerBox: CGRect? = nil
            if let c = cutout, let result = StampRenderer.sticker(from: c) {
                sticker = result.image
                stickerBox = result.box
            }

            let cutoutImage = cutout.map { UIImage(cgImage: $0, scale: 1, orientation: .up) }
            return Analysis(cutout: cutoutImage, sticker: sticker, stickerBox: stickerBox,
                            label: label, tint: tint)
        }
        return await work.value
    }

    // MARK: Subject lifting

    private static func subjectCutout(from cg: CGImage) -> CGImage? {
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        let request = VNGenerateForegroundInstanceMaskRequest()
        do {
            try handler.perform([request])
            guard let observation = request.results?.first else { return nil }
            let buffer = try observation.generateMaskedImage(
                ofInstances: observation.allInstances,
                from: handler,
                croppedToInstancesExtent: false
            )
            let ci = CIImage(cvPixelBuffer: buffer)
            return CIContext.shared.createCGImage(ci, from: ci.extent)
        } catch {
            return nil
        }
    }

    // MARK: Naming

    private static let genericIdentifiers: Set<String> = [
        "structure", "material", "machine", "equipment", "furniture",
        "container", "indoor", "outdoor", "adult", "people", "textile",
        "pattern", "design", "art", "still_life", "product", "document",
        "tableware", "utensil", "cookware", "drink", "liquid", "foliage",
        "plant", "food", "vegetable", "fruit", "decoration", "toy",
    ]

    private static func classify(_ cg: CGImage) -> String? {
        let request = VNClassifyImageRequest()
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        guard (try? handler.perform([request])) != nil,
              let results = request.results else { return nil }
        let best = results
            .filter { $0.confidence >= 0.30 && !genericIdentifiers.contains($0.identifier) }
            .max(by: { $0.confidence < $1.confidence })
        guard let best else { return nil }
        return best.identifier
            .split(separator: "_")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    // MARK: Color

    private static func alphaCoverage(of cg: CGImage) -> Double {
        guard let pixels = downsample(cg, side: 32) else { return 0 }
        var sum = 0.0
        for i in stride(from: 3, to: pixels.count, by: 4) { sum += Double(pixels[i]) }
        return sum / (Double(pixels.count / 4) * 255)
    }

    private static func dominantColor(of cg: CGImage) -> UIColor {
        guard let px = downsample(cg, side: 16) else { return .gray }
        var r = 0.0, g = 0.0, b = 0.0, w = 0.0
        for i in stride(from: 0, to: px.count, by: 4) {
            let a = Double(px[i + 3]) / 255
            guard a > 0.4 else { continue }
            let pr = Double(px[i]) / 255, pg = Double(px[i + 1]) / 255, pb = Double(px[i + 2]) / 255
            let sat = max(pr, pg, pb) - min(pr, pg, pb)
            let luma = 0.299 * pr + 0.587 * pg + 0.114 * pb
            // favor colorful midtones; ignore near-black/near-white noise
            let weight = a * (0.2 + sat) * (1 - abs(luma - 0.5) * 0.9)
            r += pr * weight; g += pg * weight; b += pb * weight; w += weight
        }
        guard w > 0.001 else { return .gray }
        return UIColor(red: r / w, green: g / w, blue: b / w, alpha: 1)
    }

    /// RGBA8 premultiplied-last pixel dump at `side`×`side`.
    private static func downsample(_ cg: CGImage, side: Int) -> [UInt8]? {
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        guard let ctx = CGContext(
            data: &pixels, width: side, height: side,
            bitsPerComponent: 8, bytesPerRow: side * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.interpolationQuality = .low
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))
        return pixels
    }
}

extension CIContext {
    static let shared = CIContext(options: [.useSoftwareRenderer: false])
}
