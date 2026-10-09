import Darwin
import Foundation
import PinyinCore

/// A synchronous, single-owner transport. Callers must serialize all access.
/// PinyinSession supplies that serialization for the input service.
public final class PinyinWorker {
    private let workerRoot: URL
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var buffer = Data()

    public var processIdentifier: Int32? {
        process?.isRunning == true ? process?.processIdentifier : nil
    }

    public init(workerRoot: URL) { self.workerRoot = workerRoot }
    deinit { stop() }

    public func start() throws {
        try start(checkCancellation: {})
    }

    func start(checkCancellation: () throws -> Void) throws {
        try checkCancellation()
        if process?.isRunning == true, input != nil, output != nil { return }
        stop()
        // A child that has not finished exiting must remain tracked. Do not
        // launch another worker over an outstanding cleanup attempt.
        guard process == nil else { throw PinyinWorkerError.unavailable }
        let child = Process()
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        child.executableURL = URL(fileURLWithPath: "/usr/bin/sandbox-exec")
        child.arguments = ["-D", "WORKER_ROOT=" + workerRoot.path,
                           "-f", workerRoot.appendingPathComponent("pinyin.sb").path,
                           workerRoot.appendingPathComponent("pinyin-worker").path, "--serve"]
        child.standardInput = stdinPipe
        child.standardOutput = stdoutPipe
        child.standardError = FileHandle.nullDevice
        // A dead child must cause a recoverable write error, never SIGPIPE in the IME.
        guard fcntl(stdinPipe.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1) == 0 else {
            throw PinyinWorkerError.unavailable
        }
        try child.run()
        process = child
        input = stdinPipe.fileHandleForWriting
        output = stdoutPipe.fileHandleForReading
        do {
            try WorkerProtocol.decodeReady(readLine(checkCancellation: checkCancellation))
            try checkCancellation()
        } catch {
            stop()
            throw error
        }
    }

    public func candidates(for pinyin: String, context: String = "") throws -> [Candidate] {
        try candidates(for: pinyin, context: context, checkCancellation: {})
    }

    // Only the queue that owns this transport touches its process and pipes.
    // Cancellation is observed here rather than closing a pipe from another thread.
    func candidates(for pinyin: String, context: String, checkCancellation: () throws -> Void) throws -> [Candidate] {
        try checkCancellation()
        // Reject invalid queries before starting or restarting a child process.
        // The bounded request also fits into a pipe without a large blocking write.
        var request = try WorkerProtocol.requestData(pinyin: pinyin, context: context)
        request.append(10)
        for attempt in 0..<2 {
            do {
                try start(checkCancellation: checkCancellation)
                try checkCancellation()
                guard let input else { throw PinyinWorkerError.unavailable }
                try input.write(contentsOf: request)
                let result = try WorkerProtocol.decodeCandidates(readLine(checkCancellation: checkCancellation), pinyin: pinyin)
                try checkCancellation()
                return result
            } catch {
                // Discard all buffered bytes before a retry; a response can never
                // be reused for a different composition or a restarted process.
                stop()
                // A cancelled request must never restart its worker or retain a
                // partially read response for the next composition.
                if error is CancellationError { throw error }
                try checkCancellation()
                if attempt == 1 { throw error }
            }
        }
        throw PinyinWorkerError.unavailable
    }

    public func stop() {
        try? input?.close()
        try? output?.close()
        input = nil
        output = nil
        buffer.removeAll(keepingCapacity: false)
        if let process, process.isRunning {
            process.terminate()
            if !waitForExit(process, nanoseconds: 100_000_000) {
                _ = Darwin.kill(process.processIdentifier, SIGKILL)
                guard waitForExit(process, nanoseconds: 500_000_000) else {
                    NSLog("LocalPinyin: worker cleanup is still pending")
                    return
                }
            }
        }
        process = nil
    }

    private func waitForExit(_ child: Process, nanoseconds: UInt64) -> Bool {
        let deadline = DispatchTime.now().uptimeNanoseconds + nanoseconds
        while child.isRunning {
            // Foundation owns reaping; never compete with it through waitpid.
            // waitUntilExit can remain in a run loop after the child disappears,
            // so observe its status with a bound and also accept kernel ESRCH.
            if Darwin.kill(child.processIdentifier, 0) == -1, errno == ESRCH { return true }
            guard DispatchTime.now().uptimeNanoseconds < deadline else { return false }
            usleep(2_000)
        }
        return true
    }

    private func readLine(checkCancellation: () throws -> Void) throws -> Data {
        guard let output else { throw PinyinWorkerError.unavailable }
        let deadline = DispatchTime.now().uptimeNanoseconds + 3_000_000_000
        while true {
            try checkCancellation()
            if let frame = try WorkerProtocol.takeFrame(from: &buffer) { return frame }
            let now = DispatchTime.now().uptimeNanoseconds
            guard now < deadline else { throw PinyinWorkerError.timedOut }
            var descriptor = pollfd(fd: output.fileDescriptor, events: Int16(POLLIN), revents: 0)
            // Short waits make cancellation responsive without sharing descriptors
            // across threads; the original absolute response deadline still applies.
            let waitMilliseconds = min(50, max(1, (deadline - now) / 1_000_000))
            let result = poll(&descriptor, 1, Int32(waitMilliseconds))
            if result < 0 && errno == EINTR { continue }
            if result == 0 { continue }
            guard result > 0 else { throw PinyinWorkerError.unavailable }
            var bytes = [UInt8](repeating: 0, count: 8192)
            let count = Darwin.read(output.fileDescriptor, &bytes, bytes.count)
            if count < 0 && errno == EINTR { continue }
            guard count > 0 else { throw PinyinWorkerError.unavailable }
            buffer.append(contentsOf: bytes.prefix(count))
        }
    }
}
