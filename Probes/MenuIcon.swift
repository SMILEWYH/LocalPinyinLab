import AppKit
final class MenuIcon: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 14, weight: .medium), .foregroundColor: NSColor.black]
        let text = "拼" as NSString
        let size = text.size(withAttributes: attributes)
        text.draw(at: NSPoint(x: (22-size.width)/2, y: (16-size.height)/2), withAttributes: attributes)
    }
}
let view = MenuIcon(frame: NSRect(x: 0, y: 0, width: 22, height: 16))
try view.dataWithPDF(inside: view.bounds).write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
