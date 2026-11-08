#!/usr/bin/env swift
// Usage: swift .github/assets/make-icon.swift .github/assets/icon.png
// Tac project icon: glassy white SF "switch.2" glyph on a rose→violet→indigo squircle.
// Same macOS grid as Flusso: 824 body, continuous corners r≈185, shadow in margin.
import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let out = URL(fileURLWithPath: CommandLine.arguments[1])
let symbolName = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "switch.2"
let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
func rgb(_ h: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: srgb, components: [CGFloat((h >> 16) & 0xFF)/255, CGFloat((h >> 8) & 0xFF)/255, CGFloat(h & 0xFF)/255, a])!
}
func grad(_ s: [(CGFloat, CGColor)]) -> CGGradient {
    CGGradient(colorsSpace: srgb, colors: s.map { $0.1 } as CFArray, locations: s.map { $0.0 })!
}
func continuousRect(_ r: CGRect, radius: CGFloat, n: CGFloat = 3.3) -> CGPath {
    let s = min(radius * 1.528, min(r.width, r.height) / 2)
    let p = CGMutablePath(); var first = true
    let corners: [(CGPoint, CGFloat)] = [
        (CGPoint(x: r.maxX - s, y: r.minY + s), -.pi/2), (CGPoint(x: r.maxX - s, y: r.maxY - s), 0),
        (CGPoint(x: r.minX + s, y: r.maxY - s), .pi/2), (CGPoint(x: r.minX + s, y: r.minY + s), .pi)]
    for (c, start) in corners {
        for i in 0...96 {
            let t = start + (.pi/2) * CGFloat(i)/96, ct = cos(t), st = sin(t)
            let pt = CGPoint(x: c.x + s * copysign(pow(abs(ct), 2/n), ct), y: c.y + s * copysign(pow(abs(st), 2/n), st))
            if first { p.move(to: pt); first = false } else { p.addLine(to: pt) }
        }
    }
    p.closeSubpath(); return p
}
func bitmap(_ px: Int) -> CGContext {
    CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0, space: srgb,
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

// Glyph layer (1024 space): symbol alpha filled with a white→ice gradient.
func glyphLayer(px: Int) -> (CGImage, CGRect) {
    let cfg = NSImage.SymbolConfiguration(pointSize: 470, weight: .medium)
    let sym = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)!.withSymbolConfiguration(cfg)!
    let maxSide: CGFloat = 540
    let sc = maxSide / max(sym.size.width, sym.size.height)
    let w = sym.size.width * sc, h = sym.size.height * sc
    let rect = CGRect(x: 512 - w/2, y: 512 - h/2 + 6, width: w, height: h)
    let ctx = bitmap(px); let k = CGFloat(px)/1024; ctx.scaleBy(x: k, y: k)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    sym.draw(in: rect)
    NSGraphicsContext.restoreGraphicsState()
    ctx.setBlendMode(.sourceIn)
    ctx.drawLinearGradient(grad([(0, rgb(0xFFFFFF)), (0.55, rgb(0xFFF6FB)), (1, rgb(0xE9E2FF))]),
                           start: CGPoint(x: 512, y: rect.maxY), end: CGPoint(x: 512, y: rect.minY), options: [])
    // specular sheen on the upper half
    ctx.drawLinearGradient(grad([(0, rgb(0xFFFFFF, 0.0)), (1, rgb(0xFFFFFF, 0.0))]),
                           start: .zero, end: CGPoint(x: 0, y: 1), options: [])
    return (ctx.makeImage()!, rect)
}

func render(_ px: Int) -> CGImage {
    let ctx = bitmap(px); let k = CGFloat(px)/1024
    ctx.interpolationQuality = .high; ctx.scaleBy(x: k, y: k)
    let bodyRect = CGRect(x: 100, y: 100, width: 824, height: 824)
    let body = continuousRect(bodyRect, radius: 185)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12*k), blur: 28*k, color: rgb(0, 0.32))
    ctx.addPath(body); ctx.setFillColor(rgb(0x3A1060)); ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState(); ctx.addPath(body); ctx.clip()
    ctx.drawLinearGradient(grad([(0, rgb(0xFF5E9C)), (0.5, rgb(0xB24BF3)), (1, rgb(0x4B3FE0))]),
                           start: CGPoint(x: 230, y: 924), end: CGPoint(x: 800, y: 100), options: [])
    ctx.drawRadialGradient(grad([(0, rgb(0xFFB37A, 0.55)), (1, rgb(0xFFB37A, 0))]),
                           startCenter: CGPoint(x: 200, y: 900), startRadius: 0,
                           endCenter: CGPoint(x: 200, y: 900), endRadius: 480, options: [])
    ctx.drawRadialGradient(grad([(0, rgb(0x5AC8FF, 0.45)), (1, rgb(0x5AC8FF, 0))]),
                           startCenter: CGPoint(x: 880, y: 140), startRadius: 0,
                           endCenter: CGPoint(x: 880, y: 140), endRadius: 500, options: [])
    ctx.drawLinearGradient(grad([(0, rgb(0xFFFFFF, 0.16)), (1, rgb(0xFFFFFF, 0))]),
                           start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 560), options: [])
    ctx.restoreGState()

    let (glyph, _) = glyphLayer(px: px)
    let full = CGRect(x: 0, y: 0, width: 1024, height: 1024)
    // soft glow + contact shadow
    ctx.saveGState(); ctx.addPath(body); ctx.clip()
    ctx.setShadow(offset: CGSize(width: 0, height: -16*k), blur: 40*k, color: rgb(0x2A0A5A, 0.45))
    ctx.draw(glyph, in: full)
    ctx.restoreGState()
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 46*k, color: rgb(0xFFE6F4, 0.55))
    ctx.draw(glyph, in: full)
    ctx.restoreGState()

    // glass rim on the body
    ctx.saveGState(); ctx.addPath(body); ctx.clip()
    ctx.addPath(body); ctx.setLineWidth(8); ctx.replacePathWithStrokedPath(); ctx.clip()
    ctx.drawLinearGradient(grad([(0, rgb(0xFFFFFF, 0.7)), (0.35, rgb(0xFFFFFF, 0.1)), (0.8, rgb(0xFFFFFF, 0.12)), (1, rgb(0xFFFFFF, 0.35))]),
                           start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    ctx.restoreGState()
    return ctx.makeImage()!
}

let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, render(1024), nil)
precondition(CGImageDestinationFinalize(dest))
print(out.path)
