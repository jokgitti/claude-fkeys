import Foundation

public struct RGB: Equatable, Sendable, Codable {
    public var r: UInt8
    public var g: UInt8
    public var b: UInt8

    public init(r: UInt8, g: UInt8, b: UInt8) {
        self.r = r
        self.g = g
        self.b = b
    }

    public init?(hex: String) {
        var digits = hex
        if digits.hasPrefix("#") { digits.removeFirst() }
        guard digits.count == 6, digits.allSatisfy(\.isHexDigit), let value = UInt32(digits, radix: 16) else { return nil }
        self.init(
            r: UInt8((value >> 16) & 0xFF),
            g: UInt8((value >> 8) & 0xFF),
            b: UInt8(value & 0xFF)
        )
    }

    public var hex: String {
        String(format: "#%02x%02x%02x", Int(r), Int(g), Int(b))
    }

    public init(from decoder: Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        guard let parsed = RGB(hex: text) else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "expected #rrggbb, got '\(text)'")
            )
        }
        self = parsed
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(hex)
    }
}

/// Waiting-state pulse: a triangle wave between `floor` (0-255, the
/// brightness scale at the trough) and 255, repeating every `periodMs`.
/// Each field falls back to its default on its own when missing or out of range.
public struct PulseSettings: Equatable, Sendable, Codable {
    public static let periodRange = 50...10_000
    public static let floorRange = 0...255

    public var periodMs: Int
    public var floor: Int

    public static let `default` = PulseSettings(periodMs: 700, floor: 0)

    public init(periodMs: Int, floor: Int) {
        self.periodMs = periodMs
        self.floor = floor
    }

    private enum CodingKeys: String, CodingKey {
        case periodMs = "period_ms"
        case floor
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let period = (try? c.decode(Int.self, forKey: .periodMs)).flatMap { Self.periodRange.contains($0) ? $0 : nil }
        let floor = (try? c.decode(Int.self, forKey: .floor)).flatMap { Self.floorRange.contains($0) ? $0 : nil }
        self.periodMs = period ?? Self.default.periodMs
        self.floor = floor ?? Self.default.floor
    }
}

public struct Palette: Equatable, Sendable, Codable {
    public var off: RGB
    public var working: RGB
    public var idle: RGB
    public var waiting: RGB
    public var pulse: PulseSettings

    public init(off: RGB, working: RGB, idle: RGB, waiting: RGB, pulse: PulseSettings = .default) {
        self.off = off
        self.working = working
        self.idle = idle
        self.waiting = waiting
        self.pulse = pulse
    }

    private enum CodingKeys: String, CodingKey {
        case off, working, idle, waiting, pulse
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        off = try c.decode(RGB.self, forKey: .off)
        working = try c.decode(RGB.self, forKey: .working)
        idle = try c.decode(RGB.self, forKey: .idle)
        waiting = try c.decode(RGB.self, forKey: .waiting)
        pulse = (try? c.decode(PulseSettings.self, forKey: .pulse)) ?? .default
    }

    /// `idle` is dim on purpose (config/palette.json ships the same value).
    /// The firmware's compiled-in idle is still #00d75f: it only shows when a
    /// SET_STATES arrives with no SET_PALETTE, which this daemon never sends.
    public static let `default` = Palette(
        off: RGB(r: 0, g: 0, b: 0),
        working: RGB(r: 255, g: 149, b: 0),
        idle: RGB(r: 0, g: 47, b: 21),
        waiting: RGB(r: 255, g: 0, b: 170)
    )

    /// A missing or malformed file falls back to the default: a typo in the
    /// config must not leave the F-row dark with no explanation. A bad `pulse`
    /// block falls back alone and keeps the colours.
    public static func load(from url: URL) -> Palette {
        guard let data = try? Data(contentsOf: url),
              let parsed = try? JSONDecoder().decode(Palette.self, from: data)
        else { return .default }
        return parsed
    }
}
