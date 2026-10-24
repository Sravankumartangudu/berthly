// Renders the background for the Berthly.dmg installer window (640×400, plus @2x).
//   swift Icon/make_dmg_background.swift <out.tiff>
// build.sh --dist runs this; icons sit at (160, 190) and (480, 190) in Finder's top-left coordinates.
import AppKit

let w = 640.0, h = 400.0
func c(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor { NSColor(red: r, green: g, blue: b, alpha: a) }
let warm = [c(1.0, 0.72, 0.2), c(1.0, 0.5, 0.15)]

func render(scale: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(w) * scale, pixelsHigh: Int(h) * scale,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: w, height: h)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let cg = NSGraphicsContext.current!.cgContext
    cg.scaleBy(x: CGFloat(scale), y: CGFloat(scale))

    let bg = CGGradient(colorsSpace: nil, colors: [c(0.12, 0.15, 0.32).cgColor, c(0.02, 0.03, 0.08).cgColor] as CFArray,
                        locations: [0, 1])!
    cg.drawLinearGradient(bg, start: CGPoint(x: 0, y: h), end: .zero, options: [])

    var seed: UInt64 = 11
    func rnd() -> CGFloat {
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        return CGFloat(seed >> 33) / CGFloat(UInt32.max >> 1)
    }
    for _ in 0..<70 {
        let r = 0.6 + rnd() * 1.4
        cg.setFillColor(NSColor.white.withAlphaComponent(0.15 + rnd() * 0.45).cgColor)
        cg.fillEllipse(in: CGRect(x: rnd() * w, y: rnd() * h, width: r * 2, height: r * 2))
    }
    let amber = CGGradient(colorsSpace: nil, colors: warm.map(\.cgColor) as CFArray, locations: nil)!

    // A strip of track along the top: two rails and sleepers.
    cg.setStrokeColor(NSColor.white.withAlphaComponent(0.16).cgColor)
    cg.setLineWidth(2)
    for ry in [h - 40, h - 56] {
        cg.move(to: CGPoint(x: 0, y: ry)); cg.addLine(to: CGPoint(x: w, y: ry)); cg.strokePath()
    }
    cg.setLineWidth(4)
    for x in stride(from: 6.0, to: w, by: 22) {
        cg.move(to: CGPoint(x: x, y: h - 62)); cg.addLine(to: CGPoint(x: x, y: h - 34)); cg.strokePath()
    }

    // Amber dotted arc from the app to Applications, ending in an arrowhead.
    let y = h - 190
    cg.saveGState()
    cg.setShadow(offset: .zero, blur: 12, color: warm[1].cgColor)
    let arc = CGMutablePath()
    arc.move(to: CGPoint(x: 245, y: y))
    arc.addQuadCurve(to: CGPoint(x: 385, y: y), control: CGPoint(x: 315, y: y + 40))
    cg.beginTransparencyLayer(auxiliaryInfo: nil)
    cg.addPath(arc.copy(dashingWithPhase: 0, lengths: [2, 12]).copy(strokingWithWidth: 4, lineCap: .round, lineJoin: .round, miterLimit: 10))
    cg.move(to: CGPoint(x: 398, y: y - 4))
    cg.addLine(to: CGPoint(x: 376, y: y + 12))
    cg.addLine(to: CGPoint(x: 380, y: y - 12))
    cg.closePath()
    cg.clip()
    cg.drawLinearGradient(amber, start: CGPoint(x: 245, y: 0), end: CGPoint(x: 398, y: 0), options: [])
    cg.endTransparencyLayer()
    cg.restoreGState()

    // Finder draws icon labels in black (Light Mode) or white (Dark Mode); a mid-grey nameplate
    // under each label keeps both readable on the dark background.
    for x in [160.0, 480.0] {
        let plate = CGPath(roundedRect: CGRect(x: x - 75, y: h - 283, width: 150, height: 28),
                           cornerWidth: 14, cornerHeight: 14, transform: nil)
        cg.addPath(plate)
        cg.setFillColor(NSColor.white.withAlphaComponent(0.4).cgColor)
        cg.fillPath()
    }

    func text(_ s: String, _ size: CGFloat, _ weight: NSFont.Weight, _ color: NSColor, y: CGFloat, kern: CGFloat = 0) {
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        let str = NSAttributedString(string: s, attributes: [.font: NSFont.systemFont(ofSize: size, weight: weight),
                                                             .foregroundColor: color, .paragraphStyle: para, .kern: kern])
        str.draw(in: CGRect(x: 0, y: y, width: w, height: size * 1.5))
    }
    text("BERTHLY", 13, .heavy, c(1.0, 0.78, 0.4), y: h - 100, kern: 3)
    text("Drag Berthly into Applications to install", 17, .semibold, .white, y: 80)
    text("First launch blocked? System Settings → Privacy & Security → Open Anyway", 11, .regular,
         c(1.0, 0.82, 0.55, 0.85), y: 44)

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "background.tiff"
// A multi-representation TIFF lets Finder pick the sharp 2x image on Retina screens.
let data = NSBitmapImageRep.tiffRepresentationOfImageReps(in: [render(scale: 1), render(scale: 2)], using: .lzw, factor: 0)!
try! data.write(to: URL(fileURLWithPath: out))
print("✓ wrote \(out)")
