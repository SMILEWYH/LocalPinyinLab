import AppKit
import PinyinCore
import PinyinPresentation

extension PresentationChecks {
    @MainActor static func checkIncrementalCandidates() async throws {
        checkSelectionReusesViews()
        try checkTallCandidateScrolling()
        try await checkAsynchronousAnnotations()
    }

    @MainActor private static func checkSelectionReusesViews() {
        let presenter = incrementalPanel(provider: EmptyAnnotations())
        defer { presenter.hide() }
        let rows = incrementalRows()
        showIncremental(rows, selected: 0, on: presenter)
        let view = presenter.panel.contentView as! CandidateView
        let children = view.subviews
        let first = view.accessibilitySelectedChildren()!.first as! NSView
        let frames = view.subviews.map(\.frame)
        showIncremental(rows, selected: 1, on: presenter)
        precondition(presenter.panel.contentView === view && zip(children, view.subviews).allSatisfy { $0 === $1 },
                     "a selection-only update must reuse the candidate view and all its row/text views")
        precondition(view.subviews.map(\.frame) == frames && view.highlighted == 1,
                     "selection must preserve measured layout and update the highlighted index")
        let selected = view.accessibilitySelectedChildren()!.first as! NSView
        precondition(selected.accessibilityIndex() == 1 && !first.isAccessibilitySelected(),
                     "the reused view must publish only the new accessibility selection")
        precondition(candidateLabels(first)[1].textColor != .white && candidateLabels(selected)[1].textColor == .white,
                     "reusing rows must update the visible text colors of both affected rows")
        var changed = rows
        changed[1].translation = .ready("A longer changed translation")
        showIncremental(changed, selected: 1, on: presenter)
        precondition(presenter.panel.contentView !== view, "new translation text must invalidate the previous layout")

        let short = CandidateView(rows: (0..<9).map { _ in rows[0] }, pinyin: "ni", highlighted: 0,
                                  footer: "第 1/1 页", maximumSize: NSSize(width: 300, height: 130))
        precondition(!short.updateHighlighted(8) && short.highlighted == 0,
                     "a short-screen selection that changes the visible range must request a new layout")
    }

    @MainActor private static func checkTallCandidateScrolling() throws {
        let chinese = String(repeating: "需要完整显示的中文候选内容", count: 12)
        let translation = (1...45).map { "Line \($0): This text must remain reachable." }.joined(separator: "\n")
        let row = CandidateRow(candidate: Candidate(text: chinese, consumedCount: 2), translation: .ready(translation))
        let view = CandidateView(rows: [row], pinyin: "ceshi", highlighted: 0, footer: "英语译文 · 第 1/1 页",
                                 maximumSize: NSSize(width: 320, height: 190))
        let selected = view.accessibilitySelectedChildren()!.first as! NSView
        let clip = selected.subviews.compactMap { $0 as? NSClipView }.first!
        let document = clip.documentView!
        let gloss = candidateLabels(selected)[2]
        let needed = gloss.cell!.cellSize(forBounds: NSRect(x: 0, y: 0, width: gloss.frame.width, height: 100000)).height
        precondition(needed <= gloss.frame.height && document.frame.height > clip.frame.height && clip.bounds.minY == 0,
                     "an oversized row must retain its entire natural text in a viewport initially scrolled to the top")
        precondition((view.subviews.last as! NSTextField).stringValue.hasPrefix("全文 1/") &&
                     (view.subviews.last as! NSTextField).stringValue.contains("⇧PageUp/Down"),
                     "an oversized single candidate must advertise its full-text navigation before a possibly truncated footer")
        precondition(view.scrollHighlightedCandidate(by: 1) && clip.bounds.minY > 0 && view.highlighted == 0,
                     "full-text page down must move the text while preserving the selected candidate")
        let firstOffset = clip.bounds.minY
        precondition(firstOffset < clip.frame.height, "full-text pages should overlap so text cannot fall between pages")
        precondition(view.scrollHighlightedCandidate(by: Int.max) && abs(clip.bounds.maxY - document.frame.maxY) < 0.5,
                     "the final text page must reach the last line without exceeding the document")
        precondition(view.scrollHighlightedCandidate(by: 1) && abs(clip.bounds.maxY - document.frame.maxY) < 0.5,
                     "scrolling beyond the end must stay consumed instead of turning the candidate page")
        precondition(view.highlightedScrollProgress == 1 && candidateLabels(selected)[1].stringValue == chinese && gloss.stringValue == translation,
                     "scrolling must retain complete Chinese and translation strings")
        precondition(view.scrollHighlightedCandidate(by: -1) && clip.bounds.maxY < document.frame.maxY,
                     "full-text page up must move towards the beginning")
        precondition(view.scrollHighlightedCandidate(by: Int.min) && clip.bounds.minY == 0,
                     "large backwards scrolls must safely clamp to the beginning")
        precondition(selected.accessibilityLabel()?.contains(translation) == true,
                     "the complete translation must remain available to accessibility independently of the viewport")
        let compact = CandidateView(rows: incrementalRows(), pinyin: "ni", highlighted: 0, footer: "第 1/1 页")
        precondition(!compact.scrollHighlightedCandidate(by: 1), "ordinary rows must preserve the original page-key handling")
        if let index = CommandLine.arguments.firstIndex(of: "--render-directory"), CommandLine.arguments.indices.contains(index + 1) {
            let directory = URL(fileURLWithPath: CommandLine.arguments[index + 1], isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try renderScrollingCandidate(view, at: directory.appendingPathComponent("full-text-top.png"))
            _ = view.scrollHighlightedCandidate(by: Int.max)
            try renderScrollingCandidate(view, at: directory.appendingPathComponent("full-text-bottom.png"))
        }
    }

    @MainActor private static func checkAsynchronousAnnotations() async throws {
        let provider = ControlledAnnotations()
        let presenter = incrementalPanel(provider: provider)
        defer { presenter.hide() }
        let rows = incrementalRows()
        showIncremental(rows, selected: 0, on: presenter)
        let initial = presenter.panel.contentView as! CandidateView
        precondition(candidateLabels(initial.accessibilitySelectedChildren()!.first as! NSView).count == 3,
                     "ready translations must appear immediately, before optional annotations complete")
        try await waitForAnnotations { await provider.count == 1 }
        showIncremental(rows, selected: 1, on: presenter)
        precondition(presenter.panel.contentView === initial, "selection changes must not wait for or restart annotations")
        await provider.resolve(0, with: [.noun, .pronoun])
        try await waitForAnnotations { presenter.panel.contentView !== initial }
        let annotated = presenter.panel.contentView as! CandidateView
        let selected = annotated.accessibilitySelectedChildren()!.first as! NSView
        let count = await provider.count
        precondition(count == 1 && annotated.highlighted == 1 && candidateLabels(selected).last?.stringValue == "pron.",
                     "annotation completion must retain a later selection and annotate only the current content")
        precondition(selected.accessibilityLabel()?.contains("词性：代词") == true,
                     "the inferred annotation must become part of the complete accessible row")
        let wasMainThread = await provider.ranOnMainThread
        precondition(!wasMainThread, "the annotation provider must run on its independent actor")

        var replacement = rows
        replacement[0].translation = .ready("banana")
        showIncremental(replacement, selected: 0, on: presenter)
        try await waitForAnnotations { await provider.count == 2 }
        showIncremental(rows, selected: 0, language: .japanese, on: presenter)
        let japanese = presenter.panel.contentView
        await provider.resolve(1, with: [.noun, .pronoun])
        try await Task.sleep(for: .milliseconds(30))
        precondition(presenter.panel.contentView === japanese,
                     "a late English annotation must not replace a view after the target language changes")

        showIncremental(replacement, selected: 0, on: presenter)
        try await waitForAnnotations { await provider.count == 3 }
        presenter.hide()
        let hidden = presenter.panel.contentView
        await provider.resolve(2, with: [.noun, .pronoun])
        try await Task.sleep(for: .milliseconds(30))
        precondition(!presenter.panel.isVisible && presenter.panel.contentView === hidden &&
                     !presenter.scrollHighlightedCandidate(by: 1),
                     "a late annotation must never reopen a hidden panel or expose stale full-text scrolling")

        showIncremental(replacement, selected: 0, on: presenter)
        try await waitForAnnotations { await provider.count == 4 }
        showIncremental(rows, selected: 1, on: presenter)
        try await waitForAnnotations { await provider.count == 5 }
        let newest = presenter.panel.contentView
        await provider.resolve(3, with: [.noun, .pronoun])
        try await Task.sleep(for: .milliseconds(30))
        precondition(presenter.panel.contentView === newest,
                     "a superseded same-language annotation must not overwrite a newer candidate query")
        await provider.resolve(4, with: [.noun, .pronoun])
        try await waitForAnnotations { presenter.panel.contentView !== newest }
    }

    @MainActor private static func incrementalRows() -> [CandidateRow] {
        [CandidateRow(candidate: Candidate(text: "苹果", consumedCount: 2), translation: .ready("apple")),
         CandidateRow(candidate: Candidate(text: "你", consumedCount: 2), translation: .ready("you"))]
    }

    @MainActor private static func incrementalPanel(provider: any TranslationPartOfSpeechProviding) -> CandidatePanel {
        CandidatePanel(panelFactory: { IncrementalPanel() }, foregroundPID: { nil }, partOfSpeechProvider: provider)
    }

    @MainActor private static func showIncremental(_ rows: [CandidateRow], selected: Int,
                                                   language: TranslationLanguage = .english, on presenter: CandidatePanel) {
        presenter.show(rows: rows, pinyin: "ni", selected: selected, page: 0, totalPages: 1,
                       anchor: NSRect(x: 300, y: 400, width: 1, height: 20), translationLanguage: language)
    }

    @MainActor private static func waitForAnnotations(_ predicate: @MainActor () async -> Bool) async throws {
        for _ in 0..<100 {
            if await predicate() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        preconditionFailure("asynchronous annotations did not reach the expected state")
    }

    @MainActor private static func renderScrollingCandidate(_ view: CandidateView, at url: URL) throws {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: view.preferredSize), styleMask: .borderless,
                              backing: .buffered, defer: false)
        window.contentView = view
        defer { window.contentView = nil }
        view.layoutSubtreeIfNeeded()
        let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try bitmap.representation(using: .png, properties: [:])!.write(to: url)
    }
}

private actor EmptyAnnotations: TranslationPartOfSpeechProviding {
    func annotations(for rows: [CandidateRow], language: TranslationLanguage) -> [TranslationPartOfSpeech?] {
        Array(repeating: nil, count: rows.count)
    }
}

private actor ControlledAnnotations: TranslationPartOfSpeechProviding {
    private var pending: [Int: CheckedContinuation<[TranslationPartOfSpeech?], Never>] = [:]
    private(set) var count = 0
    private(set) var ranOnMainThread = false

    func annotations(for rows: [CandidateRow], language: TranslationLanguage) async -> [TranslationPartOfSpeech?] {
        ranOnMainThread = ranOnMainThread || Thread.isMainThread
        let index = count
        count += 1
        return await withCheckedContinuation { pending[index] = $0 }
    }

    func resolve(_ index: Int, with annotations: [TranslationPartOfSpeech?]) {
        pending.removeValue(forKey: index)!.resume(returning: annotations)
    }
}

@MainActor private final class IncrementalPanel: NSPanel {
    private var simulatedVisible = false
    init() { super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false) }
    override var isVisible: Bool { simulatedVisible }
    override func orderFrontRegardless() { simulatedVisible = true }
    override func orderOut(_ sender: Any?) { simulatedVisible = false }
}
