import Darwin

private struct CheckFailure: Error, CustomStringConvertible {
    let description: String
}

func checkTrue(_ value: Bool, file: StaticString = #filePath, line: UInt = #line) throws {
    guard value else { throw CheckFailure(description: "\(file):\(line): expected true") }
}

func checkFalse(_ value: Bool, file: StaticString = #filePath, line: UInt = #line) throws {
    guard !value else { throw CheckFailure(description: "\(file):\(line): expected false") }
}

func checkEqual<T: Equatable>(_ actual: T, _ expected: T,
                             file: StaticString = #filePath, line: UInt = #line) throws {
    guard actual == expected else {
        throw CheckFailure(description: "\(file):\(line): expected \(expected), got \(actual)")
    }
}

/// A standalone suite for machines with Command Line Tools and no XCTest framework.
@main struct PunctuationChecks {
    @MainActor static func main() async {
        let checks = InputSessionPunctuationChecks()
        let uppercase = UppercaseChecks()
        let paging = PagingChecks()
        let cases: [(String, @MainActor () async throws -> Void)] = [
            ("Chinese punctuation follows the current mode", checks.chinesePunctuation),
            ("English punctuation passes through unchanged", checks.englishPunctuation),
            ("Caps Lock switches punctuation on both edges", checks.capsLockSwitchesPunctuation),
            ("Mode shortcut switches punctuation without key-repeat toggles", checks.shortcutSwitchesPunctuation),
            ("Command, Control and Option shortcuts pass through", checks.shortcutsPassThrough),
            ("Apostrophe remains a separator inside pinyin", checks.pinyinApostrophe),
            ("An apostrophe outside composition inserts a Chinese quote", checks.emptyCompositionApostrophe),
            ("Quotes follow text before the cursor", checks.quotesFollowCursorContext),
            ("Quotes never share state across hosts", checks.quotesAreIndependentAcrossHosts),
            ("Marked text is counted only once in quote context", checks.longMarkedTextPreservesOpeningQuote),
            ("A mode change while reading context leaves quotes unconverted", checks.contextReentrySwitchesToEnglish),
            ("Unmapped text is preserved", checks.unmappedTextIsPreserved),
            ("Composition and punctuation commit together once", checks.compositionCommitsWithPunctuation),
            ("Late candidates cannot revive committed composition", checks.lateCandidatesCannotReviveComposition),
            ("Reentrant host changes cannot move punctuation to another document", checks.reentrantHostChange),
            ("Uppercase lock toggles from both modes and physical Caps Lock states", uppercase.togglesFromBothModesAndCapsStates),
            ("Repeated Caps Lock and key events never repeat uppercase toggles or prompts", uppercase.repeatedEventsDoNotToggleOrRepeatStatus),
            ("Uppercase survives client changes, activation and shared sessions", uppercase.uppercaseSurvivesHostAndSessionChanges),
            ("A keyDown recovers a missed Caps Lock event only once", uppercase.keyDownRecoversMissedCapsEvent),
            ("Both switches back to Chinese clear uppercase lock", uppercase.returningToChineseClearsUppercase),
            ("Uppercase changes letters and preserves other text and shortcuts", uppercase.onlyLettersChangeAndShortcutsPassThrough),
            ("Uppercase toggle commits once and rejects late candidates", uppercase.toggleCommitsOnceAndRejectsLateCandidates),
            ("Reentrant commits cannot show an obsolete uppercase prompt", uppercase.reentrantCommitCannotShowObsoleteStatus),
            ("Left and right page candidates within the first and last boundaries", paging.arrowsPageAndStopAtBoundaries),
            ("Number and Space selection follow the displayed candidate page", paging.selectionsUseTheDisplayedPage),
            ("Plain Left pages candidates while Shift+Left restores a segment", paging.plainLeftPagesAndShiftLeftUndoesSegments),
            ("Arrows during candidate loading never commit or leave the IME", paging.arrowsDuringLoadingNeverCommit),
            ("Arrows pass through outside composition and with system shortcuts", paging.arrowsPassThroughOutsideCompositionAndWithShortcuts),
            ("Left and right match Page Up and Page Down", paging.arrowsMatchPageUpAndPageDown)
        ]
        var failures = 0
        for (name, run) in cases {
            do {
                try await run()
                print("PASS: \(name)")
            } catch {
                failures += 1
                print("FAIL: \(name) — \(error)")
            }
        }
        print("\(cases.count - failures)/\(cases.count) input checks passed")
        if failures > 0 { exit(1) }
    }
}
