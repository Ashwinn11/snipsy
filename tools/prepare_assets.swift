// Prepares the onboarding demo assets: resizes raw photos and runs the SAME
// Vision pipeline the app uses (VNGenerateForegroundInstanceMaskRequest) on
// macOS to precompute subject cutouts. Titles/tints live in OnboardingDemo.
// Run: swift tools/prepare_assets.swift
import AppKit
import Vision
import CoreImage

let samples: [(raw: String, name: String)] = [
    ("robot.jpg", "robot"),
    ("teapot.jpg", "teapot"),
    ("coffee.jpg", "coffee"),
    ("cactus.jpg", "cactus"),
]

let rawDir = URL(fileURLWithPath: "tools/raw")
let outDir = URL(fileURLWithPath: "Postmark/Resources/Onboarding")
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

let ciContext = CIContext()

func loadCG(_ url: URL) -> CGImage? {
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(src, 0, [
        kCGImageSourceShouldCache: true
    ] as CFDictionary)
}

func resize(_ cg: CGImage, maxSide: CGFloat) -> CGImage {
    let w = CGFloat(cg.width), h = CGFloat(cg.height)
    let scale = min(1, maxSide / max(w, h))
    if scale >= 1 { return cg }
    let nw = Int(w * scale), nh = Int(h * scale)
    let ctx = CGContext(
        data: nil, width: nw, height: nh, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    ctx.interpolationQuality = .high
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: nw, height: nh))
    return ctx.makeImage()!
}

func writeJPEG(_ cg: CGImage, to url: URL) {
    let rep = NSBitmapImageRep(cgImage: cg)
    let data = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.87])!
    try! data.write(to: url)
}

func writePNG(_ cg: CGImage, to url: URL) {
    let rep = NSBitmapImageRep(cgImage: cg)
    let data = rep.representation(using: .png, properties: [:])!
    try! data.write(to: url)
}

func subjectCutout(_ cg: CGImage) -> CGImage? {
    let handler = VNImageRequestHandler(cgImage: cg, options: [:])
    let request = VNGenerateForegroundInstanceMaskRequest()
    do {
        try handler.perform([request])
        guard let obs = request.results?.first else { return nil }
        let buffer = try obs.generateMaskedImage(
            ofInstances: obs.allInstances, from: handler,
            croppedToInstancesExtent: false
        )
        let ci = CIImage(cvPixelBuffer: buffer)
        return ciContext.createCGImage(ci, from: ci.extent)
    } catch {
        print("  mask failed: \(error.localizedDescription)")
        return nil
    }
}

func classify(_ cg: CGImage) -> [(String, Float)] {
    let request = VNClassifyImageRequest()
    try? VNImageRequestHandler(cgImage: cg, options: [:]).perform([request])
    return (request.results ?? []).prefix(5).map { ($0.identifier, $0.confidence) }
}

for sample in samples {
    let rawURL = rawDir.appendingPathComponent(sample.raw)
    guard let cg = loadCG(rawURL) else { print("missing \(sample.raw)"); continue }
    let resized = resize(cg, maxSide: 1600)
    let jpgName = "\(sample.name).jpg"
    writeJPEG(resized, to: outDir.appendingPathComponent(jpgName))
    print("\(sample.name): \(resized.width)×\(resized.height)")

    if let cutout = subjectCutout(resized) {
        writePNG(cutout, to: outDir.appendingPathComponent("\(sample.name).cutout.png"))
        print("  cutout ✓ (\(cutout.width)×\(cutout.height))")
    }
    print("  classify: \(classify(resized).map { "\($0.0) \(String(format: "%.2f", $0.1))" }.joined(separator: ", "))")
}

