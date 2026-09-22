import Foundation

/// Raw values are the firmware contract. Changing one means reflashing.
public enum KeyState: UInt8, Sendable, Equatable {
    case off = 0
    case working = 1
    case idle = 2
    case waiting = 3

    public init(_ state: SessionState?) {
        switch state {
        case .none:    self = .off
        case .working: self = .working
        case .idle:    self = .idle
        case .waiting: self = .waiting
        }
    }
}

public enum HIDProtocol {
    public static let reportSize = 32
    public static let keyCount = 12

    static let commandSetStates: UInt8 = 0x01
    static let commandSetPalette: UInt8 = 0x02

    /// 12 state bytes, F1 first. The report-id byte is added by the transport,
    /// so byte 0 here is what the firmware sees as `data[0]`.
    public static func encodeStates(_ states: [KeyState]) -> [UInt8] {
        precondition(states.count == keyCount, "expected \(keyCount) states, got \(states.count)")
        var report = [UInt8](repeating: 0, count: reportSize)
        report[0] = commandSetStates
        for (index, state) in states.enumerated() {
            report[1 + index] = state.rawValue
        }
        return report
    }

    /// 4 RGB triples in KeyState raw-value order: off, working, idle, waiting.
    public static func encodePalette(_ palette: Palette) -> [UInt8] {
        var report = [UInt8](repeating: 0, count: reportSize)
        report[0] = commandSetPalette
        for (index, colour) in [palette.off, palette.working, palette.idle, palette.waiting].enumerated() {
            report[1 + index * 3] = colour.r
            report[2 + index * 3] = colour.g
            report[3 + index * 3] = colour.b
        }
        return report
    }
}
