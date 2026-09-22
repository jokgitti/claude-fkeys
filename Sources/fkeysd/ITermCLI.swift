import Foundation
import FKeysCore

/// Runs iTerm2's bundled `it2` CLI.
public struct ITermCLI: Sendable {
    public static let defaultBinary = "/Applications/iTerm.app/Contents/Resources/utilities/it2"

    public let binary: String

    public init(binary: String = ITermCLI.defaultBinary) {
        self.binary = binary
    }

    /// Empty when iTerm is not running or `it2` fails — the caller must treat
    /// that as "unknown", never as "every session died".
    public func liveSessionUUIDs() -> Set<String> {
        guard let output = run(["session", "list"]) else { return [] }
        return ITermParsing.sessionUUIDs(from: output)
    }

    public func focus(_ uuid: String) {
        _ = run(["session", "focus", uuid])
    }

    @discardableResult
    private func run(_ arguments: [String]) -> String? {
        guard FileManager.default.isExecutableFile(atPath: binary) else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
