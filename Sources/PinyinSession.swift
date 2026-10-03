import Foundation
import Darwin

// All Process/pipe access is confined to one dedicated queue, never the main actor.
final class PinyinSession: @unchecked Sendable {
    static let shared = PinyinSession(workerRoot: Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/Worker"))
    private let queue = DispatchQueue(label: "local.pinyinlab.worker", qos: .userInteractive)
    private let worker: PinyinWorker

    init(workerRoot: URL) { worker = PinyinWorker(workerRoot: workerRoot) }
    deinit { worker.stop() }

    func warm() {
        queue.async { [self] in
            do { try worker.start() } catch { worker.stop() }
        }
    }

    func candidates(for pinyin: String, context: String = "") async throws -> [Candidate] {
        let cancellation = QueryCancellation()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                queue.async { [self] in
                    do {
                        try cancellation.check()
                        let result = try worker.candidates(for: pinyin, context: context)
                        try cancellation.check()
                        continuation.resume(returning: result)
                    } catch { continuation.resume(throwing: error) }
                }
            }
        } onCancel: { cancellation.cancel() }
    }

    func shutdown() async {
        await withCheckedContinuation { continuation in
            queue.async { [self] in worker.stop(); continuation.resume() }
        }
    }
}

private final class QueryCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    func check() throws {
        lock.lock(); let value = cancelled; lock.unlock()
        if value { throw CancellationError() }
    }
}

// Synchronous transport used only on PinyinSession.queue (or isolated test code).
final class PinyinWorker {
    private let workerRoot: URL
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var buffer = Data()
    var processIdentifier: Int32? { process?.isRunning == true ? process?.processIdentifier : nil }

    init(workerRoot: URL) { self.workerRoot = workerRoot }
    deinit { stop() }

    func start() throws {
        if process?.isRunning == true { return }
        stop()
        let child = Process()
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        child.executableURL = URL(fileURLWithPath: "/usr/bin/sandbox-exec")
        child.arguments = ["-D", "WORKER_ROOT=" + workerRoot.path, "-f", workerRoot.appendingPathComponent("pinyin.sb").path,
                           workerRoot.appendingPathComponent("pinyin-worker").path, "--serve"]
        child.standardInput = stdinPipe
        child.standardOutput = stdoutPipe
        child.standardError = FileHandle.nullDevice
        try child.run()
        // A dead child must produce a recoverable write error, not SIGPIPE in the IME.
        _ = fcntl(stdinPipe.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        process = child
        input = stdinPipe.fileHandleForWriting
        output = stdoutPipe.fileHandleForReading
        do {
            let response = try JSONDecoder().decode(Ready.self, from: readLine())
            guard response.ready else { throw ApplePinyinEngine.EngineError.unavailable }
        } catch { stop(); throw error }
    }

    func candidates(for pinyin: String, context: String = "") throws -> [Candidate] {
        for attempt in 0..<2 {
            do {
                try start()
                var data = try ApplePinyinEngine.requestData(pinyin: pinyin, context: context)
                data.append(10)
                try input?.write(contentsOf: data)
                return try ApplePinyinEngine.decodeCandidates(readLine(), pinyin: pinyin)
            } catch {
                stop()
                if attempt == 1 { throw error }
            }
        }
        throw ApplePinyinEngine.EngineError.unavailable
    }

    func stop() {
        try? input?.close()
        try? output?.close()
        input = nil
        output = nil
        buffer.removeAll(keepingCapacity: false)
        if let process, process.isRunning {
            process.terminate()
            let deadline = DispatchTime.now().uptimeNanoseconds + 100_000_000
            while process.isRunning && DispatchTime.now().uptimeNanoseconds < deadline { usleep(2_000) }
            if process.isRunning { _ = Darwin.kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit()
        }
        process = nil
    }

    private func readLine() throws -> Data {
        guard let output else { throw ApplePinyinEngine.EngineError.unavailable }
        let deadline = DispatchTime.now().uptimeNanoseconds + 3_000_000_000
        while true {
            if let end = buffer.firstIndex(of: 10) {
                let frame = Data(buffer[..<end])
                buffer.removeSubrange(...end)
                return frame
            }
            let now = DispatchTime.now().uptimeNanoseconds
            guard now < deadline, buffer.count < 4_194_304 else { throw ApplePinyinEngine.EngineError.unavailable }
            var descriptor = pollfd(fd: output.fileDescriptor, events: Int16(POLLIN), revents: 0)
            let result = poll(&descriptor, 1, Int32(max(1, (deadline - now) / 1_000_000)))
            if result < 0 && errno == EINTR { continue }
            guard result > 0 else { throw ApplePinyinEngine.EngineError.unavailable }
            var bytes = [UInt8](repeating: 0, count: 8192)
            let count = Darwin.read(output.fileDescriptor, &bytes, bytes.count)
            if count < 0 && errno == EINTR { continue }
            guard count > 0 else { throw ApplePinyinEngine.EngineError.unavailable }
            buffer.append(contentsOf: bytes.prefix(count))
        }
    }
    private struct Ready: Decodable { let ready: Bool }
}
