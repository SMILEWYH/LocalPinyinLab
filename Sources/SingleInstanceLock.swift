import Foundation
import Darwin

// Hold before registering the IMK connection. Launch Services may start the app
// concurrently with an update/restart; a second process must not register again.
final class SingleInstanceLock {
    private let descriptor: Int32
    private init(descriptor: Int32) { self.descriptor = descriptor }
    deinit { close(descriptor) }

    static func acquire(in directory: URL) throws -> SingleInstanceLock? {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        let path = directory.appendingPathComponent("input-service.lock").path
        let descriptor = open(path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        if flock(descriptor, LOCK_EX | LOCK_NB) != 0 {
            let error = errno
            close(descriptor)
            if error == EWOULDBLOCK || error == EAGAIN { return nil }
            throw POSIXError(POSIXErrorCode(rawValue: error) ?? .EIO)
        }
        // Never unlink: every launcher must lock the same inode, even after a crash.
        return SingleInstanceLock(descriptor: descriptor)
    }
}
