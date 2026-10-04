import AppKit
import PinyinCore
import PinyinApplication
import PinyinInfrastructure
import PinyinPresentation

@MainActor enum DemoRunner {
    private static var panel: CandidatePanel?

    static func run(arguments args: [String]) async throws {
        let sample = args.contains("--long-sample") ? "xianzaibeijingshijianjidianzhong" : (args.contains("--candidate-sample") ? "pingying" : "xiexie")
        let engine = ApplePinyinEngine(workerRoot: Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/Worker"))
        let results = try await Task.detached { try engine.candidates(for: sample) }.value
        var candidates = CandidateList()
        candidates.replace(results.map { CandidateRow(candidate: $0) })
        let indices = candidates.visibleIndices.filter { candidates.rows[$0].needsTranslation }
        let translator = AppleTranslator()
        do {
            let translations = try await translator.translate(indices.map { candidates.rows[$0].text })
            for (index, translation) in zip(indices, translations) {
                _ = candidates.updateTranslation(at: index, source: candidates.rows[index].text, state: .ready(translation))
            }
        } catch TranslationFailure.modelsNotInstalled {
            for index in indices {
                _ = candidates.updateTranslation(at: index, source: candidates.rows[index].text, state: .unavailable(.modelsNotInstalled))
            }
        } catch {
            for index in indices {
                _ = candidates.updateTranslation(at: index, source: candidates.rows[index].text, state: .unavailable(.failed))
            }
        }
        if let index = args.firstIndex(of: "--snapshot"), args.indices.contains(index + 1) {
            let view = CandidateView(rows: candidates.visibleRows, pinyin: sample, highlighted: 0, footer: "1/\(max(1, candidates.totalPages))")
            try view.writePNG(to: URL(fileURLWithPath: args[index + 1]))
            print("Real Apple candidates: " + results.map(\.text).joined(separator: ", "))
            exit(0)
        }
        panel = CandidatePanel()
        panel?.show(rows: candidates.visibleRows, pinyin: sample, selected: 0, page: 0, totalPages: max(1, candidates.totalPages),
                    anchor: NSRect(x: NSScreen.main?.visibleFrame.midX ?? 500, y: NSScreen.main?.visibleFrame.midY ?? 500, width: 0, height: 16))
    }
}
