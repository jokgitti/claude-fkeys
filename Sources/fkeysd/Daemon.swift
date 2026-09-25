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

    /// The frontmost window's tabs, as of the last successful re-derive.
    /// Kept across a failed it2 call so a hiccup degrades to "stale", never
    /// to "nothing bound".
    private var tabs: [TabInfo] = []
    /// Session uuid → `tab.id`, filled in once per uuid and dropped when its
    /// state file is removed, or when `KeyBinding.invalidateStaleCache`
    /// proves an entry stale (see rederiveTabs) — which is how a dragged
    /// pane's old tab.id stops lingering without waiting for the session to
    /// end.
    private var uuidToTabID: [String: String] = [:]
    private var lastUUIDs: Set<String> = []

    private var watcher: DirectoryWatcher?
    private var reconcileTimer: Timer?
    private let hotkeys = HotkeyManager()

    init(stateDir: URL, iterm: ITermCLI = ITermCLI()) {
        self.stateDir = stateDir
        self.store = StateStore(dir: stateDir)
        self.iterm = iterm
    }

    func start() {
        // Created before the first refresh(): its init creates stateDir, and
        // a fresh machine with no ~/.claude/.fkeys yet needs it to exist
        // before anything scans it.
        watcher = DirectoryWatcher(dir: stateDir) { [weak self] in self?.refresh() }
        if watcher == nil { log("could not watch \(stateDir.path); falling back to the 10s loop only") }

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

    /// Re-derives tab positions: refreshes the frontmost window's tab list,
    /// drops any cache entry the fresh list proves stale (a dragged pane —
    /// see KeyBinding.invalidateStaleCache), then fills in a `tab.id` for
    /// any uuid still uncached. A failed or unreachable it2 call leaves the
    /// previous tabs/cache in place entirely — see ITermCLI.frontmostWindowTabs.
    private func rederiveTabs() {
        if let fresh = iterm.frontmostWindowTabs() {
            tabs = fresh
            uuidToTabID = KeyBinding.invalidateStaleCache(uuidToTabID: uuidToTabID, tabs: tabs)
        }
        for uuid in lastUUIDs where uuidToTabID[uuid] == nil {
            if let tabID = iterm.tabID(forSessionUUID: uuid) {
                uuidToTabID[uuid] = tabID
            }
        }
    }

    /// SessionEnd is not guaranteed — kill -9, a closed window and a crash
    /// all skip it — so without this, a dead session's state file leaks
    /// until the daemon restarts. Also the 10s tab re-derive: up to 10s of
    /// staleness after a tab close or drag is accepted.
    func reconcile() {
        let live = iterm.liveSessionUUIDs()
        // An empty result means iTerm is gone or it2 failed. Treat it as
        // unknown, not as "every session died", or one it2 hiccup deletes
        // every state file.
        if !live.isEmpty {
            let dead = store.scan().keys.filter { !live.contains($0) }
            for uuid in dead {
                log("dropped \(uuid): no longer in it2 session list")
                try? FileManager.default.removeItem(at: stateDir.appendingPathComponent("\(uuid).json"))
                uuidToTabID.removeValue(forKey: uuid)
            }
        }
        rederiveTabs()
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

    private func focus(_ key: Int) {
        iterm.gotoTab(key - 1)
    }

    /// Filled in by Task 9, once the firmware exists.
    private func publish(_ states: [String: SessionState]) {}

    private func log(_ message: String) {
        print("fkeysd: \(message)")
        fflush(stdout)
    }
}
