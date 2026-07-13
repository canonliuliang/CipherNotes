import AppKit
import CoreGraphics
import Foundation
import ImageIO

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let assets = root.appendingPathComponent("Assets", isDirectory: true)
let iconBuild = URL(fileURLWithPath: "/tmp/ciphernotes-iconbuild", isDirectory: true)
let iconset = iconBuild.appendingPathComponent("AppIcon.iconset", isDirectory: true)

try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

struct Stop {
    let t: CGFloat
    let color: NSColor
}

func c(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(calibratedRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
}

func interp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat {
    a + (b - a) * t
}

func gradientColor(_ stops: [Stop], _ t: CGFloat) -> NSColor {
    let t = max(0, min(1, t))
    for index in 0..<(stops.count - 1) {
        let left = stops[index]
        let right = stops[index + 1]
        guard t >= left.t && t <= right.t else { continue }
        let local = (t - left.t) / (right.t - left.t)
        guard let lc = left.color.usingColorSpace(.deviceRGB),
              let rc = right.color.usingColorSpace(.deviceRGB) else { return left.color }
        return NSColor(
            calibratedRed: interp(lc.redComponent, rc.redComponent, local),
            green: interp(lc.greenComponent, rc.greenComponent, local),
            blue: interp(lc.blueComponent, rc.blueComponent, local),
            alpha: interp(lc.alphaComponent, rc.alphaComponent, local)
        )
    }
    return stops.last?.color ?? .black
}

func roundedRect(_ rect: CGRect, radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}

func fillLinear(_ rect: CGRect, stops: [Stop]) {
    let colors = stops.map(\.color)
    var locations = stops.map(\.t)
    NSGradient(colors: colors, atLocations: &locations, colorSpace: .deviceRGB)?
        .draw(in: rect, angle: -90)
}

func drawShadow(_ path: NSBezierPath, color: NSColor, blur: CGFloat, y: CGFloat) {
    NSGraphicsContext.saveGraphicsState()
    NSShadow().apply {
        $0.shadowColor = color
        $0.shadowBlurRadius = blur
        $0.shadowOffset = CGSize(width: 0, height: y)
    }
    NSColor.black.setFill()
    path.fill()
    NSGraphicsContext.restoreGraphicsState()
}

extension NSShadow {
    func apply(_ configure: (NSShadow) -> Void) {
        configure(self)
        set()
    }
}

func drawIcon(size: Int) -> CGImage {
    let scale = CGFloat(size) / 1024
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let context = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: size * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    let graphics = NSGraphicsContext(cgContext: context, flipped: false)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphics
    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)

    let canvas = CGRect(x: 0, y: 0, width: CGFloat(size), height: CGFloat(size))
    context.clear(canvas)

    func s(_ value: CGFloat) -> CGFloat { value * scale }
    func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
        CGRect(x: s(x), y: s(y), width: s(w), height: s(h))
    }

    // Keep the mark intentionally quiet: a single native SF Symbol on a macOS-style tile.
    let base = roundedRect(r(72, 72, 880, 880), radius: s(218))
    drawShadow(base, color: c(8, 30, 64, 0.22), blur: s(44), y: s(-18))
    context.saveGState()
    base.addClip()
    fillLinear(canvas, stops: [
        Stop(t: 0.00, color: c(32, 102, 214)),
        Stop(t: 0.52, color: c(44, 145, 226)),
        Stop(t: 1.00, color: c(46, 181, 174))
    ])
    context.restoreGState()

    c(255, 255, 255, 0.34).setStroke()
    base.lineWidth = s(2)
    base.stroke()

    let symbolSize = CGFloat(size) * 0.42
    let symbolConfiguration = NSImage.SymbolConfiguration(pointSize: symbolSize, weight: .semibold, scale: .large)
        .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
    guard let symbol = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: "CipherNotes")?.withSymbolConfiguration(symbolConfiguration) else {
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage()!
    }
    symbol.isTemplate = true
    NSColor.white.set()
    let symbolSizeValue = symbol.size
    let symbolRect = CGRect(
        x: (CGFloat(size) - symbolSizeValue.width) / 2,
        y: (CGFloat(size) - symbolSizeValue.height) / 2 + s(4),
        width: symbolSizeValue.width,
        height: symbolSizeValue.height
    )
    symbol.draw(in: symbolRect, from: .zero, operation: .sourceOver, fraction: 1)

    NSGraphicsContext.restoreGraphicsState()
    return context.makeImage()!
}

func savePNG(_ image: CGImage, to url: URL) throws {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
        throw NSError(domain: "IconGenerator", code: 1)
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw NSError(domain: "IconGenerator", code: 2)
    }
}

let slots: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for (name, size) in slots {
    try savePNG(drawIcon(size: size), to: iconset.appendingPathComponent(name))
}

try savePNG(drawIcon(size: 1024), to: assets.appendingPathComponent("AppIcon-1024.png"))
try savePNG(drawIcon(size: 256), to: root.appendingPathComponent("Website/icon.png"))
try savePNG(drawIcon(size: 256), to: root.appendingPathComponent("docs/icon.png"))
