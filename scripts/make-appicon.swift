#!/usr/bin/env swift
//
// Generates the macOS AppIcon PNGs for VideoDownloader.
// Run from the repo root:  swift scripts/make-appicon.swift
//
// Design: a full-bleed rounded "squircle" with a blue→purple vertical
// gradient and a white download glyph (arrow + base bar) — the app is a
// video downloader. Kept simple so it stays crisp down to 16px.
//
import AppKit

let outDir = "App/Assets.xcassets/AppIcon.appiconset"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

let sizes: [Int] = [16, 32, 64, 128, 256, 512, 1024]

func png(forSize px: Int) -> Data {
    let S = CGFloat(px)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // y-up coordinates. Helper: turn a "fraction from the top" into a CGRect.
    func rectTD(x: CGFloat, topD: CGFloat, w: CGFloat, h: CGFloat) -> CGRect {
        CGRect(x: x * S, y: S - (topD + h) * S, width: w * S, height: h * S)
    }
    func pt(_ x: CGFloat, _ topD: CGFloat) -> NSPoint { NSPoint(x: x * S, y: S - topD * S) }

    // Rounded-rect background clip + gradient.
    let full = CGRect(x: 0, y: 0, width: S, height: S)
    let radius = S * 0.2237
    let bg = NSBezierPath(roundedRect: full, xRadius: radius, yRadius: radius)
    bg.addClip()
    let top = NSColor(srgbRed: 0.29, green: 0.47, blue: 0.80, alpha: 1)     // blue
    let bottom = NSColor(srgbRed: 0.42, green: 0.28, blue: 0.68, alpha: 1)  // purple
    NSGradient(starting: top, ending: bottom)!.draw(in: full, angle: -90)

    NSColor.white.setFill()

    // Download arrow shaft (rounded vertical bar).
    let shaftW: CGFloat = 0.12
    let shaft = NSBezierPath(
        roundedRect: rectTD(x: 0.5 - shaftW / 2, topD: 0.22, w: shaftW, h: 0.22),
        xRadius: shaftW * S / 2, yRadius: shaftW * S / 2)
    shaft.fill()

    // Arrowhead (solid triangle pointing down).
    let head = NSBezierPath()
    head.move(to: pt(0.30, 0.42))
    head.line(to: pt(0.70, 0.42))
    head.line(to: pt(0.50, 0.66))
    head.close()
    head.fill()

    // Base bar (the "download destination" underline).
    let base = NSBezierPath(
        roundedRect: rectTD(x: 0.28, topD: 0.745, w: 0.44, h: 0.085),
        xRadius: 0.045 * S, yRadius: 0.045 * S)
    base.fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for px in sizes {
    let data = png(forSize: px)
    let path = "\(outDir)/icon_\(px).png"
    try! data.write(to: URL(fileURLWithPath: path))
    print("wrote \(path) (\(data.count) bytes)")
}
print("done")
