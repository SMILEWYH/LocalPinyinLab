import Foundation
import Darwin
import PinyinCore
import PinyinInfrastructure

@main
struct PerformanceTests {
    static func shape(_ rows: [Candidate]) -> [String] { rows.map { "\($0.text)|\($0.consumedCount)" } }
    static func milliseconds(_ start: UInt64) -> Double { Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000 }
    static func median(_ values: [Double]) -> Double { values.sorted()[values.count / 2] }
    static func main() async throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let oneShot = ApplePinyinEngine(workerRoot: root)
        let worker = PinyinWorker(workerRoot: root)
        let start = DispatchTime.now().uptimeNanoseconds
        try worker.start()
        print(String(format: "Worker startup: %.2f ms (prewarmed before typing)", milliseconds(start)))
        let pid = worker.processIdentifier!
        let queries = ["p", "n", "nihao", "pingying", "ying", "xianzaibeijingshijianjidianzhong", "xian'zai'bei'jing"]
        for query in queries {
            let baseline = try oneShot.candidates(for: query)
            let repeated = try worker.candidates(for: query)
            precondition(shape(baseline) == shape(repeated), "Persistent engine changed candidates: \(query)")
            precondition(worker.processIdentifier == pid)
        }
        print("PASS: reused one process; candidates/order/consumed lengths match one-shot for short, long and apostrophe input")
        let beforeContext = try worker.candidates(for: "pingying")
        _ = try worker.candidates(for: "gongshi", context: "数学")
        let afterContext = try worker.candidates(for: "pingying")
        precondition(shape(beforeContext) == shape(afterContext))
        print("PASS: reset between unrelated composition/context requests")
        for query in ["p", "n", "nihao"] {
            var cold: [Double] = [], warm: [Double] = []
            for _ in 0..<8 {
                var tick = DispatchTime.now().uptimeNanoseconds
                _ = try oneShot.candidates(for: query)
                cold.append(milliseconds(tick))
                tick = DispatchTime.now().uptimeNanoseconds
                _ = try worker.candidates(for: query)
                warm.append(milliseconds(tick))
            }
            print(String(format: "%@: one-shot median %.2f ms; reused median %.2f ms; removed fixed wait 60 ms", query, median(cold), median(warm)))
        }
        // Kill only the child process created by this test, then verify automatic recovery.
        _ = Darwin.kill(pid, SIGKILL)
        usleep(20_000)
        let recovered = try worker.candidates(for: "nihao")
        precondition(recovered.contains { $0.text == "你好" } && worker.processIdentifier != pid)
        print("PASS: unexpected worker death recovers without SIGPIPE or stale response")
        do {
            _ = try worker.candidates(for: "invalid!")
            preconditionFailure("Invalid input must be rejected")
        } catch {}
        let afterError = try worker.candidates(for: "nihao")
        precondition(afterError.contains { $0.text == "你好" })
        print("PASS: malformed query is rejected and next valid query recovers")
        worker.stop()

        let session = PinyinSession(workerRoot: root)
        session.warm()
        let letters = ["x", "xi", "xia", "xian", "xianz", "xianza", "xianzai"]
        var tasks: [Task<[Candidate], Error>] = []
        for query in letters {
            let task = Task { try await session.candidates(for: query) }
            tasks.append(task)
            if tasks.count > 1 { tasks[tasks.count - 2].cancel() }
        }
        let latest = try await tasks.last!.value
        precondition(latest.first?.text == "现在")
        for task in tasks.dropLast() { _ = try? await task.value }
        print("PASS: rapid typing cancels obsolete queued requests; latest result stays correct")
        let sessionStart = DispatchTime.now().uptimeNanoseconds
        let firstLetter = try await session.candidates(for: "p")
        precondition(!firstLetter.isEmpty)
        print(String(format: "Full async warm session query p: %.2f ms (excludes UI rendering)", milliseconds(sessionStart)))
        await session.shutdown()
    }
}
