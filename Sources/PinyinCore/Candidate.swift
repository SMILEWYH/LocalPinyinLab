import Foundation

/// An engine result. Consumption is validated against the current composition when selected.
public struct Candidate: Sendable, Equatable {
    public let text: String
    public let consumedCount: Int

    public init(text: String, consumedCount: Int) {
        self.text = text
        self.consumedCount = consumedCount
    }
}

public enum InputMode: Sendable, Equatable {
    case chinesePinyin
    case englishDirect
}
