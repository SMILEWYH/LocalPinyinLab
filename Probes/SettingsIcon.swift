import AppKit
import CoreText

/// The settings app has its own full-color Dock/Finder icon. The input method's
/// menu badge continues to be generated independently by MenuIcon.swift.
@main struct SettingsIcon {
    @MainActor static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            throw IconError(description: "Usage: settings-icon <output.icns>")
        }
        let output = URL(fileURLWithPath: CommandLine.arguments[1]).standardizedFileURL
        let iconset = FileManager.default.temporaryDirectory
            .appendingPathComponent("PinyinSettings-" + UUID().uuidString + ".iconset", isDirectory: true)
        try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: iconset) }
        for size in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let suffix = scale == 2 ? "@2x" : ""
                let name = "icon_\(size)x\(size)\(suffix).png"
                try render(pixels: size * scale).write(to: iconset.appendingPathComponent(name), options: .atomic)
            }
        }
        let converter = Process()
        converter.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
        converter.arguments = ["--convert", "icns", "--output", output.path, iconset.path]
        try converter.run()
        converter.waitUntilExit()
        guard converter.terminationStatus == 0 else {
            throw IconError(description: "iconutil failed with status \(converter.terminationStatus)")
        }
        print("Generated the standalone 拼音设置 icon: \(output.path)")
    }

    @MainActor private static func render(pixels: Int) throws -> Data {
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
            pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else {
            throw IconError(description: "Cannot allocate the settings icon bitmap")
        }
        bitmap.size = NSSize(width: 1024, height: 1024)
        guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            throw IconError(description: "Cannot create the settings icon graphics context")
        }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        NSColor.clear.setFill()
        NSRect(x: 0, y: 0, width: 1024, height: 1024).fill(using: .copy)

        let tile = NSBezierPath(roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896),
                                xRadius: 196, yRadius: 196)
        guard let gradient = NSGradient(starting: NSColor(srgbRed: 0.16, green: 0.50, blue: 0.97, alpha: 1),
                                        ending: NSColor(srgbRed: 0.05, green: 0.25, blue: 0.72, alpha: 1)) else {
            throw IconError(description: "Cannot create the settings icon gradient")
        }
        gradient.draw(in: tile, angle: -70)
        NSColor.white.withAlphaComponent(0.18).setStroke()
        tile.lineWidth = 3
        tile.stroke()

        let title = NSAttributedString(string: "中英", attributes: [
            .font: NSFont.systemFont(ofSize: 330, weight: .semibold),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): NSColor.white.cgColor
        ])
        let line = CTLineCreateWithAttributedString(title)
        let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        let graphics = context.cgContext
        graphics.textMatrix = .identity
        graphics.textPosition = CGPoint(x: 512 - bounds.midX, y: 605 - bounds.midY)
        CTLineDraw(line, graphics)

        // Two controls make the independent app recognizable as settings while
        // retaining the familiar 中英 lettering at Finder and Dock sizes.
        for (y, knobX) in [(300.0, 420.0), (208.0, 622.0)] {
            NSColor.white.withAlphaComponent(0.78).setFill()
            NSBezierPath(roundedRect: NSRect(x: 286, y: y - 10, width: 452, height: 20),
                         xRadius: 10, yRadius: 10).fill()
            NSColor(srgbRed: 0.09, green: 0.32, blue: 0.79, alpha: 1).setFill()
            NSBezierPath(ovalIn: NSRect(x: knobX - 34, y: y - 34, width: 68, height: 68)).fill()
            NSColor.white.setFill()
            NSBezierPath(ovalIn: NSRect(x: knobX - 23, y: y - 23, width: 46, height: 46)).fill()
        }
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw IconError(description: "Cannot encode the settings icon PNG")
        }
        return data
    }
}

private struct IconError: Error, CustomStringConvertible {
    let description: String
}
