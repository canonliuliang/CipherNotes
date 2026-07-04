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
    c(237, 246, 255).setFill()
    NSBezierPath(rect: canvas).fill()

    func s(_ value: CGFloat) -> CGFloat { value * scale }
    func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
        CGRect(x: s(x), y: s(y), width: s(w), height: s(h))
    }

    let base = roundedRect(r(72, 72, 880, 880), radius: s(218))
    drawShadow(base, color: c(8, 30, 64, 0.26), blur: s(54), y: s(-20))
    context.saveGState()
    base.addClip()
    fillLinear(canvas, stops: [
        Stop(t: 0.00, color: c(11, 93, 214)),
        Stop(t: 0.36, color: c(24, 139, 232)),
        Stop(t: 0.72, color: c(35, 196, 195)),
        Stop(t: 1.00, color: c(111, 226, 198))
    ])

    let glow = NSGradient(colors: [
        c(255, 255, 255, 0.45),
        c(255, 255, 255, 0.02)
    ])
    glow?.draw(in: roundedRect(r(112, 552, 560, 300), radius: s(150)), angle: -28)

    c(255, 255, 255, 0.11).setFill()
    roundedRect(r(540, 94, 330, 618), radius: s(96)).fill()
    c(3, 48, 119, 0.12).setFill()
    roundedRect(r(78, 82, 874, 248), radius: s(180)).fill()
    context.restoreGState()

    c(255, 255, 255, 0.34).setStroke()
    base.lineWidth = s(2)
    base.stroke()

    let backCard = roundedRect(r(286, 200, 440, 590), radius: s(82))
    drawShadow(backCard, color: c(5, 34, 85, 0.20), blur: s(42), y: s(-16))
    c(226, 247, 255, 0.30).setFill()
    backCard.fill()

    let frontCard = roundedRect(r(234, 238, 506, 548), radius: s(90))
    drawShadow(frontCard, color: c(2, 30, 78, 0.24), blur: s(42), y: s(-14))
    context.saveGState()
    frontCard.addClip()
    fillLinear(frontCard.bounds, stops: [
        Stop(t: 0.0, color: c(255, 255, 255, 0.96)),
        Stop(t: 1.0, color: c(226, 246, 255, 0.86))
    ])
    context.restoreGState()
    c(255, 255, 255, 0.72).setStroke()
    frontCard.lineWidth = s(2)
    frontCard.stroke()

    c(16, 103, 212, 0.26).setStroke()
    for y in [592, 522, 452] as [CGFloat] {
        let line = NSBezierPath()
        line.lineCapStyle = .round
        line.lineWidth = s(24)
        line.move(to: CGPoint(x: s(330), y: s(y)))
        line.line(to: CGPoint(x: s(644), y: s(y)))
        line.stroke()
    }

    let lockBody = roundedRect(r(372, 286, 286, 238), radius: s(64))
    drawShadow(lockBody, color: c(0, 48, 105, 0.20), blur: s(22), y: s(-7))
    context.saveGState()
    lockBody.addClip()
    fillLinear(lockBody.bounds, stops: [
        Stop(t: 0.0, color: c(0, 120, 212)),
        Stop(t: 1.0, color: c(20, 181, 186))
    ])
    context.restoreGState()

    let shackle = NSBezierPath()
    shackle.lineWidth = s(52)
    shackle.lineCapStyle = .round
    shackle.appendArc(
        withCenter: CGPoint(x: s(515), y: s(518)),
        radius: s(105),
        startAngle: 18,
        endAngle: 162,
        clockwise: false
    )
    c(7, 103, 194).setStroke()
    shackle.stroke()

    let key = NSBezierPath(ovalIn: r(488, 382, 54, 54))
    c(255, 255, 255, 0.92).setFill()
    key.fill()
    let keyStem = roundedRect(r(503, 334, 24, 72), radius: s(12))
    keyStem.fill()

    c(255, 255, 255, 0.42).setFill()
    roundedRect(r(254, 706, 310, 42), radius: s(21)).fill()

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
