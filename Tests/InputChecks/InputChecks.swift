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
@main struct InputChecks {
    @MainActor static func main() async {
        let checks = InputSessionPunctuationChecks()
        let uppercase = UppercaseChecks()
        let paging = PagingChecks()
        let asynchronous = AsyncInputChecks()
        let languages = TranslationLanguageChecks()
        let speech = SpeechShortcutChecks()
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
            ("A keyDown recovers physical Caps without inferring Shift+Caps", uppercase.keyDownRecoversMissedCapsEvent),
            ("Both switches back to Chinese clear uppercase lock", uppercase.returningToChineseClearsUppercase),
            ("Uppercase changes letters and preserves other text and shortcuts", uppercase.onlyLettersChangeAndShortcutsPassThrough),
            ("Uppercase toggle commits once and rejects late candidates", uppercase.toggleCommitsOnceAndRejectsLateCandidates),
            ("Reentrant commits cannot show an obsolete uppercase prompt", uppercase.reentrantCommitCannotShowObsoleteStatus),
            ("Left and right page candidates within the first and last boundaries", paging.arrowsPageAndStopAtBoundaries),
            ("Number and Space selection follow the displayed candidate page", paging.selectionsUseTheDisplayedPage),
            ("Plain Left pages candidates while Shift+Left restores a segment", paging.plainLeftPagesAndShiftLeftUndoesSegments),
            ("Arrows during candidate loading never commit or leave the IME", paging.arrowsDuringLoadingNeverCommit),
            ("Arrows pass through outside composition and with system shortcuts", paging.arrowsPassThroughOutsideCompositionAndWithShortcuts),
            ("Left and right match Page Up and Page Down", paging.arrowsMatchPageUpAndPageDown),
            ("Mode transitions show one status without replay on activation", uppercase.modeStatusAppearsOnceForEachTransition),
            ("Late candidates cannot replace a mode status", uppercase.modeStatusSurvivesLateCandidates),
            ("Reentrant commits cannot show an obsolete mode status", uppercase.reentrantCommitCannotShowObsoleteMode),
            ("Activation and restart map Caps off to Chinese and on to English", uppercase.activationAndRestartFollowPhysicalCaps),
            ("Ordinary Caps stays aligned after mode and uppercase shortcuts", uppercase.ordinaryCapsStaysAlignedAfterShortcuts),
            ("Modified Caps aligns mode while other system shortcuts pass through", uppercase.modifiedCapsAlignsWithoutStealingShortcuts),
            ("Hardware acknowledgement only records a deduplication baseline", uppercase.hardwareAcknowledgementOnlyChangesBaseline),
            ("Shared sessions adopt external Caps changes and restart cleanly", uppercase.sharedSessionsAdoptExternalCapsChanges),
            ("Up and Down preserve loading composition and cancel queued selection", asynchronous.verticalNavigationWhileLoadingPreservesComposition),
            ("Space commits selected Chinese after deleting the remaining pinyin", asynchronous.spaceCommitsSelectedTextAfterDeletingSuffix),
            ("Same-page highlight changes retain their translation request", asynchronous.samePageNavigationRetainsTranslationRequest),
            ("A changed page rejects late translations and preserves completed pages", asynchronous.changedPageRejectsLateTranslation),
            ("A changed query rejects late candidates and translations", asynchronous.changedQueryRejectsLateCandidatesAndTranslation),
            ("Highlight changes do not retry a failed translation", asynchronous.failedTranslationIsNotRetriedByHighlightChanges),
            ("Changing translation language preserves segments, candidates and page", languages.switchingLanguagePreservesCompositionAndPage),
            ("Returning to a language still rejects its obsolete batch", languages.returningToLanguageStillRejectsItsOldBatch),
            ("An in-flight candidate query uses the latest translation language", languages.languageChangeDuringQueryUsesLatestTarget),
            ("Speech stops on a language switch and uses the new voice language", languages.speechStopsAndFollowsCurrentLanguage),
            ("Selecting the current language does not restart speech or translation", languages.selectingSameLanguageDoesNotRestartWork),
            ("Translation reset preserves selection and candidate-engine diagnostics", languages.resetTranslationsPreservesSelectionAndEngineDiagnostics),
            ("Translation caches separate languages and preserve response ordering", languages.cacheSeparatesTargetsAndKeepsResponseOrder),
            ("Cancelled translations cannot populate another language's cache", languages.cancelledBatchCannotFillAnotherLanguagesCache),
            ("Speech shortcuts validate two and three keys and protect candidate controls", speech.validatesTwoAndThreeKeys),
            ("Persisted speech shortcuts reject invalid values and derive trusted names", speech.validatesPersistedValues),
            ("The default speech gesture plays once after all modifiers are released", speech.defaultGestureSpeaksOnceAfterRelease),
            ("Three-modifier speech gestures require every configured modifier", speech.threeModifierGestureRequiresTheCompleteChord),
            ("Other keys and extra modifiers cancel the entire speech gesture", speech.otherKeysAndExtraModifiersCancelTheWholeGesture),
            ("Released and repressed modifiers cannot rearm a speech gesture", speech.releasingAndRepressingModifiersCannotRearm),
            ("Translations arriving during a held chord cannot arm speech", speech.aTranslationArrivingDuringTheChordDoesNotArmIt),
            ("Custom speech key chords require ready speech and suppress repeats", speech.customKeyChordsRequireReadySpeechAndDoNotRepeat),
            ("Speech cancellation and shortcut changes require fresh chords", speech.explicitCancellationAndConfigurationChangesNeedFreshChords),
            ("Candidate, language and lifecycle changes cancel pending speech", speech.candidateLanguageAndLifecycleChangesCancelGestures)
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
