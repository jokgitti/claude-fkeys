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
    // uuidToTabID still has a stale cache entry for a tab.id the current
    // tab list no longer contains (the tab was closed).
    let tabs = [tab(0, id: "1")]
    let uuidToTabID = ["gone": "99"]
    let states = ["gone": SessionState.working]

    let slots = KeyBinding.derive(tabs: tabs, uuidToTabID: uuidToTabID, states: states)

    #expect(slots.allSatisfy { $0.uuid == nil })
}
