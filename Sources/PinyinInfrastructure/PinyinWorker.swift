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
        if process?.isRunning == true { return }
        stop()
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
            try WorkerProtocol.decodeReady(readLine())
        } catch {
            stop()
            throw error
        }
    }

    public func candidates(for pinyin: String, context: String = "") throws -> [Candidate] {
        // Reject invalid queries before starting or restarting a child process.
        // The bounded request also fits into a pipe without a large blocking write.
        var request = try WorkerProtocol.requestData(pinyin: pinyin, context: context)
        request.append(10)
        for attempt in 0..<2 {
            do {
                try start()
                guard let input else { throw PinyinWorkerError.unavailable }
                try input.write(contentsOf: request)
                return try WorkerProtocol.decodeCandidates(readLine(), pinyin: pinyin)
            } catch {
                // Discard all buffered bytes before a retry; a response can never
                // be reused for a different composition or a restarted process.
                stop()
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
            let deadline = DispatchTime.now().uptimeNanoseconds + 100_000_000
            while process.isRunning && DispatchTime.now().uptimeNanoseconds < deadline {
                usleep(2_000)
            }
            if process.isRunning { _ = Darwin.kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit()
        }
        process = nil
    }

    private func readLine() throws -> Data {
        guard let output else { throw PinyinWorkerError.unavailable }
        let deadline = DispatchTime.now().uptimeNanoseconds + 3_000_000_000
        while true {
            if let frame = try WorkerProtocol.takeFrame(from: &buffer) { return frame }
            let now = DispatchTime.now().uptimeNanoseconds
            guard now < deadline else { throw PinyinWorkerError.timedOut }
            var descriptor = pollfd(fd: output.fileDescriptor, events: Int16(POLLIN), revents: 0)
            let result = poll(&descriptor, 1, Int32(max(1, (deadline - now) / 1_000_000)))
            if result < 0 && errno == EINTR { continue }
            if result == 0 { throw PinyinWorkerError.timedOut }
            guard result > 0 else { throw PinyinWorkerError.unavailable }
            var bytes = [UInt8](repeating: 0, count: 8192)
            let count = Darwin.read(output.fileDescriptor, &bytes, bytes.count)
            if count < 0 && errno == EINTR { continue }
            guard count > 0 else { throw PinyinWorkerError.unavailable }
            buffer.append(contentsOf: bytes.prefix(count))
        }
    }
}
