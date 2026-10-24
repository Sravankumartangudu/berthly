// Renders the app icon: the front of a train inside an amber countdown ring, on a night-navy tile.
//   swift Icon/make_icon.swift   → writes Icon/AppIcon.icns and Icon/AppIcon.png
import AppKit

let size = 1024.0

func c(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor { NSColor(red: r, green: g, blue: b, alpha: a).cgColor }
let amber = c(1.0, 0.72, 0.2), saffron = c(1.0, 0.5, 0.15), white = c(1, 1, 1), green = c(0.25, 0.88, 0.5)

func renderFull(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let cg = NSGraphicsContext.current!.cgContext
    cg.scaleBy(x: CGFloat(px) / size, y: CGFloat(px) / size)
    draw(cg)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

// Every size is shrunk from one full-size drawing. Shadow and glow blur are measured in device pixels, so
// drawing straight at 16–64 px would spill them over the whole image as a faint grey square.
enum Full {
    static let png = renderFull(1024)
    static let image = NSBitmapImageRep(data: png)!.cgImage!
}

func render(_ px: Int) -> Data {
    if px == Full.image.width { return Full.png }
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
    ctx.interpolationQuality = .high
    ctx.draw(Full.image, in: CGRect(x: 0, y: 0, width: px, height: px))
    return rep.representation(using: .png, properties: [:])!
}

func gradient(_ colors: [CGColor]) -> CGGradient {
    CGGradient(colorsSpace: nil, colors: colors as CFArray, locations: nil)!
}

func rounded(_ r: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func draw(_ cg: CGContext) {
    // Body follows Apple's icon grid: 824pt squircle centred in a 1024 canvas.
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let squircle = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)

    cg.saveGState()
    cg.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: c(0, 0, 0, 0.5))
    cg.addPath(squircle)
    cg.setFillColor(c(0, 0, 0))
    cg.fillPath()
    cg.restoreGState()

    cg.saveGState()
    cg.addPath(squircle)
    cg.clip()
    cg.drawLinearGradient(gradient([c(0.12, 0.15, 0.32), c(0.05, 0.07, 0.17), c(0.02, 0.03, 0.08)]),
                          start: CGPoint(x: 0, y: 924), end: CGPoint(x: 0, y: 100), options: [])
    cg.drawRadialGradient(gradient([c(1.0, 0.6, 0.2, 0.22), c(1.0, 0.6, 0.2, 0)]),
                          startCenter: CGPoint(x: 512, y: 540), startRadius: 0,
                          endCenter: CGPoint(x: 512, y: 540), endRadius: 430, options: [])

    // Rails running towards the viewer under the train.
    cg.setStrokeColor(c(1, 1, 1, 0.22))
    cg.setLineWidth(10)
    cg.setLineCap(.round)
    for (top, bottom) in [(462.0, 300.0), (562.0, 724.0)] {
        cg.move(to: CGPoint(x: top, y: 300)); cg.addLine(to: CGPoint(x: bottom, y: 110)); cg.strokePath()
    }
    for (i, y) in [280.0, 220.0, 150.0].enumerated() {
        let half = 70.0 + Double(i) * 50
        cg.setLineWidth(8 + CGFloat(i) * 3)
        cg.move(to: CGPoint(x: 512 - half, y: y)); cg.addLine(to: CGPoint(x: 512 + half, y: y)); cg.strokePath()
    }
    cg.restoreGState()

    // Countdown ring: a faint track, then a glowing amber arc with a bright tip.
    let centre = CGPoint(x: 512, y: 560)
    let radius = 300.0
    cg.setLineWidth(38)
    cg.setStrokeColor(c(1, 1, 1, 0.09))
    cg.addArc(center: centre, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
    cg.strokePath()

    let start = CGFloat.pi / 2, end = CGFloat.pi / 2 - .pi * 1.55
    cg.saveGState()
    cg.setShadow(offset: .zero, blur: 40, color: saffron)
    let arc = CGMutablePath()
    arc.addArc(center: centre, radius: radius, startAngle: start, endAngle: end, clockwise: true)
    let band = arc.copy(strokingWithWidth: 38, lineCap: .round, lineJoin: .round, miterLimit: 10)
    cg.beginTransparencyLayer(auxiliaryInfo: nil)
    cg.addPath(band)
    cg.clip()
    cg.drawLinearGradient(gradient([amber, saffron]), start: CGPoint(x: 212, y: 860), end: CGPoint(x: 812, y: 260), options: [])
    cg.endTransparencyLayer()
    cg.restoreGState()
    let tip = CGPoint(x: centre.x + radius * cos(end), y: centre.y + radius * sin(end))
    cg.saveGState()
    cg.setShadow(offset: .zero, blur: 30, color: amber)
    cg.setFillColor(c(1, 0.95, 0.8))
    cg.fillEllipse(in: CGRect(x: tip.x - 26, y: tip.y - 26, width: 52, height: 52))
    cg.restoreGState()

    // The train, seen head-on.
    let shell = CGRect(x: 512 - 165, y: 340, width: 330, height: 420)
    cg.saveGState()
    cg.setShadow(offset: CGSize(width: 0, height: -10), blur: 30, color: c(0, 0, 0, 0.55))
    cg.addPath(rounded(shell, 110))
    cg.setFillColor(white)
    cg.fillPath()
    cg.restoreGState()

    // Saffron band across the nose, clipped to the body.
    cg.saveGState()
    cg.addPath(rounded(shell, 110))
    cg.clip()
    cg.setFillColor(saffron)
    cg.fill(CGRect(x: shell.minX, y: 470, width: shell.width, height: 46))
    cg.restoreGState()

    // Windscreen.
    let screen = CGRect(x: shell.minX + 48, y: 572, width: shell.width - 96, height: 130)
    cg.addPath(rounded(screen, 46))
    cg.setFillColor(c(0.08, 0.11, 0.25))
    cg.fillPath()
    cg.saveGState()
    cg.addPath(rounded(screen, 46))
    cg.clip()
    cg.setFillColor(c(1, 1, 1, 0.16))
    let shine = CGMutablePath()
    shine.move(to: CGPoint(x: screen.minX + 30, y: screen.maxY))
    shine.addLine(to: CGPoint(x: screen.minX + 110, y: screen.maxY))
    shine.addLine(to: CGPoint(x: screen.minX + 40, y: screen.minY))
    shine.addLine(to: CGPoint(x: screen.minX - 40, y: screen.minY))
    shine.closeSubpath()
    cg.addPath(shine)
    cg.fillPath()
    cg.restoreGState()

    // Headlights with a warm glow, and a green "go" lamp on top.
    for x in [shell.minX + 78, shell.maxX - 78] {
        cg.saveGState()
        cg.setShadow(offset: .zero, blur: 34, color: amber)
        cg.setFillColor(c(1, 0.9, 0.55))
        cg.fillEllipse(in: CGRect(x: x - 30, y: 390, width: 60, height: 60))
        cg.restoreGState()
    }
    cg.saveGState()
    cg.setShadow(offset: .zero, blur: 26, color: green)
    cg.setFillColor(green)
    cg.fillEllipse(in: CGRect(x: 512 - 22, y: 718, width: 44, height: 22))
    cg.restoreGState()

    // Buffer beam.
    cg.addPath(rounded(CGRect(x: shell.minX + 20, y: 318, width: shell.width - 40, height: 36), 18))
    cg.setFillColor(c(0.75, 0.78, 0.86))
    cg.fillPath()
}

let iconset = URL(fileURLWithPath: "Icon/AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128),
                   ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    try! render(px).write(to: iconset.appendingPathComponent("icon_\(name).png"))
}
try! Full.png.write(to: URL(fileURLWithPath: "Icon/AppIcon.png"))
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", "Icon/AppIcon.icns"]
try! p.run()
p.waitUntilExit()
print("✓ Icon/AppIcon.icns")
