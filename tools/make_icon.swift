// Renders AppIcon.png (1024×1024): a tilted perforated stamp on warm paper,
// postal-red pinwheel-iris disc, caption dashes, and a corner postmark.
// Run: swift tools/make_icon.swift
import AppKit
import CoreGraphics

let S: CGFloat = 1024
let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

func makeContext(_ w: Int, _ h: Int) -> CGContext {
    CGContext(
        data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
        space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
}

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255, alpha: a
    )
}

let paper = rgb(0xF4EFE6)
let paperHi = rgb(0xFAF7F0)
let red = rgb(0xC7402D)
let stampPaper = rgb(0xFFFDF7)

// ── Stamp layer (transparent, holes punched with .clear) ────────────
let W: CGFloat = 560, H: CGFloat = 700
let pad: CGFloat = 40   // room for the hole punches at the edge
let layer = makeContext(Int(W + pad * 2), Int(H + pad * 2))
layer.translateBy(x: pad, y: pad)

let stampRect = CGRect(x: 0, y: 0, width: W, height: H)
layer.setFillColor(stampPaper)
layer.fill(stampRect)

// Hairline inner frame
let inner = stampRect.insetBy(dx: 50, dy: 50)
layer.setStrokeColor(rgb(0x221F1A, 0.30))
layer.setLineWidth(4)
layer.stroke(inner)

// Red disc with pinwheel iris
let discC = CGPoint(x: W / 2, y: H / 2 + 46)
let discR: CGFloat = 158
layer.setFillColor(red)
layer.fillEllipse(in: CGRect(x: discC.x - discR, y: discC.y - discR,
                             width: discR * 2, height: discR * 2))
layer.saveGState()
layer.addEllipse(in: CGRect(x: discC.x - discR, y: discC.y - discR,
                            width: discR * 2, height: discR * 2))
layer.clip()
layer.setStrokeColor(stampPaper)
layer.setLineWidth(14)
layer.setLineCap(.round)
// Classic shutter: partial chords V(i) → 66% of the way to V(i+2),
// vertices just past the rim so blades emerge from the disc edge.
let blades = 6
let rOut: CGFloat = discR + 8
let vertices = (0..<blades).map { i -> CGPoint in
    let a = CGFloat(i) / CGFloat(blades) * 2 * .pi + .pi / 8
    return CGPoint(x: discC.x + cos(a) * rOut, y: discC.y + sin(a) * rOut)
}
for i in 0..<blades {
    let from = vertices[i]
    let to = vertices[(i + 2) % blades]
    layer.move(to: from)
    layer.addLine(to: CGPoint(
        x: from.x + (to.x - from.x) * 0.66,
        y: from.y + (to.y - from.y) * 0.66
    ))
}
layer.strokePath()
layer.restoreGState()

// Caption dashes
layer.setFillColor(rgb(0x221F1A, 0.68))
let capY: CGFloat = 106
for (x, len) in [(W / 2 - 128, CGFloat(104)), (W / 2 + 0, CGFloat(150))] {
    let rr = CGPath(roundedRect: CGRect(x: x, y: capY, width: len, height: 18),
                    cornerWidth: 9, cornerHeight: 9, transform: nil)
    layer.addPath(rr)
    layer.fillPath()
}
layer.setFillColor(rgb(0x221F1A, 0.40))
for x in [inner.minX + 6, inner.maxX - 44] {
    let rr = CGPath(roundedRect: CGRect(x: x, y: capY + 2, width: 38, height: 14),
                    cornerWidth: 7, cornerHeight: 7, transform: nil)
    layer.addPath(rr)
    layer.fillPath()
}

// Punch perforation holes (clear blend erases the layer)
let r: CGFloat = 19
func holeCenters(_ length: CGFloat) -> [CGFloat] {
    let n = max(2, Int((length / (r * 2.9)).rounded()))
    let step = length / CGFloat(n)
    return (0...n).map { CGFloat($0) * step }
}
layer.setBlendMode(.clear)
layer.setFillColor(CGColor(gray: 0, alpha: 1))
for x in holeCenters(W) {
    layer.fillEllipse(in: CGRect(x: x - r, y: -r, width: r * 2, height: r * 2))
    layer.fillEllipse(in: CGRect(x: x - r, y: H - r, width: r * 2, height: r * 2))
}
for y in holeCenters(H) {
    layer.fillEllipse(in: CGRect(x: -r, y: y - r, width: r * 2, height: r * 2))
    layer.fillEllipse(in: CGRect(x: W - r, y: y - r, width: r * 2, height: r * 2))
}
layer.setBlendMode(.normal)
let stampImage = layer.makeImage()!

// ── Main canvas ─────────────────────────────────────────────────────
let ctx = makeContext(Int(S), Int(S))

ctx.setFillColor(paper)
ctx.fill(CGRect(x: 0, y: 0, width: S, height: S))
let grad = CGGradient(colorsSpace: srgb, colors: [paperHi, paper] as CFArray,
                      locations: [0, 1])!
ctx.drawRadialGradient(
    grad, startCenter: CGPoint(x: S * 0.5, y: S * 0.62), startRadius: 0,
    endCenter: CGPoint(x: S * 0.5, y: S * 0.5), endRadius: S * 0.75, options: []
)

// Dot grid
ctx.setFillColor(rgb(0x221F1A, 0.05))
let spacing: CGFloat = 74
var gy = spacing / 2
while gy < S {
    var gx = spacing / 2
    while gx < S {
        ctx.fillEllipse(in: CGRect(x: gx - 3, y: gy - 3, width: 6, height: 6))
        gx += spacing
    }
    gy += spacing
}

// Stamp, tilted, with soft shadow
ctx.saveGState()
ctx.translateBy(x: S / 2, y: S / 2)
ctx.rotate(by: -8 * .pi / 180)
ctx.setShadow(offset: CGSize(width: 0, height: -16), blur: 48, color: rgb(0x221F1A, 0.30))
let drawW = W + pad * 2, drawH = H + pad * 2
ctx.draw(stampImage, in: CGRect(x: -drawW / 2, y: -drawH / 2, width: drawW, height: drawH))
ctx.restoreGState()

// Postmark: double ring + wavy bars, overlapping the stamp's top-right
let pmC = CGPoint(x: S * 0.760, y: S * 0.770)
let pmInk = rgb(0x3A362E, 0.60)
ctx.setStrokeColor(pmInk)
ctx.setLineWidth(11)
ctx.strokeEllipse(in: CGRect(x: pmC.x - 132, y: pmC.y - 132, width: 264, height: 264))
ctx.setLineWidth(6)
ctx.strokeEllipse(in: CGRect(x: pmC.x - 104, y: pmC.y - 104, width: 208, height: 208))
ctx.setLineWidth(12)
ctx.setLineCap(.round)
for i in 0..<3 {
    let y0 = pmC.y - 42 + CGFloat(i) * 42
    var x = pmC.x + 142
    ctx.move(to: CGPoint(x: x, y: y0))
    while x < pmC.x + 240 {
        x += 6
        ctx.addLine(to: CGPoint(x: x, y: y0 + sin((x - pmC.x) / 30) * 8))
    }
    ctx.strokePath()
}

// ── Write PNG ───────────────────────────────────────────────────────
let image = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: image)
let data = rep.representation(using: .png, properties: [:])!
let out = URL(fileURLWithPath: "Postmark/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png")
try! data.write(to: out)
print("icon written: \(out.path)")
