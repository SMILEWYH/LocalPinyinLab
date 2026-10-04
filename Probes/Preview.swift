import PinyinCore
import PinyinPresentation
import AppKit

@main
struct Preview {
    @MainActor static func main() throws {
        // 手写合成显示数据，只用于 UI 测量；不是苹果拼音或翻译输出。
        let rows = [
            CandidateRow(candidate: Candidate(text: "写的", consumedCount: 0), translation: .ready("written")),
            CandidateRow(candidate: Candidate(text: "xiedekaiyuanshurufa,zhichi", consumedCount: 0), translation: .ready("")),
            CandidateRow(candidate: Candidate(text: "携带", consumedCount: 0), translation: .ready("carry")),
            CandidateRow(candidate: Candidate(text: "协定", consumedCount: 0), translation: .ready("agreement · accord")),
            CandidateRow(candidate: Candidate(text: "写道", consumedCount: 0), translation: .ready("write")),
            CandidateRow(candidate: Candidate(text: "鞋带", consumedCount: 0), translation: .ready("shoelace")),
            CandidateRow(candidate: Candidate(text: "鞋底", consumedCount: 0), translation: .ready("sole")),
            CandidateRow(candidate: Candidate(text: "鞋垫", consumedCount: 0), translation: .ready("insole")),
            CandidateRow(candidate: Candidate(text: "亵渎", consumedCount: 0), translation: .ready("blaspheme"))
        ]
        let view = CandidateView(rows: rows, pinyin: "xie'd", highlighted: 0, footer: "1/22")
        let logical = view.preferredSize
        let output = CommandLine.arguments.dropFirst().first ?? "build/candidate-preview-synthetic.png"
        try view.writePNG(to: URL(fileURLWithPath: output))
        print("Synthetic UI preview: \(Int(ceil(logical.width * 2)))×\(Int(ceil(logical.height * 2))) pixels; \(output)")
    }
}
