import Foundation
import IOKit
import IOKit.hidsystem

/// Accesses the system Caps Lock state. All connections are scoped to one call.
/// A write may generate modifier events; the input adapter must establish its
/// expected Caps Lock baseline before requesting a change.
@MainActor
public final class CapsLockController {
    public init() {}

    public func isEnabled() -> Bool? {
        guard let connection = openConnection() else { return nil }
        defer { IOServiceClose(connection) }
        return readState(connection)
    }

    /// True means the state already matched or the system API accepted the
    /// request. Modifier flags and keyboard LEDs can update asynchronously;
    /// the caller must confirm the state with isEnabled() without blocking UI.
    @discardableResult public func requestEnabled(_ enabled: Bool) -> Bool {
        guard let connection = openConnection() else { return false }
        defer { IOServiceClose(connection) }
        guard let current = readState(connection) else { return false }
        if current == enabled { return true }
        let result = IOHIDSetModifierLockState(connection, Int32(kIOHIDCapsLockState), enabled)
        guard result == KERN_SUCCESS else {
            NSLog("LocalPinyin Caps Lock: cannot set state (0x%08x)", result)
            return false
        }
        return true
    }

    private func openConnection() -> io_connect_t? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(kIOHIDSystemClass))
        guard service != IO_OBJECT_NULL else {
            NSLog("LocalPinyin Caps Lock: IOHIDSystem is unavailable")
            return nil
        }
        defer { IOObjectRelease(service) }
        var connection: io_connect_t = IO_OBJECT_NULL
        let result = IOServiceOpen(service, mach_task_self_, UInt32(kIOHIDParamConnectType), &connection)
        guard result == KERN_SUCCESS else {
            NSLog("LocalPinyin Caps Lock: cannot open IOHIDSystem (0x%08x)", result)
            return nil
        }
        return connection
    }

    private func readState(_ connection: io_connect_t) -> Bool? {
        var enabled = false
        let result = IOHIDGetModifierLockState(connection, Int32(kIOHIDCapsLockState), &enabled)
        guard result == KERN_SUCCESS else {
            NSLog("LocalPinyin Caps Lock: cannot read state (0x%08x)", result)
            return nil
        }
        return enabled
    }
}
