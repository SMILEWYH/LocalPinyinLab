import AppKit
import InputMethodKit
import Carbon

@objc(LocalPinyinInputController)
@MainActor
final class InputController: IMKInputController {
    private var mode: InputMode = .chinesePinyin
    private var composition = CompositionState()
    private var documentContext = ""
    private var rows: [Candidate] = []
    private var page = 0
    private var highlighted = 0
    private var generation = 0
    private var pending: Task<Void, Never>?
    private var pageTranslation: Task<Void, Never>?
    private var queuedSelection: Int?
    private var candidatePanel: CandidatePanel?
    private var currentClient: (any IMKTextInput)?
    private let translator = AppleTranslator()
    private var speaker: EnglishSpeaker?
    private var speechStatus: String?

    override func activateServer(_ sender: Any!) {
        NSLog("LocalPinyin lifecycle: input controller activated")
        super.activateServer(sender)
        PinyinSession.shared.warm()
    }

    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event, event.type == .keyDown, let client = sender as? any IMKTextInput else { return false }
        guard !IsSecureEventInputEnabled() else { clear(); return false }
        currentClient = client
        if mode == .chinesePinyin, !composition.isEmpty, EnglishSpeaker.matches(event) {
            // Holding the key must not continually restart speech. No commit or mutation of pinyin.
            if !event.isARepeat { speakHighlighted(client) }
            return true
        }
        if event.keyCode == 49 && event.modifierFlags.contains([.control, .shift]) {
            if !composition.isEmpty { commit(composition.markedText, client: client) }
            mode = mode == .chinesePinyin ? .englishDirect : .chinesePinyin
            return true
        }
        guard mode == .chinesePinyin, event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return false }
        if event.keyCode == 53 && !composition.isEmpty { reset(client); return true }
        if event.keyCode == 51 && !composition.isEmpty { composition.backspace(); refresh(client); return true }
        // Restore the most recently selected segment for correction without losing its suffix.
        if event.keyCode == 123 && composition.undoSelection() { refresh(client); return true }
        // Return commits the visible composition literally, even while candidates are loading.
        // Consume this event so it does not also insert a newline into the host document.
        if (event.keyCode == 36 || event.keyCode == 76) && !composition.isEmpty {
            commit(composition.markedText, client: client)
            return true
        }
        if event.keyCode == 49 && !composition.isEmpty {
            select(page * 9 + highlighted, client: client)
            return true
        }
        let text = event.characters ?? ""
        if !composition.isEmpty, let digit = Int(text), (1...9).contains(digit) {
            select(page * 9 + digit - 1, client: client)
            return true
        }
        if !composition.isEmpty && (event.keyCode == 121 || event.keyCode == 116) {
            stopSpeech()
            page = min(max(0, page + (event.keyCode == 121 ? 1 : -1)), max(0, (rows.count - 1) / 9))
            highlighted = 0
            show(client)
            translateVisiblePage(client)
            return true
        }
        if !composition.isEmpty && (event.keyCode == 125 || event.keyCode == 126) && !rows.isEmpty {
            stopSpeech()
            let index = min(max(0, page * 9 + highlighted + (event.keyCode == 125 ? 1 : -1)), rows.count - 1)
            page = index / 9
            highlighted = index % 9
            show(client)
            translateVisiblePage(client)
            return true
        }
        if !text.isEmpty && text.unicodeScalars.allSatisfy({ (97...122).contains($0.value) || $0.value == 39 }) {
            guard composition.inputCount + text.count <= 128 else { return true }
            if composition.isEmpty { documentContext = precedingContext(client) }
            composition.pending += text
            refresh(client)
            return true
        }
        if !composition.isEmpty { commit(composition.markedText, client: client) }
        return false
    }

    private func precedingContext(_ client: any IMKTextInput) -> String {
        // Requested contextual conversion: only a bounded prefix at the caret, in memory.
        // IMK clients may not support document access; nil/NSNotFound means no context.
        guard !IsSecureEventInputEnabled() else { return "" }
        let selection = client.selectedRange()
        guard selection.location != NSNotFound, selection.location > 0 else { return "" }
        let length = min(128, selection.location)
        let range = NSRange(location: selection.location - length, length: length)
        guard let text = client.attributedSubstring(from: range)?.string else { return "" }
        return ApplePinyinEngine.boundedContext(text)
    }

    private func select(_ index: Int, client: any IMKTextInput) {
        guard rows.indices.contains(index) else {
            if pending != nil { queuedSelection = index }
            return
        }
        guard composition.choose(rows[index]) else { return }
        if composition.pending.isEmpty { commit(composition.selectedText, client: client) }
        else { refresh(client) }
    }

    private func refresh(_ client: any IMKTextInput) {
        stopSpeech()
        pending?.cancel()
        pending = nil
        pageTranslation?.cancel()
        queuedSelection = nil
        generation += 1
        rows = []
        page = 0
        highlighted = 0
        let marked = composition.markedText
        client.setMarkedText(marked, selectionRange: NSRange(location: marked.utf16.count, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        guard !composition.pending.isEmpty else { candidatePanel?.hide(); return }
        candidatePanel?.showLoading(pinyin: marked)
        let query = composition.pending
        let context = ApplePinyinEngine.boundedContext(documentContext + composition.selectedText)
        let version = generation
        pending = Task { @MainActor [weak self] in
            do {
                let result = try await PinyinSession.shared.candidates(for: query, context: context)
                guard let self, self.generation == version, !Task.isCancelled else { return }
                self.pending = nil
                self.rows = result.isEmpty ? [Candidate(text: query, translation: "暂无候选，请检查拼音", consumedCount: query.count)] : result
                if let selection = self.queuedSelection {
                    self.queuedSelection = nil
                    self.select(selection, client: client)
                    return
                }
                self.show(client)
                self.translateVisiblePage(client)
            } catch {
                guard let self, self.generation == version, !Task.isCancelled else { return }
                self.pending = nil
                self.queuedSelection = nil
                self.rows = [Candidate(text: query, translation: "苹果拼音暂不可用", consumedCount: query.count)]
                self.show(client)
            }
        }
    }

    private func translateVisiblePage(_ client: any IMKTextInput) {
        pageTranslation?.cancel()
        let indices = Array(rows.indices.dropFirst(page * 9).prefix(9)).filter { rows[$0].needsTranslation }
        guard !indices.isEmpty else { return }
        let sources = indices.map { rows[$0].text }
        let version = generation
        let requestedPage = page
        pageTranslation = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let installed = await self.translator.status() == .installed
                let translated = installed ? try await self.translator.translate(sources) : sources.map { _ in "未安装中英离线语言包" }
                guard !Task.isCancelled, self.generation == version, self.page == requestedPage else { return }
                let oldSpeech = EnglishSpeaker.selectedText(rows: self.rows, page: self.page, highlighted: self.highlighted)
                for (index, translation) in zip(indices, translated) {
                    self.rows[index].translation = translation
                    self.rows[index].translationReady = installed
                }
                if oldSpeech != EnglishSpeaker.selectedText(rows: self.rows, page: self.page, highlighted: self.highlighted) { self.stopSpeech() }
                self.speechStatus = nil
            } catch {
                guard !Task.isCancelled, self.generation == version, self.page == requestedPage else { return }
                self.stopSpeech()
                for index in indices {
                    self.rows[index].translation = "本地翻译暂不可用"
                    self.rows[index].translationReady = false
                }
            }
            self.show(client)
        }
    }

    private func show(_ client: any IMKTextInput) {
        guard !rows.isEmpty else { candidatePanel?.hide(); return }
        var anchor = NSRect.zero
        _ = client.attributes(forCharacterIndex: 0, lineHeightRectangle: &anchor)
        if anchor == .zero { anchor = NSRect(origin: NSEvent.mouseLocation, size: NSSize(width: 0, height: 16)) }
        if candidatePanel == nil { candidatePanel = CandidatePanel() }
        candidatePanel?.show(rows: Array(rows.dropFirst(page * 9).prefix(9)), pinyin: composition.markedText, selected: highlighted, page: page, totalPages: max(1, (rows.count + 8) / 9), anchor: anchor, status: speechStatus)
    }

    private func speakHighlighted(_ client: any IMKTextInput) {
        stopSpeech()
        guard let text = EnglishSpeaker.selectedText(rows: rows, page: page, highlighted: highlighted) else {
            speechStatus = "当前项尚无可朗读译文"
            show(client)
            return
        }
        if speaker == nil { speaker = EnglishSpeaker() }
        if speaker?.speak(text) != true { speechStatus = "未找到本地英语声音" }
        show(client)
    }

    private func stopSpeech() {
        speaker?.stop()
        speechStatus = nil
    }

    private func commit(_ text: String, client: any IMKTextInput) {
        client.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
        clear()
    }
    private func reset(_ client: any IMKTextInput) {
        client.setMarkedText("", selectionRange: NSRange(location: 0, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        clear()
    }
    private func clear() {
        stopSpeech()
        pending?.cancel(); pending = nil; pageTranslation?.cancel(); pageTranslation = nil
        generation += 1; composition = CompositionState(); documentContext = ""; queuedSelection = nil
        rows = []; page = 0; highlighted = 0; candidatePanel?.hide()
    }
    override func deactivateServer(_ sender: Any!) {
        NSLog("LocalPinyin lifecycle: input controller deactivated")
        if let client = currentClient, !composition.isEmpty { commit(composition.markedText, client: client) }
        clear()
        currentClient = nil
    }
}
