import Testing
@testable import FKeysCore

private final class FakeSink: ReportSink {
    var present = true
    var failNextSend = false
    var failAllSends = false
    /// Fail the n-th send from now (1 = next).
    var failSendNumber: Int?
    private(set) var isOpen = false
    private(set) var openAttempts = 0
    private(set) var sent: [[UInt8]] = []

    func open() -> Bool {
        openAttempts += 1
        isOpen = present
        return present
    }

    func send(_ report: [UInt8]) -> Bool {
        if failAllSends { isOpen = false; return false }
        if let n = failSendNumber {
            failSendNumber = n == 1 ? nil : n - 1
            if n == 1 { isOpen = false; return false }
        }
        if failNextSend {
            failNextSend = false
            isOpen = false
            return false
        }
        sent.append(report)
        return true
    }

    var commands: [UInt8] { sent.map { $0[0] } }
}

@Suite struct LightPublisherTests {
    private func make(_ sink: FakeSink) -> LightPublisher {
        LightPublisher(sink: sink, palette: { .default })
    }

    private func states(_ first: KeyState) -> [KeyState] {
        [first] + [KeyState](repeating: .off, count: 11)
    }

    @Test func connectSendsPaletteThenStates() {
        let sink = FakeSink()
        let p = make(sink)
        p.publish(states(.working))
        #expect(sink.sent.isEmpty)
        p.tick()
        #expect(sink.commands == [0x02, 0x03, 0x01])
    }

    @Test func unchangedStatesAreNotRewritten() {
        let sink = FakeSink()
        let p = make(sink)
        p.tick()
        p.publish(states(.working))
        p.publish(states(.working))
        p.publish(states(.working))
        #expect(sink.commands == [0x02, 0x03, 0x01])
        p.publish(states(.idle))
        #expect(sink.commands == [0x02, 0x03, 0x01, 0x01])
    }

    @Test func tickKeepsAliveWithCurrentStates() {
        let sink = FakeSink()
        let p = make(sink)
        p.tick()
        p.publish(states(.working))
        p.tick()
        #expect(sink.commands == [0x02, 0x03, 0x01, 0x01])
        #expect(sink.sent[3] == HIDProtocol.encodeStates(states(.working)))
    }

    @Test func absentKeyboardIsRetriedAndNothingSent() {
        let sink = FakeSink()
        sink.present = false
        let p = make(sink)
        p.publish(states(.working))
        p.tick()
        p.tick()
        #expect(sink.openAttempts == 2)
        #expect(sink.sent.isEmpty)
        sink.present = true
        p.tick()
        #expect(sink.commands == [0x02, 0x03, 0x01])
    }

    @Test func failedWriteDropsLinkAndReconnectResendsPaletteAndStates() {
        let sink = FakeSink()
        let p = make(sink)
        p.tick()
        sink.failNextSend = true
        p.publish(states(.working))
        #expect(!sink.isOpen)
        p.publish(states(.idle))
        #expect(sink.commands == [0x02, 0x03])
        p.tick()
        #expect(sink.commands == [0x02, 0x03, 0x02, 0x03, 0x01])
        #expect(sink.sent[4] == HIDProtocol.encodeStates(states(.idle)))
    }

    @Test func failedPaletteWriteIsNotFatalAndIsRetriedInTheSameTick() {
        let sink = FakeSink()
        sink.failNextSend = true
        let p = make(sink)
        p.tick()
        #expect(sink.isOpen)
        #expect(sink.commands == [0x02, 0x03])
    }

    @Test func failedPulseWriteIsRetriedAndThePulseIsResent() {
        let sink = FakeSink()
        sink.failSendNumber = 2 // palette ok, pulse fails
        let p = make(sink)
        p.tick()
        #expect(sink.commands == [0x02, 0x02, 0x03])
    }

    @Test func stateFailureInTickAfterPaletteSuccessIsRetriedImmediately() {
        let sink = FakeSink()
        let p = make(sink)
        p.publish(states(.working))
        sink.failSendNumber = 3 // palette, pulse ok, states fail
        p.tick()
        #expect(sink.commands == [0x02, 0x03, 0x02, 0x03, 0x01])
        #expect(sink.isOpen)
    }

    @Test func aStillFailingLinkIsRetriedOnceThenLeftUntilTheNextTick() {
        let sink = FakeSink()
        sink.failAllSends = true
        let p = make(sink)
        p.tick()
        #expect(sink.openAttempts == 2)
        #expect(sink.sent.isEmpty)
    }

    @Test func tickWithNothingPublishedSendsOnlyThePalette() {
        let sink = FakeSink()
        let p = make(sink)
        p.tick()
        p.tick()
        #expect(sink.commands == [0x02, 0x03])
    }

    @Test func aStatePublishedWhileClosedIsDeliveredOnReconnect() {
        let sink = FakeSink()
        sink.present = false
        let p = make(sink)
        p.tick()
        p.publish(states(.waiting))
        sink.present = true
        p.tick()
        #expect(sink.commands == [0x02, 0x03, 0x01])
        #expect(sink.sent[2] == HIDProtocol.encodeStates(states(.waiting)))
    }
}
