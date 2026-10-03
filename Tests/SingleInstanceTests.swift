import Foundation

@main struct SingleInstanceTests {
    static func main() throws {
        let args = CommandLine.arguments
        if args.count == 3 && args[1] == "--attempt" {
            let lock = try SingleInstanceLock.acquire(in: URL(fileURLWithPath: args[2]))
            print(lock == nil ? "busy" : "acquired")
            withExtendedLifetime(lock) {}
            return
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        func attempt() throws -> String {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: args[0])
            process.arguments = ["--attempt", directory.path]
            let pipe = Pipe(); process.standardOutput = pipe
            try process.run()
            let result = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            precondition(process.terminationStatus == 0)
            return String(decoding: result, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        var lock = try SingleInstanceLock.acquire(in: directory)
        precondition(lock != nil)
        let whileHeld = try attempt()
        precondition(whileHeld == "busy")
        withExtendedLifetime(lock) {}
        lock = nil
        let afterRelease = try attempt()
        precondition(afterRelease == "acquired")
        print("PASS: second process excluded; lock released on owner exit/lifetime end")
    }
}
