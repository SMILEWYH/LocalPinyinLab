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
            ("Reentrant host changes cannot move punctuation to another document", checks.reentrantHostChange)
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
        print("\(cases.count - failures)/\(cases.count) punctuation checks passed")
        if failures > 0 { exit(1) }
    }
}
