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

public struct Palette: Equatable, Sendable, Codable {
    public var off: RGB
    public var working: RGB
    public var idle: RGB
    public var waiting: RGB

    public init(off: RGB, working: RGB, idle: RGB, waiting: RGB) {
        self.off = off
        self.working = working
        self.idle = idle
        self.waiting = waiting
    }

    public static let `default` = Palette(
        off: RGB(r: 0, g: 0, b: 0),
        working: RGB(r: 255, g: 149, b: 0),
        idle: RGB(r: 0, g: 215, b: 95),
        waiting: RGB(r: 255, g: 0, b: 170)
    )

    /// A missing or malformed file falls back to the default: a typo in the
    /// config must not leave the F-row dark with no explanation.
    public static func load(from url: URL) -> Palette {
        guard let data = try? Data(contentsOf: url),
              let parsed = try? JSONDecoder().decode(Palette.self, from: data)
        else { return .default }
        return parsed
    }
}
