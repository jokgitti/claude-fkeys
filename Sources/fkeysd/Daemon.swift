import Foundation
import FKeysCore

/// `@unchecked Sendable` only to satisfy `Timer.scheduledTimer`'s `@Sendable`
/// closure parameter. Every mutation of `registry` happens on the main
/// thread in practice: DirectoryWatcher's DispatchSource runs its handler on
/// `.main` (see DirectoryWatcher.swift), the hotkey callback fires on the
/// main run loop via Carbon's GetEventDispatcherTarget() (see
/// Hotkeys.swift), and this class's own Timer fires on the main run loop
/// too, since `app.run()` runs it. No lock or queue is added here — if a
/// future caller ever touches a Daemon from a background thread, this
/// annotation stops the compiler from catching it.
final class Daemon: @unchecked Sendable {
    private let stateDir: URL
    private let registryURL: URL
    private let store: StateStore
    private let iterm: ITermCLI

    private var registry = Registry()
    private var watcher: DirectoryWatcher?
    private var reconcileTimer: Timer?
    private let hotkeys = HotkeyManager()

    /// `registryURL` must live outside `stateDir`: `stateDir` is watched, and
    /// a write inside it re-triggers the watcher. Saving the registry there
    /// (or logging there, see launchd/com.lucagaleazzi.fkeys.plist.in) is an
    /// unbounded refresh-save-refresh loop, not a one-off self-trigger.
    init(stateDir: URL, registryURL: URL, iterm: ITermCLI = ITermCLI()) {
        self.stateDir = stateDir
        self.registryURL = registryURL
        self.store = StateStore(dir: stateDir)
        self.iterm = iterm
    }

    func start() {
        loadRegistry()

        // Created before the first refresh(): its init creates stateDir, and
        // refresh() saves the registry into it. On a fresh machine with no
        // ~/.claude/.fkeys yet, refresh() first would try to save into a
        // directory that doesn't exist yet, and that write fails silently.
        watcher = DirectoryWatcher(dir: stateDir) { [weak self] in self?.refresh() }
        if watcher == nil { log("could not watch \(stateDir.path); falling back to the 10s loop only") }

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

    /// Bind new sessions, unbind gone ones, then push the lights.
    ///
    /// The hook triggers this on every PreToolUse/PostToolUse, and most of
    /// those calls bind nothing new and release nothing — the session's file
    /// already exists and still exists. `changed` gates the save on those,
    /// so a no-op refresh costs a directory scan, not a disk write too.
    func refresh() {
        let states = store.scan()
        var changed = false

        // Sorted so assignment is deterministic when several sessions appear at once.
        for uuid in states.keys.sorted() where registry.key(for: uuid) == nil {
            if let key = registry.assign(uuid) {
                log("F\(key) -> \(uuid)")
                changed = true
            } else {
                log("no free F-key for \(uuid); \(Registry.capacity) already bound")
            }
        }
        for uuid in Array(registry.byKey.values) where states[uuid] == nil {
            registry.release(uuid)
            changed = true
        }

        if changed { saveRegistry() }
        publish(states)
    }

    /// SessionEnd is not guaranteed, so drop keys whose session no longer exists.
    func reconcile() {
        let live = iterm.liveSessionUUIDs()
        // An empty result means iTerm is gone or it2 failed. Treat it as unknown,
        // not as "every session died", or one it2 hiccup clears the whole F-row.
        guard !live.isEmpty else { return }

        let released = registry.reconcile(liveUUIDs: live)
        guard !released.isEmpty else { return }
        for uuid in released {
            log("released \(uuid): no longer in it2 session list")
            try? FileManager.default.removeItem(at: stateDir.appendingPathComponent("\(uuid).json"))
        }
        saveRegistry()
        publish(store.scan())
    }

    func statusReport() -> String {
        // `status` builds a fresh Daemon that never calls start(), so this is
        // the only place its registry gets loaded from disk.
        loadRegistry()
        let states = store.scan()
        return (1...Registry.capacity).map { key in
            guard let uuid = registry.uuid(forKey: key) else { return "F\(key)  —" }
            return "F\(key)  \(uuid)  \(states[uuid]?.rawValue ?? "unknown")"
        }.joined(separator: "\n")
    }

    private func focus(_ key: Int) {
        guard let uuid = registry.uuid(forKey: key) else { return }
        iterm.focus(uuid)
    }

    /// Filled in by Task 9, once the firmware exists.
    private func publish(_ states: [String: SessionState]) {}

    private func loadRegistry() {
        guard let data = try? Data(contentsOf: registryURL),
              let saved = try? JSONDecoder().decode(Registry.self, from: data)
        else { return }
        registry = saved
    }

    private func saveRegistry() {
        guard let data = try? JSONEncoder().encode(registry) else { return }
        try? data.write(to: registryURL, options: .atomic)
    }

    private func log(_ message: String) {
        print("fkeysd: \(message)")
        fflush(stdout)
    }
}
