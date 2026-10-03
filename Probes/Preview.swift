import AppKit

@main
struct Preview {
    @MainActor static func main() throws {
        // 手写合成显示数据，只用于 UI 测量；不是苹果拼音或翻译输出。
        let rows = [
            Candidate(text: "写的", translation: "written"),
            Candidate(text: "xiedekaiyuanshurufa,zhichi", translation: ""),
            Candidate(text: "携带", translation: "carry"),
            Candidate(text: "协定", translation: "agreement · accord"),
            Candidate(text: "写道", translation: "write"),
            Candidate(text: "鞋带", translation: "shoelace"),
            Candidate(text: "鞋底", translation: "sole"),
            Candidate(text: "鞋垫", translation: "insole"),
            Candidate(text: "亵渎", translation: "blaspheme")
        ]
        let view = CandidateView(rows: rows, pinyin: "xie'd", highlighted: 0, footer: "1/22")
        let logical = view.preferredSize
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(ceil(logical.width * 2)), pixelsHigh: Int(ceil(logical.height * 2)), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else { fatalError("Bitmap creation failed") }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context.cgContext, flipped: true)
        context.cgContext.scaleBy(x: 2, y: 2)
        context.cgContext.translateBy(x: 0, y: logical.height)
        context.cgContext.scaleBy(x: 1, y: -1)
        view.draw(view.bounds)
        NSGraphicsContext.restoreGraphicsState()
        let output = CommandLine.arguments.dropFirst().first ?? "build/candidate-preview-synthetic.png"
        try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
        print("Synthetic UI preview: \(Int(ceil(logical.width * 2)))×\(Int(ceil(logical.height * 2))) pixels; \(output)")
    }
}
