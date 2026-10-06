import AppKit
import PinyinCore
import PinyinPresentation

/// Offscreen AppKit checks: does not register an input source or show a window.
@main
struct PresentationChecks {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        checkNativeCapsLockEvents()
        let translation = "This is a longer English translation used to verify that the selected candidate wraps without moving the window or hiding the original Chinese text."
        let longChinese = "我们正在检查较长中文候选和英文译文的显示效果"
        let rows = (0..<9).map { index in
            CandidateRow(candidate: Candidate(text: index == 4 ? longChinese : "候选词语\(index + 1)", consumedCount: 2),
                         translation: .ready(index == 4 ? translation : "Candidate translation \(index + 1)"))
        }
        let pending = rows.map { CandidateRow(candidate: $0.candidate) }
        let shortView = CandidateView(rows: pending, pinyin: "nihao", highlighted: 0, footer: "第 1/3 页")
        let expanded = CandidateView(rows: rows, pinyin: "womenzhengzaijianchajiaochangzhongwenhouxuan", highlighted: 4, footer: "第 1/3 页")
        require(shortView.preferredSize.width == expanded.preferredSize.width, "translation changed window width")
        require(candidateRows(expanded).count == 9, "normal screen must keep all nine candidates")
        require(expanded.accessibilityRole() == .list, "candidate container must expose a list")
        let selection = selectedRow(expanded)
        require(selection.accessibilityIndex() == 4, "accessible selection index differs from keyboard index")
        require(selection.accessibilityLabel()?.contains(translation) == true, "AX must preserve the complete translation")
        require(selection.accessibilityLabel()?.contains(longChinese) == true, "AX must preserve the complete Chinese candidate")
        require(selection.frame.height > candidateRows(expanded)[0].frame.height, "selected long text must expand")
        require(expanded.accessibilityValue() as? String == "womenzhengzaijianchajiaochangzhongwenhouxuan，第 1/3 页", "page and marked text must be available to AX")

        let constrained = CandidateView(rows: rows, pinyin: String(repeating: "nihao", count: 20), highlighted: 8,
                                        footer: "第 2/3 页", maximumSize: NSSize(width: 320, height: 190))
        require(constrained.preferredSize.width <= 320 && constrained.preferredSize.height <= 190, "candidate layout exceeds available screen")
        require(selectedRow(constrained).accessibilityIndex() == 8, "constrained layout lost the selected row")
        require(candidateRows(constrained).count < 9, "short display should expose only rows that fit")
        let lastVisible = candidateRows(constrained).last!
        require(lastVisible.accessibilityLabel()?.hasPrefix("第 9 项") == true, "visible row numbers must retain keyboard offsets")
        let constrainedFooter = constrained.subviews.last as! NSTextField
        require(constrainedFooter.stringValue.contains("↑↓ 查看"), "constrained layout must explain navigation")
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
        for view in [shortView, expanded, constrained, narrow, loading, arabic] { checkFrames(view) }

        let directory: URL?
        if let flag = CommandLine.arguments.firstIndex(of: "--render-directory"), CommandLine.arguments.indices.contains(flag + 1) {
            directory = URL(fileURLWithPath: CommandLine.arguments[flag + 1], isDirectory: true)
            try FileManager.default.createDirectory(at: directory!, withIntermediateDirectories: true)
        } else { directory = nil }
        for (name, view) in [("pending", shortView), ("translated", expanded), ("short-display", constrained), ("narrow-display", narrow), ("loading", loading), ("arabic", arabic)] {
            try render(view, name: name, directory: directory)
        }
        print("Presentation checks passed: native Caps Lock override/edge events, bounded/stable layout, expansion, original row indices, target-language AX state, offscreen rendering (6 cases).")
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
