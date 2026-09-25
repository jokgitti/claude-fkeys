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

    /// The frontmost window's tabs, in `tab list --json` order. `nil` when
    /// iTerm is not running or either `it2` call fails — the caller must
    /// treat that as "unknown, keep the last derivation", never as "no tabs".
    ///
    /// `tab list --json` has no window argument, so a second window's tabs
    /// would be mixed in; `window list --json`'s first entry is what narrows
    /// the result to one window. `app get-focus` looked like the obvious way
    /// to do that narrowing, but its "Current window" line only resolves
    /// when iTerm.app is the OS-frontmost application — which is false for
    /// most of this daemon's runtime, since its whole point is switching to
    /// a background Claude session while another app (e.g. a browser) holds
    /// focus. Verified live: with iTerm running two Claude sessions and
    /// Slack frontmost, `app get-focus` printed "No current window" on every
    /// call, while `window list --json` returned the real window regardless.
    public func frontmostWindowTabs() -> [TabInfo]? {
        guard let windowOutput = run(["window", "list", "--json"]),
              let windowID = ITermParsing.firstWindowID(from: windowOutput),
              let listOutput = run(["tab", "list", "--json"]),
              let allTabs = ITermParsing.tabs(from: listOutput)
        else { return nil }
        return allTabs.filter { $0.windowID == windowID }
    }

    /// `nil` when the session is gone or `it2` fails.
    public func tabID(forSessionUUID uuid: String) -> String? {
        run(["session", "get-var", "tab.id", "-s", uuid]).flatMap(ITermParsing.tabID(from:))
    }

    /// F*n* focuses tab index n-1 of the current window. `tab goto` is
    /// 0-based and defaults to the current window, so this needs no uuid
    /// lookup and no window argument at all.
    public func gotoTab(_ index: Int) {
        _ = run(["tab", "goto", String(index)])
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
