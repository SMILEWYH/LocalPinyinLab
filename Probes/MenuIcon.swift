import AppKit

guard CommandLine.arguments.count == 2 else {
    fatalError("Usage: menu-icon <output.tiff>")
}

// macOS reuses this template in the menu and inside its caret switcher capsule.
// Draw only the label; a background here would become a second badge inside it.
let size = NSSize(width: 22, height: 16)
let label = "中英" as NSString
let attributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 10.5, weight: .semibold),
    .foregroundColor: NSColor.black
]
let labelSize = label.size(withAttributes: attributes)
guard labelSize.width <= size.width, labelSize.height <= size.height else {
    fatalError("The input source label does not fit the menu icon")
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
    label.draw(at: NSPoint(x: (size.width - labelSize.width) / 2,
                          y: (size.height - labelSize.height) / 2), withAttributes: attributes)
    NSGraphicsContext.restoreGraphicsState()
    return bitmap
}
guard let data = NSBitmapImageRep.representationOfImageReps(in: representations, using: .tiff,
    properties: [.compressionMethod: NSBitmapImageRep.TIFFCompression.lzw.rawValue]) else {
    fatalError("Cannot encode the menu icon TIFF")
}
try data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]), options: .atomic)
print("Generated the 中英 input source template (22×16 pt, 1× and 2×).")
