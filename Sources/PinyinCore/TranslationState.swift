import Foundation

public enum TranslationIssue: Sendable, Equatable {
    case modelsNotInstalled
    case failed
    case noCandidates
    case engineUnavailable
}

/// A single state replaces the independent translation string and readiness flag.
public enum TranslationState: Sendable, Equatable {
    case notRequired
    case pending
    case ready(String)
    case unavailable(TranslationIssue)
}

/// Presentation data is separate from the immutable engine result.
public struct CandidateRow: Sendable, Equatable {
    public let candidate: Candidate
    public var translation: TranslationState

    public init(candidate: Candidate, translation: TranslationState? = nil) {
        self.candidate = candidate
        self.translation = translation ?? (Self.containsHan(candidate.text) ? .pending : .notRequired)
    }

    public var text: String { candidate.text }
    public var needsTranslation: Bool { Self.containsHan(text) }

    /// Only a successful, nonblank translation of a Han candidate can be spoken.
    public var speechText: String? {
        guard needsTranslation, case .ready(let value) = translation else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    public var translationText: String {
        switch translation {
        case .notRequired: return ""
        case .pending: return "等待本地翻译"
        case .ready(let value): return value
        case .unavailable(.modelsNotInstalled): return "未安装中英离线语言包"
        case .unavailable(.failed): return "本地翻译暂不可用"
        case .unavailable(.noCandidates): return "暂无候选，请检查拼音"
        case .unavailable(.engineUnavailable): return "苹果拼音暂不可用"
        }
    }

    private static func containsHan(_ text: String) -> Bool {
        text.range(of: "\\p{Han}", options: .regularExpression) != nil
    }
}
