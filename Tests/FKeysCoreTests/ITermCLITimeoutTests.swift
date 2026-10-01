import Foundation
import Testing
@testable import FKeysCore

private func stub(_ body: String) throws -> String {
    let path = NSTemporaryDirectory() + "it2-stub-\(UUID().uuidString).sh"
    try "#!/bin/sh\n\(body)\n".write(toFile: path, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
    return path
}

private func readPID(_ file: String) throws -> pid_t {
    let text = try String(contentsOfFile: file, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
    return try #require(pid_t(text))
}

/// A script written moments ago can fail to launch with ETXTBSY when another
/// test forks while the file is open for write. `run` then returns nil without
/// ever starting the child, so retry until the child has written its pid.
private func runUntilStarted(_ path: String, _ pidFile: String) -> String? {
    var result: String?
    for _ in 0..<10 {
        result = ITermCLI(binary: path, timeout: 0.4).run(["x"])
        if FileManager.default.fileExists(atPath: pidFile) { break }
    }
    return result
}

/// `kill(pid, 0)` also succeeds on an unreaped zombie, so poll until ESRCH.
private func waitUntilGone(_ pid: pid_t, within seconds: TimeInterval) -> Bool {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        if kill(pid, 0) != 0 { return true }
        Thread.sleep(forTimeInterval: 0.02)
    }
    return kill(pid, 0) != 0
}

@Suite struct ITermCLITimeoutTests {
    @Test func aHungIt2IsReportedAsFailure() throws {
        let path = try stub("exec sleep 30")
        defer { try? FileManager.default.removeItem(atPath: path) }
        let cli = ITermCLI(binary: path, timeout: 0.3)
        let start = Date()
        #expect(cli.liveSessionUUIDs().isEmpty)
        #expect(cli.frontmostWindowTabs() == nil)
        #expect(cli.tabID(forSessionUUID: "x") == nil)
        #expect(Date().timeIntervalSince(start) < 3)
    }

    /// SIGTERM alone must remove the process, well before the 0.5 s SIGKILL
    /// escalation could.
    @Test func aHungIt2IsTerminatedNotJustAbandoned() throws {
        let pidFile = NSTemporaryDirectory() + "it2-pid-\(UUID().uuidString)"
        let path = try stub("echo $$ > '\(pidFile)'\nexec sleep 30")
        defer { try? FileManager.default.removeItem(atPath: path); try? FileManager.default.removeItem(atPath: pidFile) }
        #expect(runUntilStarted(path, pidFile) == nil)
        let pid = try readPID(pidFile)
        #expect(waitUntilGone(pid, within: 0.35))
    }

    /// A child that ignores SIGTERM must still be gone: only SIGKILL removes it.
    @Test func aChildIgnoringSigtermIsKilled() throws {
        let pidFile = NSTemporaryDirectory() + "it2-pid-\(UUID().uuidString)"
        let path = try stub("trap '' TERM\necho $$ > '\(pidFile)'\nwhile :; do sleep 0.1; done")
        defer { try? FileManager.default.removeItem(atPath: path); try? FileManager.default.removeItem(atPath: pidFile) }
        #expect(runUntilStarted(path, pidFile) == nil)
        let pid = try readPID(pidFile)
        Thread.sleep(forTimeInterval: 0.2)
        #expect(kill(pid, 0) == 0, "SIGTERM was ignored, so the process must still be alive before the escalation")
        #expect(waitUntilGone(pid, within: 2))
    }

    @Test func aChildHoldingThePipeOpenDoesNotBlockPastTheTimeout() throws {
        let path = try stub("sleep 30 &\nwait")
        defer { try? FileManager.default.removeItem(atPath: path) }
        let start = Date()
        #expect(ITermCLI(binary: path, timeout: 0.3).run(["x"]) == nil)
        #expect(Date().timeIntervalSince(start) < 3)
    }

    @Test func aFastIt2StillReturnsItsOutput() throws {
        let path = try stub("echo hello")
        defer { try? FileManager.default.removeItem(atPath: path) }
        #expect(ITermCLI(binary: path, timeout: 5).run(["x"]) == "hello\n")
    }
}
