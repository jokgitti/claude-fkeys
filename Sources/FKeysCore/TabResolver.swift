import Foundation

/// The `it2` queries a reconcile pass needs, one per call, so a pass can check
/// its time budget between calls.
public protocol ITermQuerying {
    func frontmostWindowID() -> String?
    func tabs(inWindow windowID: String) -> [TabInfo]?
    func tabID(forSessionUUID uuid: String) -> String?
}

extension ITermCLI: ITermQuerying {}

/// Holds the frontmost window's tabs and the session-uuid to `tab.id` cache,
/// and refreshes them within a time budget.
///
/// An `it2` call blocks the daemon's main queue, next to the keyboard
/// keepalive, so one pass may not run unbounded. Once the deadline passes no
/// further call is issued. Whatever was not reached keeps its previous value:
/// running out of budget is "unknown, change nothing", the same as a failed call.
///
/// Uncached uuids are resolved round-robin from where the previous pass
/// stopped, so a pass that always runs out early still reaches every uuid
/// over successive passes. A uuid whose lookup fails counts as attempted.
public final class TabResolver {
    public private(set) var tabs: [TabInfo] = []
    public private(set) var uuidToTabID: [String: String] = [:]

    private let cli: ITermQuerying
    private let now: () -> Date
    private var cursor: String?

    public init(cli: ITermQuerying, now: @escaping () -> Date = Date.init) {
        self.cli = cli
        self.now = now
    }

    public func forget(_ uuid: String) {
        uuidToTabID.removeValue(forKey: uuid)
    }

    public func rederive(uuids: Set<String>, deadline: Date) {
        guard now() < deadline,
              let windowID = cli.frontmostWindowID(),
              now() < deadline,
              let fresh = cli.tabs(inWindow: windowID)
        else { return }
        tabs = fresh
        uuidToTabID = KeyBinding.invalidateStaleCache(uuidToTabID: uuidToTabID, tabs: tabs)

        let pending = uuids.filter { uuidToTabID[$0] == nil }.sorted()
        let start = pending.firstIndex { $0 > (cursor ?? "") } ?? 0
        for offset in 0..<pending.count {
            guard now() < deadline else { return }
            let uuid = pending[(start + offset) % pending.count]
            cursor = uuid
            if let tabID = cli.tabID(forSessionUUID: uuid) {
                uuidToTabID[uuid] = tabID
            }
        }
    }
}
