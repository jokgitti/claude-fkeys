import Foundation
import Testing
@testable import FKeysCore

private final class Clock: @unchecked Sendable {
    var t = Date(timeIntervalSince1970: 1000)
    func now() -> Date { t }
}

/// Every call advances the clock by `cost` seconds.
private final class StubCLI: ITermQuerying, @unchecked Sendable {
    let clock: Clock
    let cost: TimeInterval
    var windowID: String? = "w"
    var tabList: [TabInfo]? = [TabInfo(index: 0, id: "10", windowID: "w", isActive: true, sessionCount: 1)]
    var tabIDs: [String: String] = [:]
    private(set) var calls = 0
    private(set) var tabIDCalls: [String] = []

    init(clock: Clock, cost: TimeInterval) { self.clock = clock; self.cost = cost }

    func frontmostWindowID() -> String? { calls += 1; clock.t += cost; return windowID }
    func tabs(inWindow windowID: String) -> [TabInfo]? { calls += 1; clock.t += cost; return tabList }
    func tabID(forSessionUUID uuid: String) -> String? {
        calls += 1; clock.t += cost; tabIDCalls.append(uuid); return tabIDs[uuid]
    }
}

@Suite struct TabResolverTests {
    private let uuids = Set((1...6).map { "u\($0)" })

    private func make(cost: TimeInterval = 1) -> (TabResolver, StubCLI, Clock) {
        let clock = Clock()
        let cli = StubCLI(clock: clock, cost: cost)
        for (i, u) in uuids.sorted().enumerated() { cli.tabIDs[u] = "\(10 + i)" }
        cli.tabList = (0..<6).map { TabInfo(index: $0, id: "\(10 + $0)", windowID: "w", isActive: false, sessionCount: 1) }
        return (TabResolver(cli: cli, now: clock.now), cli, clock)
    }

    @Test func aPassStopsIssuingCallsOnceTheBudgetIsSpent() {
        let (r, cli, clock) = make(cost: 1)
        r.rederive(uuids: uuids, deadline: clock.now().addingTimeInterval(3))
        #expect(cli.calls == 3) // window, tabs, one tab.id; the clock then reads 3 s
        #expect(r.uuidToTabID.count == 1)
    }

    @Test func aBudgetSpentBeforeTheTabListLeavesEverythingUntouched() {
        let (r, cli, clock) = make(cost: 1)
        r.rederive(uuids: uuids, deadline: clock.now().addingTimeInterval(3))
        let before = (r.tabs, r.uuidToTabID)
        // Budget covers the window call only.
        r.rederive(uuids: uuids, deadline: clock.now().addingTimeInterval(1))
        #expect(cli.calls == 4)
        #expect(r.tabs == before.0)
        #expect(r.uuidToTabID == before.1)
    }

    @Test func aDeadlineAlreadyPastIssuesNoCalls() {
        let (r, cli, clock) = make()
        r.rederive(uuids: uuids, deadline: clock.now())
        #expect(cli.calls == 0)
    }

    @Test func successivePassesReachEveryUUIDEvenWhenEachRunsOutEarly() {
        let (r, cli, clock) = make(cost: 1)
        for _ in 0..<6 {
            r.rederive(uuids: uuids, deadline: clock.now().addingTimeInterval(4))
        }
        #expect(Set(r.uuidToTabID.keys) == uuids)
        #expect(cli.tabIDCalls.count == 6) // never re-queried once resolved
    }

    @Test func uuidsWhoseLookupsFailDoNotStarveTheOthers() {
        let (r, cli, clock) = make(cost: 1)
        cli.tabIDs["u1"] = nil
        cli.tabIDs["u2"] = nil
        for _ in 0..<8 {
            r.rederive(uuids: uuids, deadline: clock.now().addingTimeInterval(4))
        }
        #expect(Set(r.uuidToTabID.keys) == uuids.subtracting(["u1", "u2"]))
    }

    @Test func aFailedWindowCallKeepsThePreviousTabsAndCache() {
        let (r, cli, clock) = make(cost: 0)
        r.rederive(uuids: uuids, deadline: clock.now().addingTimeInterval(3))
        let kept = (r.tabs, r.uuidToTabID)
        cli.windowID = nil
        r.rederive(uuids: uuids, deadline: clock.now().addingTimeInterval(3))
        #expect(r.tabs == kept.0)
        #expect(r.uuidToTabID == kept.1)
    }
}

@Suite struct TabFocusTests {
    @Test func switchesTheTabBeforeRaisingTheApp() {
        var events: [String] = []
        TabFocus(gotoTab: { events.append("goto \($0)") }, activate: { events.append("activate") }).focus(key: 3)
        #expect(events == ["goto 2", "activate"])
    }
}
