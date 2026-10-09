import AppKit
import PinyinCore
import PinyinPresentation

/// Offscreen AppKit checks: does not register an input source or show a window.
@main
struct PresentationChecks {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        checkTranslationPartOfSpeechInference()
        checkNativeCapsLockEvents()
        checkCandidateWindowBehavior()
        try await checkCandidateWindowRecovery()
        try await checkCandidateTouchBarIntegration()
        try await checkCandidateTouchBarBehavior()
        let translation = "This is a longer English translation used to verify that every candidate wraps automatically and preserves the original Chinese text."
        let longChinese = "我们正在检查较长中文候选和英文译文的显示效果"
        let rows = (0..<9).map { index in
            CandidateRow(candidate: Candidate(text: index == 4 ? longChinese : "候选词语\(index + 1)", consumedCount: 2),
                         translation: .ready(index == 4 ? translation : "Candidate translation \(index + 1)"))
        }
        let compactRows = [CandidateRow(candidate: Candidate(text: "你好", consumedCount: 2), translation: .ready("Hello")),
                           CandidateRow(candidate: Candidate(text: "你", consumedCount: 1), translation: .ready("You"))]
        let pending = compactRows.map { CandidateRow(candidate: $0.candidate) }
        let shortView = CandidateView(rows: pending, pinyin: "nihao", highlighted: 0, footer: "第 1/3 页")
        let translatedShortView = CandidateView(rows: compactRows.map { CandidateRow(candidate: $0.candidate, translation: .ready(translation)) },
                                               pinyin: "nihao", highlighted: 0, footer: "第 1/3 页")
        let expanded = CandidateView(rows: rows, pinyin: "womenzhengzaijianchajiaochangzhongwenhouxuan", highlighted: 4, footer: "第 1/3 页")
        require(shortView.preferredSize.width < translatedShortView.preferredSize.width && translatedShortView.preferredSize.width == 600,
                "loaded translations should grow the same short candidates up to the 600-point cap")
        require(expanded.preferredSize.width == 600, "long content must stop at the fixed 600-point maximum")
        let compact = CandidateView(rows: compactRows, pinyin: "nihao", highlighted: 0, footer: "英语译文 · 第 1/1 页")
        require(compact.preferredSize.width < 240, "short content should not retain a fixed or minimum window width")
        let wideScreen = CandidateView(rows: rows, pinyin: "nihao", highlighted: 4, footer: "第 1/3 页",
                                       maximumSize: NSSize(width: 1600, height: 1000))
        require(wideScreen.preferredSize.width == 600, "a wide screen must not raise the fixed 600-point maximum")
        let longHeader = CandidateView(rows: compactRows, pinyin: String(repeating: "nihao", count: 20),
                                       highlighted: 0, footer: "第 1/1 页")
        require(longHeader.preferredSize.width > compact.preferredSize.width && longHeader.preferredSize.width <= 600,
                "header text should participate in content sizing while respecting the cap")
        require(candidateRows(longHeader)[0].subviews[1].frame.width == candidateRows(compact)[0].subviews[1].frame.width,
                "a long header must not stretch the Chinese column")
        let footerText = "英语译文 · 较长状态说明应撑开窗口，同时保持候选与译文左对齐"
        let longFooter = CandidateView(rows: compactRows, pinyin: "nihao", highlighted: 0, footer: footerText)
        require(longFooter.preferredSize.width > compact.preferredSize.width,
                "footer text should participate in content sizing")
        checkSingleLineFits(longFooter.subviews.last as! NSTextField)
        require(candidateRows(expanded).count == 9, "normal screen must keep all nine candidates")
        require(expanded.accessibilityRole() == .list, "candidate container must expose a list")
        let selection = selectedRow(expanded)
        require(selection.accessibilityIndex() == 4, "accessible selection index differs from keyboard index")
        require(selection.accessibilityLabel()?.contains(translation) == true, "AX must preserve the complete translation")
        require(selection.accessibilityLabel()?.contains(longChinese) == true, "AX must preserve the complete Chinese candidate")
        require(selection.frame.height > candidateRows(expanded)[0].frame.height, "long text must expand")
        require(expanded.accessibilityValue() as? String == "womenzhengzaijianchajiaochangzhongwenhouxuan，第 1/3 页", "page and marked text must be available to AX")

        let multilineChinese = String(repeating: "每个候选无论是否选中都应自动换行，完整显示所有内容。", count: 3)
        let multilineTranslation = String(repeating: "Every candidate must wrap automatically and keep every line visible, whether selected or not. ", count: 3)
        let multilineRows = (0..<2).map { _ in
            CandidateRow(candidate: Candidate(text: multilineChinese, consumedCount: 2), translation: .ready(multilineTranslation))
        }
        let multiline = CandidateView(rows: multilineRows, pinyin: "houxuan", highlighted: 0, footer: "第 1/1 页",
                                      maximumSize: NSSize(width: 320, height: 1600))
        let reselected = CandidateView(rows: multilineRows, pinyin: "houxuan", highlighted: 1, footer: "第 1/1 页",
                                       maximumSize: NSSize(width: 320, height: 1600))
        require(candidateRows(multiline).count == 2 && candidateRows(reselected).count == 2,
                "ample vertical space must show both long candidates")
        require(candidateRows(multiline).map(\.frame.height) == candidateRows(reselected).map(\.frame.height),
                "selection must not change wrapping or row height")
        for row in candidateRows(multiline) {
            require(row.accessibilityLabel()?.contains(multilineChinese) == true && row.accessibilityLabel()?.contains(multilineTranslation) == true,
                    "AX must preserve all selected and unselected multiline text")
            for label in row.subviews.dropFirst().compactMap({ $0 as? NSTextField }) {
                let lineHeight = NSLayoutManager().defaultLineHeight(for: label.font!)
                require(label.bounds.height > lineHeight * 3, "long candidate and translation must not be limited to three lines")
                checkWrappedTextFits(label)
            }
        }
        require(selectedRow(reselected).accessibilityIndex() == 1, "selection must remain accessible after reflow")
        let unbrokenText = String(repeating: "W", count: 160)
        let unbroken = CandidateView(rows: [CandidateRow(candidate: Candidate(text: "连续文本", consumedCount: 2),
                                                         translation: .ready(unbrokenText))],
                                     pinyin: "wenben", highlighted: 0, footer: "第 1/1 页",
                                     maximumSize: NSSize(width: 360, height: 1000))
        let unbrokenGloss = candidateRows(unbroken)[0].subviews[2] as! NSTextField
        require(unbroken.preferredSize.width == 360, "long unbroken words must respect available width")
        require(unbrokenGloss.bounds.height > NSLayoutManager().defaultLineHeight(for: unbrokenGloss.font!) * 3,
                "long unbroken translations must wrap across more than three lines")
        checkWrappedTextFits(unbrokenGloss)
        require(selectedRow(unbroken).accessibilityLabel()?.contains(unbrokenText) == true,
                "AX must retain the complete unbroken translation")

        let constrained = CandidateView(rows: rows, pinyin: String(repeating: "nihao", count: 20), highlighted: 8,
                                        footer: "第 2/3 页", maximumSize: NSSize(width: 320, height: 190))
        require(constrained.preferredSize.width <= 320 && constrained.preferredSize.height <= 190, "candidate layout exceeds available screen")
        require(selectedRow(constrained).accessibilityIndex() == 8, "constrained layout lost the selected row")
        require(candidateRows(constrained).count < 9, "short display should expose only rows that fit")
        let lastVisible = candidateRows(constrained).last!
        require(lastVisible.accessibilityLabel()?.hasPrefix("第 9 项") == true, "visible row numbers must retain keyboard offsets")
        let constrainedFooter = constrained.subviews.last as! NSTextField
        require(constrainedFooter.stringValue.contains("↑↓ 查看"), "constrained layout must explain navigation")
        let tinyRows = (0..<9).map { _ in
            CandidateRow(candidate: Candidate(text: "你", consumedCount: 1), translation: .ready("Hi"))
        }
        let tinyFull = CandidateView(rows: tinyRows, pinyin: "ni", highlighted: 8, footer: "第 1/1 页")
        let conditionalFooter = CandidateView(rows: tinyRows, pinyin: "ni", highlighted: 8, footer: "第 1/1 页",
                                              maximumSize: NSSize(width: 1000, height: 130))
        require(candidateRows(conditionalFooter).count < tinyRows.count, "short height must hide some compact rows")
        require(conditionalFooter.preferredSize.width > tinyFull.preferredSize.width,
                "conditional row-range navigation text must participate in natural width")
        let navigationFooter = conditionalFooter.subviews.last as! NSTextField
        require(navigationFooter.stringValue.contains("↑↓ 查看"), "conditional footer must expose the navigation hint")
        checkSingleLineFits(navigationFooter)
        let narrow = CandidateView(rows: rows, pinyin: "nihao", highlighted: 4,
                                   footer: "第 1/3 页", maximumSize: NSSize(width: 180, height: 360))
        require(narrow.preferredSize.width == 180, "narrow display exceeds available width")
        let loading = CandidateView(rows: [], pinyin: "nihao", highlighted: -1, footer: "查询中…", minimumHeight: 160)
        require(loading.accessibilityLabel()?.contains("查询中") == true, "loading must have accessible status")
        require((loading.accessibilitySelectedChildren() ?? []).isEmpty, "loading must not expose stale selected candidates")
        require(loading.preferredSize.height == 160, "loading should preserve the preceding window height")
        let arabic = CandidateView(rows: [CandidateRow(candidate: Candidate(text: "你好", consumedCount: 2),
                                                       translation: .ready("مرحبًا بك"))],
                                   pinyin: "nihao", highlighted: 0, footer: "阿拉伯语译文 · 第 1/1 页",
                                   translationLanguage: .arabic)
        require(selectedRow(arabic).accessibilityLabel()?.contains("阿拉伯语译文：مرحبًا بك") == true,
                "AX must announce the selected target language and preserve right-to-left text")
        let missing = CandidateRow(candidate: Candidate(text: "你好", consumedCount: 2), translation: .unavailable(.modelsNotInstalled))
        require(missing.translationText(for: .japanese).contains("日语"), "missing-model message must name the selected language")
        let partOfSpeechScenarios = checkTranslationPartsOfSpeech()
        let scenarios: [(String, CandidateView)] = [
            ("pending", shortView), ("translated", expanded), ("compact", compact), ("wide-screen-cap", wideScreen),
            ("long-header", longHeader), ("long-footer", longFooter), ("all-rows-wrap", multiline),
            ("reselected", reselected), ("unbroken-translation", unbroken), ("short-display", constrained),
            ("conditional-footer", conditionalFooter), ("narrow-display", narrow), ("loading", loading), ("arabic", arabic)
        ] + partOfSpeechScenarios
        for view in [translatedShortView] + scenarios.map({ $0.1 }) {
            checkFrames(view)
            checkColumns(view)
        }

        let directory: URL?
        if let flag = CommandLine.arguments.firstIndex(of: "--render-directory"), CommandLine.arguments.indices.contains(flag + 1) {
            directory = URL(fileURLWithPath: CommandLine.arguments[flag + 1], isDirectory: true)
            try FileManager.default.createDirectory(at: directory!, withIntermediateDirectories: true)
        } else { directory = nil }
        for (name, view) in scenarios {
            try render(view, name: name, directory: directory)
        }
        print("Presentation checks passed: Space recovery, cancellation and visible window reuse (8 scenarios), Touch Bar selection updates and owner-scoped lifecycle cleanup, host-aware candidate window levels without activation, native Caps Lock override/edge events, content-sized left-aligned columns with 40-point spacing and a 600-point cap, English POS labels with aligned translations and narrow-screen clamping, automatic wrapping for every candidate and translation, original row indices, target-language AX state, offscreen rendering (\(scenarios.count) cases).")
    }

    @MainActor private static func checkTranslationPartsOfSpeech() -> [(String, CandidateView)] {
        let samples: [(String, String, String?)] = [
            ("苹果", "apple", "n."), ("美丽", "beautiful", "adj."), ("迅速", "quickly", "adv."),
            ("奔跑", "running", "v."), ("小苹果", "a small apple", nil)
        ]
        let rows = samples.map {
            CandidateRow(candidate: Candidate(text: $0.0, consumedCount: 2), translation: .ready($0.1))
        }
        let view = CandidateView(rows: rows, pinyin: "pingguo", highlighted: 1, footer: "英语译文 · 第 1/1 页")
        let renderedRows = candidateRows(view)
        require(renderedRows.count == samples.count, "POS examples must fit without hiding candidates")
        for (row, sample) in zip(renderedRows, samples) {
            let translation = row.subviews[2] as! NSTextField
            require(translation.stringValue == sample.1, "a POS label must preserve the original translation text")
            checkWrappedTextFits(translation)
            if let abbreviation = sample.2 {
                require(row.subviews.count == 4, "single-word translations must expose a separate POS label")
                let label = row.subviews[3] as! NSTextField
                require(label.stringValue == abbreviation, "English translation has the wrong POS abbreviation")
                require(abs(translation.frame.minX - label.frame.maxX - 6) < 0.01,
                        "the POS label must sit six points to the left of the translation")
                require(label.font!.pointSize < translation.font!.pointSize,
                        "POS labels must be visually subordinate to translations")
                require(!label.isAccessibilityElement(), "POS should be announced as part of its complete candidate row")
                checkSingleLineFits(label)
            } else {
                require(row.subviews.count == 3, "translation phrases must not receive a guessed POS label")
            }
        }

        let unavailableRows = [
            CandidateRow(candidate: Candidate(text: "苹果", consumedCount: 2)),
            CandidateRow(candidate: Candidate(text: "美丽", consumedCount: 2), translation: .unavailable(.modelsNotInstalled))
        ]
        let unavailable = CandidateView(rows: unavailableRows, pinyin: "pingguo", highlighted: 0, footer: "英语译文 · 第 1/1 页")
        require(candidateRows(unavailable).allSatisfy { $0.subviews.count == 3 },
                "pending and unavailable translation messages must not acquire POS labels")
        let otherLanguage = CandidateView(rows: rows, pinyin: "pingguo", highlighted: 0, footer: "日语译文 · 第 1/1 页",
                                          translationLanguage: .japanese)
        require(candidateRows(otherLanguage).allSatisfy { $0.subviews.count == 3 },
                "English POS classification must not be applied to other target languages")

        var scenarios = [("english-parts-of-speech", view), ("parts-of-speech-unavailable", unavailable),
                         ("parts-of-speech-other-language", otherLanguage)]
        for width: CGFloat in [180, 120, 80, 32, 12, 1] {
            let narrow = CandidateView(rows: rows, pinyin: "pingguo", highlighted: 0, footer: "英语译文 · 第 1/1 页",
                                       maximumSize: NSSize(width: width, height: 1600))
            require(narrow.preferredSize.width <= width, "POS annotations must not exceed the available width")
            require(selectedRow(narrow).accessibilityIndex() == 0, "narrow POS layout must retain the selected candidate")
            checkFrames(narrow)
            checkColumns(narrow)
            if width >= 120 {
                for row in candidateRows(narrow) {
                    checkWrappedTextFits(row.subviews[1] as! NSTextField)
                    checkWrappedTextFits(row.subviews[2] as! NSTextField)
                }
            }
            // Tiny widths exercise clamping, but do not produce useful review images.
            if width == 180 { scenarios.append(("english-parts-of-speech-narrow", narrow)) }
        }
        return scenarios
    }

    @MainActor private static func checkNativeCapsLockEvents() {
        let staleOff = keyboardEvent(type: .keyDown, flags: [.shift], code: 0, characters: "A")
        guard case .key(let pendingOn) = InputEvent(event: staleOff, capsLockOverride: true) else {
            fatalError("keyDown was not adapted to a key stroke")
        }
        require(pendingOn.capsLock, "pending Caps Lock on must override an old off keyDown flag")
        require(pendingOn.code == 0 && pendingOn.characters == "A" && pendingOn.modifiers == [.shift],
                "Caps Lock override must preserve the physical key, text and other modifiers")
        require(pendingOn.textIgnoringCapsLock == "A", "pending lock on must not rewrite characters captured without Caps Lock")

        let staleOn = keyboardEvent(type: .keyDown, flags: [.capsLock], code: 0, characters: "A")
        guard case .key(let pendingOff) = InputEvent(event: staleOn, capsLockOverride: false) else {
            fatalError("keyDown was not adapted to a key stroke")
        }
        require(!pendingOff.capsLock, "pending Caps Lock off must override an old on keyDown flag")
        require(pendingOff.characters == "A" && pendingOff.textIgnoringCapsLock == "a",
                "old Caps Lock characters must be normalized while preserving the original text for host forwarding")
        let shiftedStaleOn = keyboardEvent(type: .keyDown, flags: [.capsLock, .shift], code: 0, characters: "a")
        guard case .key(let shiftedPendingOff) = InputEvent(event: shiftedStaleOn, capsLockOverride: false) else {
            fatalError("shifted keyDown adaptation failed")
        }
        require(shiftedPendingOff.characters == "a" && shiftedPendingOff.textIgnoringCapsLock == "A",
                "Shift must control character case even while the logical lock differs from captured Caps Lock")
        let lowercaseWithoutCaps = keyboardEvent(type: .keyDown, flags: [], code: 0, characters: "a")
        guard case .key(let lowercasePendingOn) = InputEvent(event: lowercaseWithoutCaps, capsLockOverride: true) else {
            fatalError("lowercase keyDown adaptation failed")
        }
        require(lowercasePendingOn.textIgnoringCapsLock == "a", "pending lock on must preserve old lock-off lowercase text")
        for modifier: NSEvent.ModifierFlags in [.control, .option, .command] {
            let shortcut = keyboardEvent(type: .keyDown, flags: [.capsLock, modifier], code: 0, characters: "A")
            guard case .key(let stroke) = InputEvent(event: shortcut, capsLockOverride: false) else {
                fatalError("shortcut keyDown adaptation failed")
            }
            // NSEvent may itself encode Control+A as a control character.
            let capturedText = shortcut.characters ?? ""
            require(stroke.passesThrough && stroke.characters == capturedText && stroke.textIgnoringCapsLock == capturedText,
                    "Caps Lock normalization must preserve command, control and option shortcuts")
        }
        guard case .key(let unchangedOn) = InputEvent(event: staleOn),
              case .key(let unchangedOff) = InputEvent(event: staleOff) else {
            fatalError("default keyDown adaptation failed")
        }
        require(unchangedOn.capsLock && !unchangedOff.capsLock, "nil override must use the actual event flags")

        let physicalOn = keyboardEvent(type: .flagsChanged, flags: [.capsLock, .shift], code: 57)
        let physicalOff = keyboardEvent(type: .flagsChanged, flags: [], code: 57)
        guard case .capsLock(let actualOn, let modifiers) = InputEvent(event: physicalOn, capsLockOverride: false),
              case .capsLock(let actualOff, _) = InputEvent(event: physicalOff, capsLockOverride: true) else {
            fatalError("Caps Lock flagsChanged was not adapted to a modifier edge")
        }
        require(actualOn && !actualOff, "real Caps Lock edges must ignore the pending keyDown override")
        require(modifiers == [.shift], "physical Caps Lock edges must preserve other modifiers")

        let chord = keyboardEvent(type: .flagsChanged, flags: [.command, .option], code: 58)
        let release = keyboardEvent(type: .flagsChanged, flags: [], code: 55)
        guard case .modifiersChanged(let chordModifiers) = InputEvent(event: chord),
              case .modifiersChanged(let releasedModifiers) = InputEvent(event: release) else {
            fatalError("Command/Option edges must reach the speech gesture")
        }
        require(chordModifiers == [.command, .option] && releasedModifiers.isEmpty,
                "modifier adaptation must preserve both press and final release")
        let keyUp = keyboardEvent(type: .keyUp, flags: [.command, .option], code: 4)
        guard case .shortcutCancelled = InputEvent(event: keyUp) else {
            fatalError("a keyUp must invalidate a gesture even if keyDown was handled by the app")
        }
        let fn = keyboardEvent(type: .flagsChanged, flags: [.command, .option, .function], code: 63)
        guard case .shortcutCancelled = InputEvent(event: fn) else {
            fatalError("unsupported Fn must not look like a clean modifier-only speech chord")
        }
        let fnHeld = keyboardEvent(type: .flagsChanged, flags: [.command, .option, .function], code: 55)
        guard case .shortcutCancelled = InputEvent(event: fnHeld) else {
            fatalError("a supported modifier edge must still reject an already-held Fn key")
        }
    }

    @MainActor private static func keyboardEvent(type: NSEvent.EventType, flags: NSEvent.ModifierFlags,
                                                code: UInt16, characters: String = "") -> NSEvent {
        guard let event = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags, timestamp: 0,
            windowNumber: 0, context: nil, characters: characters, charactersIgnoringModifiers: characters,
            isARepeat: false, keyCode: code) else { fatalError("Cannot construct native keyboard event") }
        return event
    }

    @MainActor private static func candidateRows(_ view: CandidateView) -> [NSView] {
        (view.accessibilityChildren() ?? []).compactMap { $0 as? NSView }.filter { $0.accessibilityRole() == .row }
    }

    @MainActor private static func selectedRow(_ view: CandidateView) -> NSView {
        let rows = (view.accessibilitySelectedChildren() ?? []).compactMap { $0 as? NSView }
        require(rows.count == 1 && rows[0].isAccessibilitySelected(), "candidate selection must be exposed exactly once")
        return rows[0]
    }

    @MainActor private static func checkColumns(_ view: CandidateView) {
        var chineseX: CGFloat?
        var translationX: CGFloat?
        let rows = candidateRows(view)
        let partOfSpeechX = rows.first(where: { $0.subviews.count > 3 })?.subviews[3].frame.minX
        for row in rows {
            let chinese = row.subviews[1] as! NSTextField
            let translation = row.subviews[2] as! NSTextField
            let annotationX = partOfSpeechX ?? translation.frame.minX
            let annotationGap = annotationX - chinese.frame.maxX
            require(annotationGap >= -0.01 && annotationGap <= 40.01,
                    "Chinese and annotation columns must preserve their gap within screen bounds")
            if view.preferredSize.width >= 100 {
                require(abs(annotationGap - 40) < 0.01, "Chinese and annotation columns must have a fixed 40-point gap")
            }
            require(chinese.alignment == .left && translation.alignment == .left, "both columns must stay left-aligned")
            if row.subviews.count > 3 {
                let partOfSpeech = row.subviews[3] as! NSTextField
                require(partOfSpeech.alignment == .left && partOfSpeech.frame.minX == annotationX,
                        "POS labels must share a left-aligned column")
                require(partOfSpeech.frame.maxX <= translation.frame.minX + 0.01,
                        "POS labels must not overlap translation text")
            }
            if let chineseX { require(chinese.frame.minX == chineseX, "Chinese starts must align across rows") }
            if let translationX { require(translation.frame.minX == translationX, "translation starts must align across rows") }
            chineseX = chinese.frame.minX
            translationX = translation.frame.minX
        }
    }

    @MainActor private static func checkSingleLineFits(_ label: NSTextField) {
        guard let cell = label.cell else { fatalError("Text label has no cell") }
        require(cell.cellSize.width <= label.bounds.width + 0.5,
                "content-sized footer must fit its full text: \(cell.cellSize.width) / \(label.bounds.width)")
    }

    @MainActor private static func checkWrappedTextFits(_ label: NSTextField) {
        guard let cell = label.cell else { fatalError("Text label has no cell") }
        require(label.maximumNumberOfLines == 0, "candidate and translation labels must allow unlimited wrapped lines")
        let needed = cell.cellSize(forBounds: NSRect(x: 0, y: 0, width: label.bounds.width, height: 10000)).height
        require(needed <= label.bounds.height + 0.5,
                "wrapped text must fit fully when vertical space is available: \(needed) / \(label.bounds.height)")
    }

    @MainActor private static func checkFrames(_ view: NSView) {
        for child in view.subviews {
            let frame = child.frame
            require(frame.minX >= -0.5 && frame.minY >= -0.5 && frame.maxX <= view.bounds.width + 0.5 && frame.maxY <= view.bounds.height + 0.5,
                    "child \(type(of: child)) exceeds parent: \(frame) / \(view.bounds)")
            checkFrames(child)
        }
    }

    @MainActor private static func render(_ view: CandidateView, name: String, directory: URL?) throws {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: view.preferredSize), styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = view
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { fatalError("Cannot create render bitmap") }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("Cannot encode render bitmap") }
        require(png.count > 1000, "render bitmap is unexpectedly empty")
        if let directory { try png.write(to: directory.appendingPathComponent(name + ".png")) }
        window.contentView = nil
    }

    @MainActor private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message)
    }
}
