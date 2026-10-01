import Foundation
import Testing
@testable import FKeysCore

private final class LockedSink: ReportSink, @unchecked Sendable {
    private let lock = NSLock()
    private var _sent: [[UInt8]] = []
    private var _open = false
    /// When set, `send` blocks until signalled, like a stalled USB write.
    var gate: DispatchSemaphore?

    var isOpen: Bool { lock.withLock { _open } }
    func open() -> Bool { lock.withLock { _open = true }; return true }
    func send(_ report: [UInt8]) -> Bool {
        gate?.wait()
        lock.withLock { _sent.append(report) }
        return true
    }
    var sent: [[UInt8]] { lock.withLock { _sent } }
}

@Suite struct KeyboardLightsTests {
    private let states = [KeyState](repeating: .working, count: 12)

    @Test func keepaliveKeepsFiringWhileTheCallersThreadIsBlocked() {
        let sink = LockedSink()
        let lights = KeyboardLights(sink: sink, palette: { .default }, interval: 0.05, leeway: 0.005)
        lights.start()
        lights.publish(states)
        Thread.sleep(forTimeInterval: 0.6) // this thread stands in for a main queue held by it2
        lights.drain()
        let stateWrites = sink.sent.filter { $0[0] == 0x01 }.count
        #expect(stateWrites >= 5)
    }

    @Test func publishNeverBlocksItsCallerEvenWhenTheWriteStalls() {
        let sink = LockedSink()
        let lights = KeyboardLights(sink: sink, palette: { .default }, interval: 60)
        sink.gate = DispatchSemaphore(value: 0)
        lights.start() // its first tick stalls inside send
        let start = Date()
        for _ in 0..<20 { lights.publish(states) }
        #expect(Date().timeIntervalSince(start) < 0.5)
        for _ in 0..<50 { sink.gate?.signal() }
        lights.drain()
    }
}
