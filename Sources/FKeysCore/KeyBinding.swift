import Foundation

/// One F-key's derived binding: the tab index it always points at (key−1,
/// whether or not a tab exists there), and — if a Claude session currently
/// occupies that tab — its uuid and state.
public struct KeySlot: Equatable, Sendable {
    public let tabIndex: Int
    public let uuid: String?
    public let state: SessionState?

    public init(tabIndex: Int, uuid: String? = nil, state: SessionState? = nil) {
        self.tabIndex = tabIndex
        self.uuid = uuid
        self.state = state
    }
}

/// Derives F1…F12's bindings from tab position: F*n* is tab index *n*−1 of
/// the frontmost window, full stop. A tab with no Claude session keeps its
/// slot and comes back empty; nothing renumbers to close a gap, and a tab
/// beyond the twelfth is simply never reached.
public enum KeyBinding {
    /// - Parameters:
    ///   - tabs: the frontmost window's tabs, from `it2 tab list --json`.
    ///   - uuidToTabID: cached session uuid → `tab.id`, from
    ///     `it2 session get-var tab.id`. An entry whose tab.id no longer
    ///     appears in `tabs` (tab closed) is silently unbound, not an error.
    ///   - states: session uuid → its current state, from `StateStore.scan()`.
    /// - Returns: exactly `HIDProtocol.keyCount` slots, F1 first.
    public static func derive(
        tabs: [TabInfo],
        uuidToTabID: [String: String],
        states: [String: SessionState]
    ) -> [KeySlot] {
        var uuidByTabID: [String: String] = [:]
        for (uuid, tabID) in uuidToTabID where states[uuid] != nil {
            uuidByTabID[tabID] = uuid
        }
        return (0..<HIDProtocol.keyCount).map { index in
            guard let tab = tabs.first(where: { $0.index == index }), let uuid = uuidByTabID[tab.id] else {
                return KeySlot(tabIndex: index)
            }
            return KeySlot(tabIndex: index, uuid: uuid, state: states[uuid])
        }
    }

    /// Drops cache entries a fresh tab list proves stale, before any
    /// gap-filling lookup runs. Without this, dragging a pane to a different
    /// existing tab leaves its uuid bound to wherever its *old* tab.id ends
    /// up — the uuid never disappears from `it2 session list`, so nothing
    /// else would ever notice or re-fetch it.
    ///
    /// Two rules, both keyed off `tabs`' own `sessionCount`:
    /// 1. A cached tab.id absent from `tabs` no longer exists — drop it.
    /// 2. If more cached uuids claim a tab.id than that tab's own
    ///    `sessionCount`, at least one is wrong; which one isn't knowable
    ///    from the count alone, so every entry for that tab.id is dropped
    ///    and re-fetched this pass.
    ///
    /// The converse of rule 2 is deliberately not applied: a tab reporting
    /// *more* sessions than the cache knows about is not evidence of
    /// staleness, since non-Claude panes count too.
    public static func invalidateStaleCache(
        uuidToTabID: [String: String],
        tabs: [TabInfo]
    ) -> [String: String] {
        let sessionCountByTabID = Dictionary(uniqueKeysWithValues: tabs.map { ($0.id, $0.sessionCount) })

        var cachedCountByTabID: [String: Int] = [:]
        for tabID in uuidToTabID.values {
            cachedCountByTabID[tabID, default: 0] += 1
        }
        let overcountedTabIDs = cachedCountByTabID.filter { tabID, cachedCount in
            guard let sessionCount = sessionCountByTabID[tabID] else { return false } // rule 1 covers this
            return cachedCount > sessionCount
        }.keys

        return uuidToTabID.filter { _, tabID in
            sessionCountByTabID[tabID] != nil && !overcountedTabIDs.contains(tabID)
        }
    }
}
