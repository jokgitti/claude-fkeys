import Testing
@testable import FKeysCore

@Test func keyStateMapsFromSessionState() {
    #expect(KeyState(nil) == .off)
    #expect(KeyState(.working) == .working)
    #expect(KeyState(.idle) == .idle)
    #expect(KeyState(.waiting) == .waiting)
}

@Test func keyStateRawValuesMatchTheFirmwareContract() {
    #expect(KeyState.off.rawValue == 0)
    #expect(KeyState.working.rawValue == 1)
    #expect(KeyState.idle.rawValue == 2)
    #expect(KeyState.waiting.rawValue == 3)
}

@Test func encodesStatesIntoA32ByteReport() {
    let states: [KeyState] = [.idle, .working, .waiting, .off, .off, .off,
                              .off, .off, .off, .off, .off, .off]
    let report = HIDProtocol.encodeStates(states)
    #expect(report.count == 32)
    #expect(report[0] == 0x01)
    #expect(Array(report[1...12]) == [2, 1, 3, 0, 0, 0, 0, 0, 0, 0, 0, 0])
    #expect(Array(report[13...31]).allSatisfy { $0 == 0 })
}

@Test func encodesThePaletteInOffWorkingIdleWaitingOrder() {
    let report = HIDProtocol.encodePalette(.default)
    #expect(report.count == 32)
    #expect(report[0] == 0x02)
    #expect(Array(report[1...12]) == [
        0, 0, 0,          // off     #000000
        255, 149, 0,      // working #ff9500
        0, 47, 21,        // idle    #002f15
        255, 0, 170,      // waiting #ff00aa
    ])
    #expect(Array(report[13...31]).allSatisfy { $0 == 0 })
}

@Test func fKeyLEDIndicesAreTwelveDistinctAscendingValues() {
    let indices = HIDProtocol.fKeyLEDIndices
    #expect(indices.count == 12)
    #expect(Set(indices).count == 12)
    #expect(indices == indices.sorted())
    #expect(indices.allSatisfy { (0...97).contains($0) })
}

@Test func encodesThePulseAsLittleEndianPeriodThenFloor() {
    let report = HIDProtocol.encodePulse(PulseSettings(periodMs: 0x0384, floor: 30)) // 900 ms
    #expect(report.count == 32)
    #expect(report[0] == 0x03)
    #expect(Array(report[1...3]) == [0x84, 0x03, 30])
    #expect(Array(report[4...31]).allSatisfy { $0 == 0 })
}

@Test func defaultPulseIs700msWithFloorZero() {
    let report = HIDProtocol.encodePulse(.default)
    #expect(Array(report[0...3]) == [0x03, 0xBC, 0x02, 0])
}

@Test func oddPulsePeriodsBelow512AreRoundedUpToEven() {
    #expect(Array(HIDProtocol.encodePulse(PulseSettings(periodMs: 501, floor: 0))[1...2]) == [0xF6, 0x01]) // 502
    #expect(Array(HIDProtocol.encodePulse(PulseSettings(periodMs: 500, floor: 0))[1...2]) == [0xF4, 0x01])
    #expect(Array(HIDProtocol.encodePulse(PulseSettings(periodMs: 513, floor: 0))[1...2]) == [0x01, 0x02]) // unchanged
}
