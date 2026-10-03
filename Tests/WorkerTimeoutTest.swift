import Foundation
@main
struct WorkerTimeoutTest {
    static func main() throws {
        let worker = PinyinWorker(workerRoot: URL(fileURLWithPath: CommandLine.arguments[1]))
        let start = DispatchTime.now().uptimeNanoseconds
        do {
            _ = try worker.candidates(for: "p")
            preconditionFailure("Unresponsive worker must time out")
        } catch {}
        let seconds = Double(DispatchTime.now().uptimeNanoseconds - start) / 1e9
        precondition(seconds >= 6 && seconds < 9 && worker.processIdentifier == nil)
        print(String(format: "PASS: stalled worker times out, bounded retry and forced child cleanup in %.2f s", seconds))
    }
}
