import AppKit
import CoreText

guard CommandLine.arguments.count == 2 else {
    fatalError("Usage: menu-icon <output.tiff>")
}

// Use an alpha template: the system tints the badge for each menu appearance,
// while the cutout lettering reveals the background instead of fixed white ink.
// macOS also reuses this image inside its caret switcher capsule.
let size = NSSize(width: 22, height: 16)
let label = NSAttributedString(string: "中英", attributes: [
    .font: NSFont.systemFont(ofSize: 9, weight: .semibold),
    NSAttributedString.Key(kCTForegroundColorAttributeName as String): NSColor.black.cgColor
])
let line = CTLineCreateWithAttributedString(label)
let inkBounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
guard inkBounds.width <= size.width - 4, inkBounds.height <= size.height - 4 else {
    fatalError("The input source label does not fit inside the rounded badge")
}
let representations = [1, 2].map { scale -> NSBitmapImageRep in
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
        pixelsWide: 22 * scale, pixelsHigh: 16 * scale,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else {
        fatalError("Cannot allocate the menu icon bitmap")
    }
    // Set the logical size before the context snapshots its Retina scale.
    bitmap.size = size
    guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        fatalError("Cannot create the menu icon graphics context")
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    NSColor.clear.setFill()
    NSRect(origin: .zero, size: size).fill(using: .copy)
    NSColor.black.setFill()
    NSBezierPath(roundedRect: NSRect(origin: .zero, size: size), xRadius: 5, yRadius: 5).fill()
    let graphics = context.cgContext
    graphics.setBlendMode(.destinationOut)
    graphics.textMatrix = .identity
    graphics.textPosition = CGPoint(x: (size.width - inkBounds.width) / 2 - inkBounds.minX,
                                    y: (size.height - inkBounds.height) / 2 - inkBounds.minY)
    CTLineDraw(line, graphics)
    NSGraphicsContext.restoreGraphicsState()
    return bitmap
}
guard let data = NSBitmapImageRep.representationOfImageReps(in: representations, using: .tiff,
    properties: [.compressionMethod: NSBitmapImageRep.TIFFCompression.lzw.rawValue]) else {
    fatalError("Cannot encode the menu icon TIFF")
}
try data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]), options: .atomic)
print("Generated the 中英 cutout badge template (22×16 pt, 1× and 2×).")
