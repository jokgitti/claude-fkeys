import Testing
@testable import FKeysCore

private func tab(_ index: Int, id: String) -> TabInfo {
    TabInfo(index: index, id: id, windowID: "w", isActive: false, sessionCount: 1)
}

@Test func bindsEachSessionToItsOwnTabIndex() {
    let tabs = [tab(0, id: "1"), tab(1, id: "2")]
    let uuidToTabID = ["a": "1", "b": "2"]
    let states = ["a": SessionState.working, "b": SessionState.idle]

    let slots = KeyBinding.derive(tabs: tabs, uuidToTabID: uuidToTabID, states: states)

    #expect(slots.count == 12)
    #expect(slots[0] == KeySlot(tabIndex: 0, uuid: "a", state: .working))
    #expect(slots[1] == KeySlot(tabIndex: 1, uuid: "b", state: .idle))
    #expect(slots[2] == KeySlot(tabIndex: 2))
}

@Test func nonClaudeTabsSitDarkWithoutClosingTheGap() {
    // Tabs 0 and 1 are plain shells; only tab 2 runs Claude.
    let tabs = [tab(0, id: "1"), tab(1, id: "2"), tab(2, id: "3")]
    let uuidToTabID = ["a": "3"]
    let states = ["a": SessionState.idle]

    let slots = KeyBinding.derive(tabs: tabs, uuidToTabID: uuidToTabID, states: states)

    #expect(slots[0] == KeySlot(tabIndex: 0))
    #expect(slots[1] == KeySlot(tabIndex: 1))
    #expect(slots[2] == KeySlot(tabIndex: 2, uuid: "a", state: .idle))
}

@Test func tabsBeyondTheTwelfthGetNoKey() {
    let tabs = (0...14).map { tab($0, id: "\($0 + 1)") }
    // "14" is tab index 13 — one past the 12-key capacity.
    let uuidToTabID = ["overflow": "14"]
    let states = ["overflow": SessionState.working]

    let slots = KeyBinding.derive(tabs: tabs, uuidToTabID: uuidToTabID, states: states)

    #expect(slots.count == 12)
    #expect(slots.allSatisfy { $0.uuid != "overflow" })
}

@Test func noSessionsAtAllBindsNothing() {
    let tabs = [tab(0, id: "1"), tab(1, id: "2")]

    let slots = KeyBinding.derive(tabs: tabs, uuidToTabID: [:], states: [:])

    #expect(slots.map(\.tabIndex) == Array(0..<12))
    #expect(slots.allSatisfy { $0.uuid == nil && $0.state == nil })
}

@Test func aSessionWhoseTabHasVanishedIsNotBound() {
    // uuidToTabID has a stale cache entry for a tab.id the current tab list
    // no longer contains (the tab was closed), alongside a genuinely live
    // session — so the test can tell "only that slot goes dark" apart from
    // "derive() blanks everything".
    let tabs = [tab(0, id: "1")]
    let uuidToTabID = ["live": "1", "gone": "99"]
    let states = ["live": SessionState.idle, "gone": SessionState.working]

    let slots = KeyBinding.derive(tabs: tabs, uuidToTabID: uuidToTabID, states: states)

    #expect(slots[0] == KeySlot(tabIndex: 0, uuid: "live", state: .idle))
    #expect(slots.allSatisfy { $0.uuid != "gone" })
}

// --- cache invalidation (invalidateStaleCache) ---
//
// derive() itself already tolerates a stale entry (above): it just never
// matches a vanished tab.id. These tests cover the separate, proactive step
// that drops stale entries from the cache *before* derive() ever sees it, so
// a dragged pane's old tab.id doesn't linger for the life of the session.

@Test func staleCacheDropsATabIDThatNoLongerExists() {
    let tabs = [tab(0, id: "1")]
    let uuidToTabID = ["a": "1", "gone": "99"]

    let cleaned = KeyBinding.invalidateStaleCache(uuidToTabID: uuidToTabID, tabs: tabs)

    #expect(cleaned == ["a": "1"])
}

@Test func staleCacheDropsAllEntriesForATabTheCacheOvercounts() {
    // Tab "5" reports 1 session but the cache claims two uuids point at it —
    // exactly what a dragged pane looks like: one uuid moved there from
    // elsewhere and the other cache entry is now wrong. Which one is stale
    // is not knowable from the count alone, so both are dropped and
    // re-fetched this pass.
    let tabs = [tab(0, id: "5")]
    let uuidToTabID = ["a": "5", "b": "5"]

    let cleaned = KeyBinding.invalidateStaleCache(uuidToTabID: uuidToTabID, tabs: tabs)

    #expect(cleaned.isEmpty)
}

@Test func staleCacheIgnoresATabReportingMoreSessionsThanCached() {
    // A tab can legitimately report more sessions than the cache knows about
    // — non-Claude panes count too — so under-counting must never be treated
    // as evidence of staleness.
    let tabs = [TabInfo(index: 0, id: "5", windowID: "w", isActive: false, sessionCount: 3)]
    let uuidToTabID = ["a": "5"]

    let cleaned = KeyBinding.invalidateStaleCache(uuidToTabID: uuidToTabID, tabs: tabs)

    #expect(cleaned == ["a": "5"])
}
