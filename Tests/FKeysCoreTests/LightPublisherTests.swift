import Testing
@testable import FKeysCore

private final class FakeSink: ReportSink {
    var present = true
    var failNextSend = false
    private(set) var isOpen = false
    private(set) var openAttempts = 0
    private(set) var sent: [[UInt8]] = []

    func open() -> Bool {
        openAttempts += 1
        isOpen = present
        return present
    }

    func send(_ report: [UInt8]) -> Bool {
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
        #expect(sink.commands == [0x02, 0x01])
    }

    @Test func unchangedStatesAreNotRewritten() {
        let sink = FakeSink()
        let p = make(sink)
        p.tick()
        p.publish(states(.working))
        p.publish(states(.working))
        p.publish(states(.working))
        #expect(sink.commands == [0x02, 0x01])
        p.publish(states(.idle))
        #expect(sink.commands == [0x02, 0x01, 0x01])
    }

    @Test func tickKeepsAliveWithCurrentStates() {
        let sink = FakeSink()
        let p = make(sink)
        p.tick()
        p.publish(states(.working))
        p.tick()
        #expect(sink.commands == [0x02, 0x01, 0x01])
        #expect(sink.sent[2] == HIDProtocol.encodeStates(states(.working)))
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
        #expect(sink.commands == [0x02, 0x01])
    }

    @Test func failedWriteDropsLinkAndReconnectResendsPaletteAndStates() {
        let sink = FakeSink()
        let p = make(sink)
        p.tick()
        sink.failNextSend = true
        p.publish(states(.working))
        #expect(!sink.isOpen)
        p.publish(states(.idle))
        #expect(sink.commands == [0x02])
        p.tick()
        #expect(sink.commands == [0x02, 0x02, 0x01])
        #expect(sink.sent[2] == HIDProtocol.encodeStates(states(.idle)))
    }

    @Test func failedPaletteWriteIsNotFatal() {
        let sink = FakeSink()
        sink.failNextSend = true
        let p = make(sink)
        p.tick()
        #expect(!sink.isOpen)
        p.tick()
        #expect(sink.commands == [0x02])
    }
}
