import Foundation

@main
struct CompositionTests {
    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let engine = ApplePinyinEngine(workerRoot: root)
        var state = CompositionState()
        state.pending = "pingying"
        let initial = try engine.candidates(for: state.pending)
        let bottle = initial.first { $0.text == "瓶" }!
        precondition(initial.count > 9 && initial.contains { $0.text == "平" })
        precondition(state.choose(bottle))
        precondition(state.markedText == "瓶ying" && state.pending == "ying")
        let remaining = try engine.candidates(for: state.pending, context: state.selectedText)
        let win = remaining.first { $0.text == "赢" }!
        precondition(state.choose(win))
        precondition(state.selectedText == "瓶赢" && state.pending.isEmpty)
        print("PASS: pingying -> choose 瓶 -> ying -> choose 赢 -> 瓶赢; suffix retained")
        precondition(state.undoSelection() && state.markedText == "瓶ying")
        precondition(state.undoSelection() && state.markedText == "pingying")
        print("PASS: undo selected segments restores exact original pinyin")

        state = CompositionState()
        state.pending = "xian'zai'bei'jing'shi'jian'ji'dian'zhong"
        let start = try engine.candidates(for: state.pending)
        precondition(state.choose(start.first { $0.text == "现在" }!))
        precondition(state.pending == "bei'jing'shi'jian'ji'dian'zhong")
        let middle = try engine.candidates(for: state.pending, context: state.selectedText)
        precondition(state.choose(middle.first { $0.text == "北京时间" }!))
        precondition(state.pending == "ji'dian'zhong")
        let end = try engine.candidates(for: state.pending, context: state.selectedText)
        precondition(state.choose(end.first { $0.text == "几点钟" }!))
        precondition(state.selectedText == "现在北京时间几点钟" && state.pending.isEmpty)
        print("PASS: three segment sentence selection retains all text and separators")
        precondition(state.undoSelection())
        state.backspace()
        precondition(state.pending == "ji'dian'zhon")
        print("PASS: backspace edits unconverted suffix")

        let hello = try engine.candidates(for: "nihao")
        precondition(hello.contains { $0.text == "👋" })
        precondition(hello.first { $0.text == "你" }?.consumedCount == 2)
        precondition(ApplePinyinEngine.consumedCount(reading: "xi", in: "xi'an") == 3)
        precondition(ApplePinyinEngine.consumedCount(reading: "hao", in: "nihao") == nil)
        let before = state.markedText
        precondition(!state.choose(Candidate(text: "bad", translation: "", consumedCount: 999)))
        precondition(state.markedText == before)
        print("PASS: emoji retained, prefix coverage checked, malformed selection cannot lose text")
        let context = String(repeating: "中文👨‍👩‍👧‍👦e\u{301}", count: 50)
        let bounded = ApplePinyinEngine.boundedContext(context)
        precondition(bounded.utf16.count <= 128 && context.hasSuffix(bounded))
        precondition(!bounded.isEmpty && bounded.last == "e\u{301}")
        print("PASS: bounded context preserves Chinese, emoji and combining characters")

        // The transport accepts an ephemeral bounded context. Ranking parity is NOT asserted.
        let contextRows = try engine.candidates(for: "pingying", context: "是")
        print("OBSERVED: context=是, first=\(contextRows.first!.text); native ranking parity remains unverified")
    }
}
