// Rasterizes the Tokenly brand tile (design/tokenly-icon.svg) into every PNG the AppIcon set needs.
// Usage: swift build/make-tokenly-icon.swift [<output-appiconset-dir>] [<source-svg>]   (run from the repo root)
//
// The sizes are not hard-coded: they are read out of the set's own Contents.json, so the PNGs on
// disk can never drift from what the asset catalog declares. Superseded build/make-icon.swift,
// which *drew* the old Pulse ring in Core Graphics instead of rendering a designed source file.
import AppKit

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Pulse/Pulse/Assets.xcassets/AppIcon.appiconset"
let svgPath = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "design/tokenly-icon.svg"

guard let source = NSImage(contentsOf: URL(fileURLWithPath: svgPath)) else {
    fatalError("could not load \(svgPath) — NSImage reads SVG on macOS 11+; check the path and that the file is valid SVG")
}

/// One PNG at exactly `px`×`px` device pixels: the rep is created at that pixel count and given a
/// matching point size, so the vector source draws 1:1 into it and no scale factor is inferred.
func render(_ px: Int) -> Data {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { fatalError("failed to allocate a \(px)px bitmap") }
    rep.size = NSSize(width: px, height: px)

    guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { fatalError("failed to open a context at \(px)px") }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    ctx.imageInterpolation = .high
    let rect = NSRect(x: 0, y: 0, width: px, height: px)
    // `.copy` over a fresh rep: the icon owns every pixel, including the transparent ones outside
    // the tile's rounded corners.
    NSColor.clear.setFill()
    rect.fill(using: .copy)
    source.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
    ctx.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

    guard let data = rep.representation(using: .png, properties: [:]) else {
        fatalError("failed to encode PNG at \(px)px")
    }
    return data
}

let contentsURL = URL(fileURLWithPath: "\(outDir)/Contents.json")
guard let raw = try? Data(contentsOf: contentsURL),
      let json = try? JSONSerialization.jsonObject(with: raw) as? [String: Any],
      let images = json["images"] as? [[String: String]], !images.isEmpty else {
    fatalError("could not read the image list from \(contentsURL.path)")
}

var written = 0
for entry in images {
    guard let filename = entry["filename"],
          let size = entry["size"], let points = Int(size.split(separator: "x").first ?? ""),
          let scale = entry["scale"], let factor = Int(scale.dropLast()) else {
        fatalError("unexpected entry in Contents.json: \(entry)")
    }
    let px = points * factor
    try render(px).write(to: URL(fileURLWithPath: "\(outDir)/\(filename)"))
    print("  \(filename) — \(px)×\(px)")
    written += 1
}
print("wrote \(written) icons to \(outDir) from \(svgPath)")
