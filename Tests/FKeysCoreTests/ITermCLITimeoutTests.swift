import Foundation
import Testing
@testable import FKeysCore

private func stub(_ body: String) throws -> String {
    let path = NSTemporaryDirectory() + "it2-stub-\(UUID().uuidString).sh"
    try "#!/bin/sh\n\(body)\n".write(toFile: path, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
    return path
}

@Suite struct ITermCLITimeoutTests {
    @Test func aHungIt2IsKilledAndReportedAsFailure() throws {
        let path = try stub("exec sleep 30")
        defer { try? FileManager.default.removeItem(atPath: path) }
        let cli = ITermCLI(binary: path, timeout: 0.3)
        let start = Date()
        #expect(cli.liveSessionUUIDs().isEmpty)
        #expect(cli.frontmostWindowTabs() == nil)
        #expect(cli.tabID(forSessionUUID: "x") == nil)
        #expect(Date().timeIntervalSince(start) < 3)
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
