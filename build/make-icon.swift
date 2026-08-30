// Renders the Pulse app icon at every size the AppIcon set needs.
// Usage: swift build/make-icon.swift <output-appiconset-dir>
import AppKit

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Pulse/Pulse/Assets.xcassets/AppIcon.appiconset"
try FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let image = NSImage(size: NSSize(width: s, height: s), flipped: false) { rect in
        guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
        ctx.setFillColor(NSColor(red: 0x0A / 255, green: 0x0A / 255, blue: 0x0A / 255, alpha: 1).cgColor)
        let square = CGRect(x: 0, y: 0, width: s, height: s).insetBy(dx: s * 0.05, dy: s * 0.05)
        ctx.addPath(CGPath(roundedRect: square, cornerWidth: s * 0.22, cornerHeight: s * 0.22, transform: nil))
        ctx.fillPath()

        let center = CGPoint(x: s / 2, y: s / 2)
        let r = s * 0.30, stroke = s * 0.055
        ctx.setLineWidth(stroke)
        ctx.setLineCap(.round)
        ctx.setStrokeColor(NSColor(red: 0x2C / 255, green: 0x2C / 255, blue: 0x2E / 255, alpha: 1).cgColor)
        ctx.addArc(center: center, radius: r, startAngle: 0, endAngle: 2 * .pi, clockwise: false)
        ctx.strokePath()
        ctx.setStrokeColor(NSColor(red: 0xFF / 255, green: 0x4F / 255, blue: 0x1F / 255, alpha: 1).cgColor)
        let start = CGFloat.pi / 2, sweep = -2 * CGFloat.pi * 0.73     // clockwise from 12 o'clock
        ctx.addArc(center: center, radius: r, startAngle: start, endAngle: start + sweep, clockwise: true)
        ctx.strokePath()
        ctx.setFillColor(NSColor(red: 0x1C / 255, green: 0x1C / 255, blue: 0x1E / 255, alpha: 1).cgColor)
        ctx.addArc(center: center, radius: s * 0.19, startAngle: 0, endAngle: 2 * .pi, clockwise: false)
        ctx.fillPath()
        return true
    }

    guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: [.ctm: AffineTransform(scale: 1)]) else {
        fatalError("failed to rasterize icon at \(px)px")
    }
    let rep = NSBitmapImageRep(cgImage: cgImage)
    rep.size = NSSize(width: px, height: px)
    return rep.representation(using: .png, properties: [:])!
}

let sizes: [(name: String, points: Int, scale: Int)] = [
    ("icon_16x16", 16, 1), ("icon_16x16@2x", 16, 2), ("icon_32x32", 32, 1), ("icon_32x32@2x", 32, 2),
    ("icon_128x128", 128, 1), ("icon_128x128@2x", 128, 2), ("icon_256x256", 256, 1), ("icon_256x256@2x", 256, 2),
    ("icon_512x512", 512, 1), ("icon_512x512@2x", 512, 2),
]
var images: [[String: String]] = []
for entry in sizes {
    let px = entry.points * entry.scale
    try render(px).write(to: URL(fileURLWithPath: "\(outDir)/\(entry.name).png"))
    images.append(["idiom": "mac", "size": "\(entry.points)x\(entry.points)", "scale": "\(entry.scale)x", "filename": "\(entry.name).png"])
}
let contents: [String: Any] = ["images": images, "info": ["version": 1, "author": "xcode"]]
let json = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try json.write(to: URL(fileURLWithPath: "\(outDir)/Contents.json"))
print("wrote \(sizes.count) icons to \(outDir)")
