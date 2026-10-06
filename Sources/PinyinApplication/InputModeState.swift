import PinyinCore

/// Shared by this input method's controllers, never by other system input sources.
@MainActor public final class InputModeState {
    public private(set) var mode: InputMode = .chinesePinyin
    public private(set) var isUppercaseLocked = false
    private(set) var revision: UInt64 = 0
    private var capsLock: Bool?

    public init() {}

    /// Activation and secure-input recovery adopt the real lock state. A process
    /// restart or a change made in another input source cannot invert our mode.
    public func synchronizeCapsLock(_ enabled: Bool) {
        capsLock = enabled
        _ = applyCapsLock(enabled)
    }

    /// The adapter records a lock value that it writes for a shortcut or an
    /// uppercase transition. Its echoed event must not replay that transition.
    public func acknowledgeCapsLock(_ enabled: Bool) { capsLock = enabled }

    @discardableResult public func observeCapsLock(_ enabled: Bool, modifiers: KeyModifiers = [],
                                                  allowsUppercaseToggle: Bool = true) -> Bool {
        let previous = capsLock
        capsLock = enabled
        guard previous != enabled else { return false }
        // Only an actual Shift+Caps edge expresses an uppercase command. A
        // keyDown may recover a missed lock change, but its Shift is unrelated.
        if previous != nil, allowsUppercaseToggle, modifiers == [.shift] {
            isUppercaseLocked.toggle()
            mode = .englishDirect
            revision &+= 1
            return true
        }
        return applyCapsLock(enabled)
    }

    @discardableResult private func applyCapsLock(_ enabled: Bool) -> Bool {
        let nextMode: InputMode = enabled ? .englishDirect : .chinesePinyin
        let nextUppercase = enabled && isUppercaseLocked
        guard mode != nextMode || isUppercaseLocked != nextUppercase else { return false }
        mode = nextMode
        isUppercaseLocked = nextUppercase
        revision &+= 1
        return true
    }

    public func toggle() {
        mode = mode == .chinesePinyin ? .englishDirect : .chinesePinyin
        if mode == .chinesePinyin { isUppercaseLocked = false }
        revision &+= 1
    }
}
