import PinyinCore

/// Shared by this input method's controllers, never by other system input sources.
@MainActor public final class InputModeState {
    public private(set) var mode: InputMode = .chinesePinyin
    private var capsLock: Bool?

    public init() {}

    /// Activation establishes a baseline: keys pressed in another input source
    /// must not change this input method's remembered mode.
    public func synchronizeCapsLock(_ enabled: Bool) { capsLock = enabled }

    @discardableResult public func observeCapsLock(_ enabled: Bool) -> Bool {
        let previous = capsLock
        capsLock = enabled
        guard let previous, previous != enabled else { return false }
        toggle()
        return true
    }

    public func toggle() { mode = mode == .chinesePinyin ? .englishDirect : .chinesePinyin }
}
