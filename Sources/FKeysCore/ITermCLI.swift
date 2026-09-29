import Foundation

/// Runs iTerm2's bundled `it2` CLI.
public struct ITermCLI: Sendable {
    public static let defaultBinary = "/Applications/iTerm.app/Contents/Resources/utilities/it2"

    /// Every it2 call runs on the daemon's main queue, next to the keyboard
    /// keepalive. A call that outlives this is killed and reported as a failure.
    public static let defaultTimeout: TimeInterval = 2

    public let binary: String
    public let timeout: TimeInterval

    public init(binary: String = ITermCLI.defaultBinary, timeout: TimeInterval = ITermCLI.defaultTimeout) {
        self.binary = binary
        self.timeout = timeout
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
        guard let windowID = frontmostWindowID() else { return nil }
        return tabs(inWindow: windowID)
    }

    /// One `it2` call. `nil` on any failure.
    public func frontmostWindowID() -> String? {
        run(["window", "list", "--json"]).flatMap(ITermParsing.firstWindowID(from:))
    }

    /// One `it2` call. `nil` on any failure.
    public func tabs(inWindow windowID: String) -> [TabInfo]? {
        guard let output = run(["tab", "list", "--json"]),
              let allTabs = ITermParsing.tabs(from: output)
        else { return nil }
        return allTabs.filter { $0.windowID == windowID }
    }

    /// `nil` when the session is gone or `it2` fails.
    public func tabID(forSessionUUID uuid: String) -> String? {
        run(["session", "get-var", "tab.id", "-s", uuid]).flatMap(ITermParsing.tabID(from:))
    }

    /// Switches to tab `index` (0-based) of `window`. The window is passed
    /// explicitly because `tab goto`'s default, "current window", does not
    /// resolve reliably while iTerm is not the frontmost app (the same failure
    /// `app get-focus` had). `nil` falls back to that default: used only before
    /// any window id is known, where it is no worse than not passing one.
    public func gotoTab(_ index: Int, window: String?) {
        _ = run(Self.gotoArguments(index: index, window: window))
    }

    static func gotoArguments(index: Int, window: String?) -> [String] {
        var arguments = ["tab", "goto", String(index)]
        if let window { arguments += ["-w", window] }
        return arguments
    }

    /// `nil` on any failure, including a timeout, so callers treat a hung
    /// `it2` the same as a failed one: "unknown, change nothing".
    @discardableResult
    func run(_ arguments: [String]) -> String? {
        guard FileManager.default.isExecutableFile(atPath: binary) else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }

        // The read runs off-thread so a child that holds the pipe open after
        // being killed (a grandchild) cannot block the caller past the timeout.
        let box = ReadBox()
        let done = DispatchSemaphore(value: 0)
        let handle = pipe.fileHandleForReading
        DispatchQueue.global().async {
            box.data = handle.readDataToEndOfFile()
            done.signal()
        }
        guard done.wait(timeout: .now() + timeout) == .success else {
            process.terminate()
            let pid = process.processIdentifier
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
                if process.isRunning { kill(pid, SIGKILL) }
            }
            return nil
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: box.data, encoding: .utf8)
    }
}

private final class ReadBox: @unchecked Sendable {
    var data = Data()
}
