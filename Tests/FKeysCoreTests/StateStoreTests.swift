import Testing
import Foundation
@testable import FKeysCore

private func makeTempDir() throws -> URL {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("fkeys-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func write(_ text: String, to dir: URL, named name: String) throws {
    try text.write(to: dir.appendingPathComponent(name), atomically: true, encoding: .utf8)
}

private let uuidA = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
private let uuidB = "11111111-2222-3333-4444-555555555555"

@Test func readsStatesKeyedByUUID() throws {
    let dir = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    try write(#"{"state":"working","ts":1,"claude_session_id":"s1"}"#, to: dir, named: "\(uuidA).json")
    try write(#"{"state":"waiting","ts":2,"claude_session_id":"s2"}"#, to: dir, named: "\(uuidB).json")

    let states = StateStore(dir: dir).scan()
    #expect(states == [uuidA: .working, uuidB: .waiting])
}

@Test func toleratesAMissingClaudeSessionId() throws {
    let dir = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    try write(#"{"state":"idle","ts":1}"#, to: dir, named: "\(uuidA).json")
    #expect(StateStore(dir: dir).scan() == [uuidA: .idle])
}

@Test func skipsMalformedFilesWithoutLosingGoodOnes() throws {
    let dir = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    try write(#"{"state":"idle","ts":1}"#, to: dir, named: "\(uuidA).json")
    try write("{ this is not json", to: dir, named: "\(uuidB).json")
    #expect(StateStore(dir: dir).scan() == [uuidA: .idle])
}

@Test func skipsUnknownStateValues() throws {
    let dir = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    try write(#"{"state":"compiling","ts":1}"#, to: dir, named: "\(uuidA).json")
    #expect(StateStore(dir: dir).scan().isEmpty)
}

@Test func ignoresFilenamesThatAreNotSessionUUIDs() throws {
    let dir = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    try write(#"{"state":"idle","ts":1}"#, to: dir, named: "\(uuidA).json")
    try write(#"{"1":"\#(uuidA)"}"#, to: dir, named: "registry.json")
    try write(#"{"state":"idle","ts":1}"#, to: dir, named: "\(uuidA).json.tmp.4242")
    try write("log line", to: dir, named: "fkeysd.log")
    #expect(StateStore(dir: dir).scan() == [uuidA: .idle])
}

@Test func returnsEmptyForAMissingDirectory() {
    let dir = URL(fileURLWithPath: "/nonexistent/fkeys-\(UUID().uuidString)")
    #expect(StateStore(dir: dir).scan().isEmpty)
}
