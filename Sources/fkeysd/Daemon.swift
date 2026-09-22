import Foundation
import FKeysCore

final class Daemon {
    private let stateDir: URL
    private let registryURL: URL
    private let store: StateStore
    private let iterm: ITermCLI

    private var registry = Registry()
    private var watcher: DirectoryWatcher?
    private var reconcileTimer: Timer?
    private let hotkeys = HotkeyManager()

    init(stateDir: URL, iterm: ITermCLI = ITermCLI()) {
        self.stateDir = stateDir
        self.registryURL = stateDir.appendingPathComponent("registry.json")
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
    func refresh() {
        let states = store.scan()

        // Sorted so assignment is deterministic when several sessions appear at once.
        for uuid in states.keys.sorted() where registry.key(for: uuid) == nil {
            if let key = registry.assign(uuid) {
                log("F\(key) -> \(uuid)")
            } else {
                log("no free F-key for \(uuid); \(Registry.capacity) already bound")
            }
        }
        for uuid in Array(registry.byKey.values) where states[uuid] == nil {
            registry.release(uuid)
        }

        saveRegistry()
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
