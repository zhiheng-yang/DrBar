#!/usr/bin/env swift
// Draws the app icon and writes every size the asset catalog needs.
//
// Usage: swift scripts/make-icon.swift App/Resources/Assets.xcassets/AppIcon.appiconset
//
// The icon is drawn from paths: SF Symbols may not be used in app icons.
import AppKit

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("Usage: swift scripts/make-icon.swift <AppIcon.appiconset folder>\n".utf8))
    exit(64)
}
let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

/// Draws on a 1024 × 1024 canvas with the origin at the top left.
func draw(in context: CGContext) {
    context.translateBy(x: 0, y: 1024)
    context.scaleBy(x: 1, y: -1)

    // Body: the macOS icon grid's 824 pt rounded square, with a soft shadow.
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let bodyPath = CGPath(roundedRect: body, cornerWidth: 186, cornerHeight: 186, transform: nil)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, 0.28))
    context.addPath(bodyPath)
    context.setFillColor(color(0x3F46C8))
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(bodyPath)
    context.clip()
    let gradient = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
        colors: [color(0x6470F2), color(0x2F2B8F)] as CFArray, locations: [0, 1])!
    context.drawLinearGradient(gradient, start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 924), options: [])

    // Mortarboard: the cap under the board, then the board, then the tassel.
    let cap = CGMutablePath()
    cap.move(to: CGPoint(x: 372, y: 392))
    cap.addLine(to: CGPoint(x: 652, y: 392))
    cap.addLine(to: CGPoint(x: 652, y: 486))
    cap.addQuadCurve(to: CGPoint(x: 372, y: 486), control: CGPoint(x: 512, y: 556))
    cap.closeSubpath()
    context.addPath(cap)
    context.setFillColor(color(0xFFFFFF, 0.82))
    context.fillPath()

    let board = CGMutablePath()
    board.move(to: CGPoint(x: 512, y: 214))
    board.addLine(to: CGPoint(x: 790, y: 326))
    board.addLine(to: CGPoint(x: 512, y: 438))
    board.addLine(to: CGPoint(x: 234, y: 326))
    board.closeSubpath()
    context.addPath(board)
    context.setFillColor(color(0xFFFFFF))
    context.fillPath()

    context.setStrokeColor(color(0xFFC94A))
    context.setLineWidth(14)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.move(to: CGPoint(x: 512, y: 326))
    context.addLine(to: CGPoint(x: 718, y: 372))
    context.addLine(to: CGPoint(x: 718, y: 470))
    context.strokePath()
    context.setFillColor(color(0xFFC94A))
    context.addPath(
        CGPath(
            roundedRect: CGRect(x: 700, y: 462, width: 36, height: 54), cornerWidth: 12, cornerHeight: 12,
            transform: nil))
    context.fillPath()

    // Timeline: three bars like a staircase of deadlines; the nearest one is urgent.
    let bars: [(width: CGFloat, fill: CGColor)] = [
        (170, color(0xFF9F0A)),
        (330, color(0xFFFFFF, 0.92)),
        (500, color(0xFFFFFF, 0.6)),
    ]
    for (index, bar) in bars.enumerated() {
        let rect = CGRect(x: 262, y: 612 + CGFloat(index) * 78, width: bar.width, height: 44)
        // The app's bar shape: corners of 40 % of the height, never a capsule.
        context.addPath(CGPath(roundedRect: rect, cornerWidth: 18, cornerHeight: 18, transform: nil))
        context.setFillColor(bar.fill)
        context.fillPath()
    }
    // The "today" line all bars start from.
    context.setStrokeColor(color(0xFFFFFF, 0.95))
    context.setLineWidth(10)
    context.move(to: CGPoint(x: 244, y: 596))
    context.addLine(to: CGPoint(x: 244, y: 824))
    context.strokePath()
    context.restoreGState()
}

func png(size: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let graphics = NSGraphicsContext(bitmapImageRep: rep)!
    let context = graphics.cgContext
    context.interpolationQuality = .high
    context.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    draw(in: context)
    graphics.flushGraphics()
    return rep.representation(using: .png, properties: [:])!
}

let sizes: [(name: String, pixels: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for (name, pixels) in sizes {
    try png(size: pixels).write(to: output.appending(path: "\(name).png"))
}
print("Wrote \(sizes.count) icons to \(output.path)")
