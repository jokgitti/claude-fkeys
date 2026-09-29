import Foundation

/// The write side of the keyboard link. `HIDTransport` (fkeysd) is the real one.
public protocol ReportSink: AnyObject {
    var isOpen: Bool { get }
    func open() -> Bool
    /// A failed send must leave the sink closed, so the next `open()` re-matches.
    func send(_ report: [UInt8]) -> Bool
}

/// Decides when reports go to the keyboard.
///
/// - `publish` writes only when the twelve states differ from the last ones sent.
/// - `tick` (called on a timer) reopens a closed link, then sends the palette and
///   the current states. On an open link it re-sends the current states: the
///   firmware blanks the board 10 s after the last report, so an unchanged state
///   still needs a write more often than that.
/// - A failed write is not fatal. The link stays closed until `tick` reopens it.
public final class LightPublisher {
    private let sink: ReportSink
    private let palette: () -> Palette
    private let log: (String) -> Void

    private var desired: [KeyState]?
    private var lastSent: [KeyState]?
    private var connected = false

    public init(sink: ReportSink, palette: @escaping () -> Palette, log: @escaping (String) -> Void = { _ in }) {
        self.sink = sink
        self.palette = palette
        self.log = log
    }

    public func publish(_ states: [KeyState]) {
        desired = states
        guard sink.isOpen, states != lastSent else { return }
        sendStates(states)
    }

    public func tick() {
        if !sink.isOpen {
            guard sink.open() else { return }
            guard sink.send(HIDProtocol.encodePalette(palette())) else { markLost(); return }
            lastSent = nil
            if !connected {
                connected = true
                log("keyboard connected")
            }
        }
        if let desired { sendStates(desired) }
    }

    private func sendStates(_ states: [KeyState]) {
        if sink.send(HIDProtocol.encodeStates(states)) {
            lastSent = states
        } else {
            markLost()
        }
    }

    private func markLost() {
        lastSent = nil
        if connected {
            connected = false
            log("keyboard write failed; retrying every tick")
        }
    }
}
