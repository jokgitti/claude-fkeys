import Foundation
import Testing
@testable import FKeysCore

@Test func assignsLowestFreeKey() {
    var r = Registry()
    #expect(r.assign("a") == 1)
    #expect(r.assign("b") == 2)
    #expect(r.assign("c") == 3)
}

@Test func reusesAReleasedKeyBeforeGoingHigher() {
    var r = Registry()
    _ = r.assign("a"); _ = r.assign("b"); _ = r.assign("c")
    r.release("b")
    #expect(r.assign("d") == 2)
}

@Test func assigningAKnownUUIDIsIdempotent() {
    var r = Registry()
    let first = r.assign("a")
    #expect(r.assign("a") == first)
    #expect(r.byKey.count == 1)
}

@Test func returnsNilPastCapacity() {
    var r = Registry()
    for i in 1...Registry.capacity { #expect(r.assign("s\(i)") == i) }
    #expect(r.assign("overflow") == nil)
    #expect(r.byKey.count == Registry.capacity)
}

@Test func releasingAnUnknownUUIDIsANoOp() {
    var r = Registry()
    _ = r.assign("a")
    r.release("ghost")
    #expect(r.byKey == [1: "a"])
}

@Test func lookupsGoBothWays() {
    var r = Registry()
    _ = r.assign("a")
    #expect(r.key(for: "a") == 1)
    #expect(r.uuid(forKey: 1) == "a")
    #expect(r.key(for: "nope") == nil)
    #expect(r.uuid(forKey: 7) == nil)
}

@Test func reconcileDropsDeadSessionsAndReportsThem() {
    var r = Registry()
    _ = r.assign("a"); _ = r.assign("b"); _ = r.assign("c")
    let released = r.reconcile(liveUUIDs: ["a", "c"])
    #expect(released == ["b"])
    #expect(r.byKey == [1: "a", 3: "c"])
}

@Test func reconcileWithEverythingAliveChangesNothing() {
    var r = Registry()
    _ = r.assign("a"); _ = r.assign("b")
    #expect(r.reconcile(liveUUIDs: ["a", "b"]).isEmpty)
    #expect(r.byKey == [1: "a", 2: "b"])
}

@Test func roundTripsThroughJSON() throws {
    var r = Registry()
    _ = r.assign("a"); _ = r.assign("b")
    let data = try JSONEncoder().encode(r)
    let back = try JSONDecoder().decode(Registry.self, from: data)
    #expect(back == r)
}

@Test func decodeThrowsOnANonIntegerKey() {
    let json = Data(#"{"one":"uuid-a"}"#.utf8)
    #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(Registry.self, from: json)
    }
}

@Test func decodeThrowsOnAKeyBelowRange() {
    let json = Data(#"{"0":"uuid-a"}"#.utf8)
    #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(Registry.self, from: json)
    }
}

@Test func decodeThrowsOnAKeyAboveRange() {
    let json = Data(#"{"13":"uuid-a"}"#.utf8)
    #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(Registry.self, from: json)
    }
}

@Test func decodeThrowsWhenTheSameUUIDAppearsUnderTwoKeys() {
    let json = Data(#"{"1":"uuid-a","2":"uuid-a"}"#.utf8)
    #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(Registry.self, from: json)
    }
}
