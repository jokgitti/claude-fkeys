import AppKit
import Foundation
import FKeysCore

/// `@unchecked Sendable` only to satisfy `Timer.scheduledTimer`'s `@Sendable`
/// closure parameter. Every mutation of this class's state happens on the
/// main thread in practice: DirectoryWatcher's DispatchSource runs its handler on
/// `.main` (see DirectoryWatcher.swift), the hotkey callback fires on the
/// main run loop via Carbon's GetEventDispatcherTarget() (see
/// Hotkeys.swift), and this class's own Timer fires on the main run loop
/// too, since `app.run()` runs it. No lock or queue is added here — if a
/// future caller ever touches a Daemon from a background thread, this
/// annotation stops the compiler from catching it.
final class Daemon: @unchecked Sendable {
    private let stateDir: URL
    private let store: StateStore
    private let iterm: ITermCLI

    /// The frontmost window's tabs and the session uuid → `tab.id` cache,
    /// kept across a failed or out-of-budget it2 call so a hiccup degrades to
    /// "stale", never to "nothing bound". See TabResolver.
    private let resolver: TabResolver
    /// Upper bound on it2 work per pass. A pass runs on the main queue next to
    /// the keyboard keepalive; the firmware blanks the board after 10 s. One
    /// call may overrun the budget by its 2 s timeout.
    private static let passBudget: TimeInterval = 3
    private var lastUUIDs: Set<String> = []

    private var watcher: DirectoryWatcher?
    private var reconcileTimer: Timer?
    private var keyboardTimer: Timer?
    private let hotkeys = HotkeyManager()
    private let publisher: LightPublisher

    /// Also the firmware watchdog's refresh interval: it blanks the board 10 s
    /// after the last report, so an idle daemon must still write inside that.
    /// 2 s leaves five writes inside the window; the tolerance bounds how far
    /// macOS may coalesce the timer.
    private static let keyboardTick: TimeInterval = 2
    private static let keyboardTickTolerance: TimeInterval = 0.2

    init(stateDir: URL, iterm: ITermCLI = ITermCLI(), paletteURL: URL? = nil) {
        self.stateDir = stateDir
        self.publisher = LightPublisher(
            sink: HIDTransport(),
            palette: { paletteURL.map(Palette.load(from:)) ?? .default },
            log: { print("fkeysd: \($0)"); fflush(stdout) }
        )
        self.store = StateStore(dir: stateDir)
        self.iterm = iterm
        self.resolver = TabResolver(cli: iterm)
    }

    func start() {
        // Created before the first refresh(): its init creates stateDir, and
        // a fresh machine with no ~/.claude/.fkeys yet needs it to exist
        // before anything scans it.
        watcher = DirectoryWatcher(dir: stateDir) { [weak self] in self?.refresh() }
        if watcher == nil { log("could not watch \(stateDir.path); falling back to the 10s loop only") }

        publisher.tick()
        rederiveTabs()
        refresh()

        // Assigned before registerFunctionKeys() so a keypress that arrives between
        // registration and handler assignment is never silently dropped.
        hotkeys.onPress = { [weak self] key in self?.focus(key) }
        let registered = hotkeys.registerFunctionKeys()
        log("registered \(registered)/12 hotkeys")

        reconcileTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            self?.reconcile()
        }
        keyboardTimer = Timer.scheduledTimer(withTimeInterval: Self.keyboardTick, repeats: true) { [weak self] _ in
            self?.publisher.tick()
        }
        keyboardTimer?.tolerance = Self.keyboardTickTolerance
    }

    /// Cheap path: no it2 work. The hook triggers this on every
    /// PreToolUse/PostToolUse, and most of those calls change no session's
    /// existence, only its state (working → idle) — that costs a directory
    /// scan, never an it2 round trip. Re-deriving tab positions only happens
    /// when the set of live session uuids actually changed.
    func refresh() {
        let states = store.scan()
        let uuids = Set(states.keys)
        if uuids != lastUUIDs {
            lastUUIDs = uuids
            rederiveTabs()
        }
        publish(states)
    }

    /// Re-derives tab positions within `passBudget`. Anything not reached keeps
    /// its previous value and is picked up by a later pass.
    private func rederiveTabs(deadline: Date = Date().addingTimeInterval(passBudget)) {
        resolver.rederive(uuids: lastUUIDs, deadline: deadline)
    }

    /// SessionEnd is not guaranteed — kill -9, a closed window and a crash
    /// all skip it — so without this, a dead session's state file leaks
    /// until the daemon restarts. Also the 10s tab re-derive: up to 10s of
    /// staleness after a tab close or drag is accepted.
    func reconcile() {
        let deadline = Date().addingTimeInterval(Self.passBudget)
        let live = iterm.liveSessionUUIDs()
        // An empty result means iTerm is gone or it2 failed. Treat it as
        // unknown, not as "every session died", or one it2 hiccup deletes
        // every state file.
        if !live.isEmpty {
            let dead = store.scan().keys.filter { !live.contains($0) }
            for uuid in dead {
                log("dropped \(uuid): no longer in it2 session list")
                try? FileManager.default.removeItem(at: stateDir.appendingPathComponent("\(uuid).json"))
                resolver.forget(uuid)
            }
        }
        rederiveTabs(deadline: deadline)
        publish(store.scan())
    }

    func statusReport() -> String {
        let states = store.scan()
        guard let tabs = iterm.frontmostWindowTabs() else {
            return "iTerm2 not reachable via it2 — bindings unknown."
        }
        var uuidToTabID: [String: String] = [:]
        for uuid in states.keys {
            if let tabID = iterm.tabID(forSessionUUID: uuid) {
                uuidToTabID[uuid] = tabID
            }
        }
        let slots = KeyBinding.derive(tabs: tabs, uuidToTabID: uuidToTabID, states: states)
        return slots.enumerated().map { offset, slot in
            let key = offset + 1
            guard let uuid = slot.uuid else {
                let tabExists = tabs.contains { $0.index == slot.tabIndex }
                return "F\(key)  tab \(slot.tabIndex)  \(tabExists ? "(no session)" : "(no tab)")"
            }
            return "F\(key)  tab \(slot.tabIndex)  \(uuid)  \(slot.state?.rawValue ?? "unknown")"
        }.joined(separator: "\n")
    }

    /// `tab goto` does not raise iTerm, so a key pressed in another app would
    /// switch a tab nobody can see. Plain `activate()` does nothing here: on
    /// macOS 14+ it only succeeds when the frontmost app yields, and this
    /// accessory app is never frontmost. `activate(options:)` is deprecated but
    /// still works (measured from Arc to iTerm on macOS 26); empty options
    /// raise the app without bringing all its windows forward.
    /// Not running: does nothing.
    @available(macOS, deprecated: 14.0)
    private static func activateITerm() {
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.googlecode.iterm2")
            .first?.activate(options: [])
    }

    private func focus(_ key: Int) {
        TabFocus(gotoTab: iterm.gotoTab, activate: Self.activateITerm).focus(key: key)
    }

    private func publish(_ states: [String: SessionState]) {
        let slots = KeyBinding.derive(tabs: resolver.tabs, uuidToTabID: resolver.uuidToTabID, states: states)
        publisher.publish(slots.map { KeyState($0.state) })
    }

    private func log(_ message: String) {
        print("fkeysd: \(message)")
        fflush(stdout)
    }
}
