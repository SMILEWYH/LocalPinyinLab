import TestSupport
import PinyinCore

@main
struct CoreTests {
    static func main() {
        let suite = CoreTests()
        suite.testInputAlphabetAndLimit()
        suite.testAppendIsAtomicAndCountsSelectedRawInput()
        suite.testSegmentSelectionAndUndoPreserveSeparatorsAndSuffix()
        suite.testInvalidSelectionDoesNotMutateComposition()
        suite.testBackspaceEditsPendingThenRestoresSelectedSegment()
        suite.testPrefixMappingIncludesOriginalSeparators()
        suite.testContextIsAWholeCharacterSuffixWithinUTF16Limit()
        suite.testEmptyCandidateListHasNoSelectionOrVisibleRows()
        suite.testCandidateNavigationKeepsLastPageInBounds()
        suite.testReplaceAndClearResetSelection()
        suite.testTranslationUsesExpectedSourceBeforeApplying()
        suite.testTranslationStateControlsDisplayAndSpeechTogether()
        suite.testRawPinyinAndEmojiCannotBeSpokenEvenIfMarkedReady()
        print("PASS: 13 PinyinCore invariant tests")
    }

    func testInputAlphabetAndLimit() {
        for valid in ["a", "ni'hao", "'", String(repeating: "x", count: 128)] {
            XCTAssertTrue(PinyinRules.isValid(valid), valid)
        }
        for invalid in ["", "Nihao", "ni hao", "ni\nhao", "ni9", "你好", "ｎｉ", "e\u{301}", String(repeating: "x", count: 129)] {
            XCTAssertFalse(PinyinRules.isValid(invalid), invalid)
        }
    }

    func testAppendIsAtomicAndCountsSelectedRawInput() {
        var state = CompositionState()
        XCTAssertTrue(state.append(String(repeating: "n", count: 127)))
        XCTAssertTrue(state.choose(Candidate(text: "你", consumedCount: 100)))
        XCTAssertEqual(state.inputCount, 127)
        let before = state
        XCTAssertFalse(state.append("aa"))
        XCTAssertFalse(state.append("A"))
        XCTAssertFalse(state.append(""))
        XCTAssertEqual(state, before)
        XCTAssertTrue(state.append("a"))
        XCTAssertEqual(state.inputCount, 128)
        XCTAssertFalse(state.append("b"))
        XCTAssertTrue(state.undoSelection())
        XCTAssertEqual(state.pending, String(repeating: "n", count: 127) + "a")
        XCTAssertEqual(state.inputCount, 128)
    }

    func testSegmentSelectionAndUndoPreserveSeparatorsAndSuffix() {
        let original = "xian'zai'bei'jing'shi'jian'ji'dian'zhong"
        var state = CompositionState()
        XCTAssertTrue(state.append(original))
        for (text, reading) in [("现在", "xianzai"), ("北京时间", "beijingshijian"), ("几点钟", "jidianzhong")] {
            let count = PinyinRules.consumedCount(reading: reading, in: state.pending)!
            XCTAssertTrue(state.choose(Candidate(text: text, consumedCount: count)))
            XCTAssertEqual(state.inputCount, original.count)
        }
        XCTAssertEqual(state.selectedText, "现在北京时间几点钟")
        XCTAssertEqual(state.pending, "")
        XCTAssertFalse(state.isEmpty)
        XCTAssertEqual(state.segments.map(\.pinyin).joined(), original)
        XCTAssertTrue(state.undoSelection())
        XCTAssertEqual(state.markedText, "现在北京时间ji'dian'zhong")
        XCTAssertTrue(state.undoSelection())
        XCTAssertTrue(state.undoSelection())
        XCTAssertEqual(state.pending, original)
        XCTAssertTrue(state.segments.isEmpty)
        XCTAssertFalse(state.undoSelection())
    }

    func testInvalidSelectionDoesNotMutateComposition() {
        var state = CompositionState()
        state.append("ni'hao")
        let before = state
        for candidate in [
            Candidate(text: "", consumedCount: 1), Candidate(text: " \n", consumedCount: 1),
            Candidate(text: "你", consumedCount: 0), Candidate(text: "你", consumedCount: -1),
            Candidate(text: "你", consumedCount: 7), Candidate(text: "你", consumedCount: Int.max)
        ] {
            XCTAssertFalse(state.choose(candidate))
            XCTAssertEqual(state, before)
        }
        var empty = CompositionState()
        XCTAssertFalse(empty.choose(Candidate(text: "你", consumedCount: 1)))
    }

    func testBackspaceEditsPendingThenRestoresSelectedSegment() {
        var state = CompositionState()
        state.append("ni'hao")
        state.choose(Candidate(text: "你", consumedCount: 3))
        state.backspace()
        XCTAssertEqual(state.markedText, "你ha")
        state.backspace()
        state.backspace()
        XCTAssertEqual(state.markedText, "你")
        state.backspace()
        XCTAssertEqual(state.pending, "ni'")
        XCTAssertEqual(state.selectedText, "")
        state.backspace()
        state.backspace()
        state.backspace()
        state.backspace()
        XCTAssertTrue(state.isEmpty)
        XCTAssertEqual(state.inputCount, 0)
    }

    func testPrefixMappingIncludesOriginalSeparators() {
        XCTAssertEqual(PinyinRules.consumedCount(reading: "xi", in: "xi'an"), 3)
        XCTAssertEqual(PinyinRules.consumedCount(reading: "xi'an", in: "xi'an"), 5)
        XCTAssertEqual(PinyinRules.consumedCount(reading: "'xi'", in: "'xi'''an"), 6)
        XCTAssertEqual(PinyinRules.consumedCount(reading: "ni", in: "nihao"), 2)
        XCTAssertNil(PinyinRules.consumedCount(reading: "hao", in: "nihao"))
        XCTAssertNil(PinyinRules.consumedCount(reading: "nihao", in: "ni"))
        XCTAssertNil(PinyinRules.consumedCount(reading: "'''", in: "nihao"))
        XCTAssertNil(PinyinRules.consumedCount(reading: "", in: "nihao"))
        XCTAssertNil(PinyinRules.consumedCount(reading: "ni", in: "ni 好"))
    }

    func testContextIsAWholeCharacterSuffixWithinUTF16Limit() {
        let source = String(repeating: "中文👨‍👩‍👧‍👦e\u{301}", count: 50)
        let bounded = PinyinRules.boundedContext(source)
        XCTAssertTrue(bounded.utf16.count <= PinyinRules.maxContextLength)
        XCTAssertFalse(bounded.isEmpty)
        XCTAssertTrue(source.hasSuffix(bounded))
        XCTAssertEqual(bounded.last, "e\u{301}")
        XCTAssertEqual(PinyinRules.boundedContext("你好👋"), "你好👋")
        XCTAssertEqual(PinyinRules.boundedContext(""), "")
        XCTAssertEqual(PinyinRules.boundedContext(String(repeating: "a", count: 129)), String(repeating: "a", count: 128))
        // One oversized grapheme cannot be split or skipped in a contiguous suffix.
        XCTAssertEqual(PinyinRules.boundedContext("a" + "e" + String(repeating: "\u{301}", count: 128)), "")
    }

    func testEmptyCandidateListHasNoSelectionOrVisibleRows() {
        var list = CandidateList()
        list.move(by: Int.max)
        list.movePage(by: Int.min)
        XCTAssertNil(list.selectedIndex)
        XCTAssertNil(list.selectedRow)
        XCTAssertEqual(list.page, 0)
        XCTAssertEqual(list.highlighted, 0)
        XCTAssertEqual(list.totalPages, 0)
        XCTAssertTrue(list.visibleRows.isEmpty)
        XCTAssertTrue(list.visibleIndices.isEmpty)
        XCTAssertNil(list.indexOnPage(0))
    }

    func testCandidateNavigationKeepsLastPageInBounds() {
        var list = CandidateList(rows: makeRows(20))
        XCTAssertEqual(list.totalPages, 3)
        XCTAssertEqual(list.visibleIndices, Array(0..<9))
        list.move(by: 9)
        XCTAssertEqual(list.page, 1)
        XCTAssertEqual(list.highlighted, 0)
        list.move(by: Int.max)
        XCTAssertEqual(list.selectedIndex, 19)
        XCTAssertEqual(list.page, 2)
        XCTAssertEqual(list.highlighted, 1)
        XCTAssertEqual(list.visibleIndices, [18, 19])
        XCTAssertEqual(list.visibleRows.map(\.text), ["候选18", "候选19"])
        XCTAssertEqual(list.selectedRow?.text, "候选19")
        XCTAssertEqual(list.indexOnPage(1), 19)
        for invalid in [-1, 2, 8, 9, Int.max, Int.min] { XCTAssertNil(list.indexOnPage(invalid)) }
        list.movePage(by: Int.max)
        XCTAssertEqual(list.selectedIndex, 18)
        list.movePage(by: -1)
        XCTAssertEqual(list.selectedIndex, 9)
        list.movePage(by: Int.min)
        XCTAssertEqual(list.selectedIndex, 0)
        list.move(by: Int.min)
        XCTAssertEqual(list.selectedIndex, 0)
    }

    func testReplaceAndClearResetSelection() {
        var list = CandidateList(rows: makeRows(19))
        list.move(by: 18)
        list.replace(makeRows(9))
        XCTAssertEqual(list.totalPages, 1)
        XCTAssertEqual(list.selectedIndex, 0)
        XCTAssertEqual(list.visibleIndices, Array(0..<9))
        list.clear()
        XCTAssertTrue(list.rows.isEmpty)
        XCTAssertNil(list.selectedIndex)
        XCTAssertNil(list.indexOnPage(0))
    }

    func testTranslationUsesExpectedSourceBeforeApplying() {
        var list = CandidateList(rows: makeRows(2))
        let before = list
        XCTAssertFalse(list.updateTranslation(at: 0, source: "旧候选", state: .ready("Old")))
        XCTAssertFalse(list.updateTranslation(at: -1, source: "候选0", state: .ready("Old")))
        XCTAssertFalse(list.updateTranslation(at: 2, source: "候选0", state: .ready("Old")))
        XCTAssertEqual(list, before)
        XCTAssertTrue(list.updateTranslation(at: 0, source: "候选0", state: .ready("Candidate zero")))
        XCTAssertEqual(list.selectedRow?.speechText, "Candidate zero")
        XCTAssertEqual(list.rows[1].translation, .pending)
    }

    func testTranslationStateControlsDisplayAndSpeechTogether() {
        var row = CandidateRow(candidate: Candidate(text: "你好", consumedCount: 5))
        XCTAssertTrue(row.needsTranslation)
        XCTAssertEqual(row.translation, .pending)
        XCTAssertEqual(row.translationText, "等待本地翻译")
        XCTAssertNil(row.speechText)
        row.translation = .ready("  Hello \n")
        XCTAssertEqual(row.translationText, "  Hello \n")
        XCTAssertEqual(row.speechText, "Hello")
        row.translation = .ready(" \n")
        XCTAssertNil(row.speechText)
        for (issue, label) in [
            (TranslationIssue.modelsNotInstalled, "未安装中英离线语言包"), (.failed, "本地翻译暂不可用"),
            (.noCandidates, "暂无候选，请检查拼音"), (.engineUnavailable, "苹果拼音暂不可用")
        ] {
            row.translation = .unavailable(issue)
            XCTAssertEqual(row.translationText, label)
            XCTAssertNil(row.speechText)
        }
        row.translation = .notRequired
        XCTAssertEqual(row.translationText, "")
        XCTAssertNil(row.speechText)
    }

    func testRawPinyinAndEmojiCannotBeSpokenEvenIfMarkedReady() {
        for text in ["nihao", "👋", ""] {
            var row = CandidateRow(candidate: Candidate(text: text, consumedCount: 5))
            XCTAssertFalse(row.needsTranslation)
            XCTAssertEqual(row.translation, .notRequired)
            row.translation = .ready("Hello")
            XCTAssertNil(row.speechText)
        }
        let mixed = CandidateRow(candidate: Candidate(text: "你好👋", consumedCount: 5), translation: .ready("Hello"))
        XCTAssertEqual(mixed.speechText, "Hello")
    }

    private func makeRows(_ count: Int) -> [CandidateRow] {
        (0..<count).map { CandidateRow(candidate: Candidate(text: "候选\($0)", consumedCount: 1)) }
    }
}
