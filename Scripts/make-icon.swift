import AppKit
import CoreGraphics

// Draws the ShiftDrop icon: warm gradient squircle with a cream 6-segment ring and an orange highlighted wedge.
let size = 1024.0
let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
let inset = 100.0
let body = CGRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
let squircle = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: CGColor(gray: 0, alpha: 0.35))
ctx.addPath(squircle); ctx.setFillColor(CGColor(red: 0.95, green: 0.45, blue: 0.2, alpha: 1)); ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(squircle); ctx.clip()
let colors = [CGColor(red: 1.0, green: 0.72, blue: 0.3, alpha: 1), CGColor(red: 0.96, green: 0.4, blue: 0.22, alpha: 1), CGColor(red: 0.62, green: 0.4, blue: 0.85, alpha: 1)] as CFArray
let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: [0, 0.55, 1])!
ctx.drawLinearGradient(gradient, start: CGPoint(x: body.minX, y: body.maxY), end: CGPoint(x: body.maxX, y: body.minY), options: [])
ctx.restoreGState()

let c = CGPoint(x: size / 2, y: size / 2)
// Glass disc
ctx.addEllipse(in: CGRect(x: c.x - 330, y: c.y - 330, width: 660, height: 660))
ctx.setFillColor(CGColor(red: 1, green: 0.95, blue: 0.9, alpha: 0.35)); ctx.fillPath()

func wedge(_ index: Int, _ count: Int, inner: Double, outer: Double, gap: Double, corner: Double) -> CGPath {
    let slice = 2 * Double.pi / Double(count)
    let mid = slice * Double(index)
    let start = mid - slice / 2, end = mid + slice / 2
    let rIn = inner + corner, rOut = outer - corner, d = gap / 2 + corner
    func inset(_ r: Double) -> Double { asin(min(1, d / r)) }
    func pt(_ a: Double, _ r: Double) -> CGPoint { CGPoint(x: c.x + r * sin(a), y: c.y + r * cos(a)) }
    let p = CGMutablePath()
    let s1 = start + inset(rOut), e1 = end - inset(rOut), s2 = start + inset(rIn), e2 = end - inset(rIn)
    p.move(to: pt(s1, rOut))
    for k in 1...40 { p.addLine(to: pt(s1 + (e1 - s1) * Double(k) / 40, rOut)) }
    p.addLine(to: pt(e2, rIn))
    for k in 1...40 { p.addLine(to: pt(e2 + (s2 - e2) * Double(k) / 40, rIn)) }
    p.closeSubpath()
    return p
}
for i in 0..<6 {
    let path = wedge(i, 6, inner: 140, outer: 305, gap: 22, corner: 26)
    let color = i == 1 ? CGColor(red: 0.85, green: 0.24, blue: 0.08, alpha: 1) : CGColor(red: 1, green: 0.9, blue: 0.8, alpha: 1)
    ctx.addPath(path); ctx.setFillColor(color); ctx.fillPath()
    ctx.addPath(path); ctx.setStrokeColor(color); ctx.setLineWidth(52); ctx.setLineJoin(.round); ctx.strokePath()
}
// Center pill
let pill = CGRect(x: c.x - 95, y: c.y - 42, width: 190, height: 84)
ctx.addPath(CGPath(roundedRect: pill, cornerWidth: 42, cornerHeight: 42, transform: nil))
ctx.setFillColor(CGColor(red: 1, green: 0.93, blue: 0.86, alpha: 1)); ctx.fillPath()
// Shift arrow glyph in the pill
NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 64, weight: .heavy), .foregroundColor: NSColor(red: 0.85, green: 0.3, blue: 0.1, alpha: 1)]
let glyph = NSAttributedString(string: "⇧", attributes: attrs)
let gs = glyph.size()
glyph.draw(at: NSPoint(x: c.x - gs.width / 2, y: c.y - gs.height / 2 + 2))

let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
