import PinyinCore

/// User-facing copy belongs to presentation; core exposes translation state only.
extension CandidateRow {
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

    func accessibilityText(index: Int) -> String {
        let candidate = "第 \(index + 1) 项，\(text)"
        switch translation {
        case .notRequired: return candidate
        case .ready: return candidate + "，英文：" + translationText
        default: return candidate + "，" + translationText
        }
    }
}
