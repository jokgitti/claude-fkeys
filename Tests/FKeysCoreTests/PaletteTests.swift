import Testing
import Foundation
@testable import FKeysCore

@Test func parsesSixDigitHexWithAndWithoutHash() {
    #expect(RGB(hex: "#ff9500") == RGB(r: 255, g: 149, b: 0))
    #expect(RGB(hex: "ff9500") == RGB(r: 255, g: 149, b: 0))
    #expect(RGB(hex: "#FF9500") == RGB(r: 255, g: 149, b: 0))
    #expect(RGB(hex: "#000000") == RGB(r: 0, g: 0, b: 0))
}

@Test func rejectsMalformedHex() {
    #expect(RGB(hex: "") == nil)
    #expect(RGB(hex: "#fff") == nil)
    #expect(RGB(hex: "#ff95000") == nil)
    #expect(RGB(hex: "#gg9500") == nil)
    #expect(RGB(hex: "+f9500") == nil)
    #expect(RGB(hex: "#+f9500") == nil)
    #expect(RGB(hex: "-f9500") == nil)
    #expect(RGB(hex: "f_9500") == nil)
    #expect(RGB(hex: "0xff95") == nil)
}

@Test func hexRoundTrips() {
    #expect(RGB(hex: "#ff9500")?.hex == "#ff9500")
    #expect(RGB(r: 0, g: 215, b: 95).hex == "#00d75f")
}

@Test func defaultPaletteMatchesTheSpec() {
    let p = Palette.default
    #expect(p.off == RGB(hex: "#000000"))
    #expect(p.working == RGB(hex: "#ff9500"))
    #expect(p.idle == RGB(hex: "#00d75f"))
    #expect(p.waiting == RGB(hex: "#ff00aa"))
}

@Test func loadsAPaletteFromDisk() throws {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("palette-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: url) }
    try "{\"off\":\"#010101\",\"working\":\"#020202\",\"idle\":\"#030303\",\"waiting\":\"#040404\"}"
        .write(to: url, atomically: true, encoding: .utf8)

    let p = Palette.load(from: url)
    #expect(p.off == RGB(r: 1, g: 1, b: 1))
    #expect(p.waiting == RGB(r: 4, g: 4, b: 4))
}

@Test func fallsBackToTheDefaultWhenTheFileIsMissingOrBad() throws {
    let missing = URL(fileURLWithPath: "/nonexistent/palette-\(UUID().uuidString).json")
    #expect(Palette.load(from: missing) == Palette.default)

    let bad = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("palette-bad-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: bad) }
    try "{ not json".write(to: bad, atomically: true, encoding: .utf8)
    #expect(Palette.load(from: bad) == Palette.default)
}

@Test func fallsBackToTheDefaultWhenAColorValueIsMalformedHex() throws {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("palette-bad-hex-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: url) }
    try "{\"off\":\"#000000\",\"working\":\"+f9500\",\"idle\":\"#00d75f\",\"waiting\":\"#ff00aa\"}"
        .write(to: url, atomically: true, encoding: .utf8)

    let p = Palette.load(from: url)
    #expect(p == Palette.default)
}

private func loadJSON(_ json: String) throws -> Palette {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("palette-pulse-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: url) }
    try json.write(to: url, atomically: true, encoding: .utf8)
    return Palette.load(from: url)
}

private let colours = "\"off\":\"#010101\",\"working\":\"#020202\",\"idle\":\"#030303\",\"waiting\":\"#040404\""

@Test func readsThePulseBlock() throws {
    let p = try loadJSON("{\(colours),\"pulse\":{\"period_ms\":900,\"floor\":30}}")
    #expect(p.pulse == PulseSettings(periodMs: 900, floor: 30))
    #expect(p.waiting == RGB(r: 4, g: 4, b: 4))
}

@Test func aMissingPulseKeyFallsBackToTheDefaultPulseAndKeepsTheColours() throws {
    let p = try loadJSON("{\(colours)}")
    #expect(p.pulse == .default)
    #expect(p.off == RGB(r: 1, g: 1, b: 1))
}

@Test func outOfRangeOrMalformedPulseValuesFallBackPerField() throws {
    #expect(try loadJSON("{\(colours),\"pulse\":{\"period_ms\":0,\"floor\":30}}").pulse == PulseSettings(periodMs: 700, floor: 30))
    #expect(try loadJSON("{\(colours),\"pulse\":{\"period_ms\":99999,\"floor\":30}}").pulse == PulseSettings(periodMs: 700, floor: 30))
    #expect(try loadJSON("{\(colours),\"pulse\":{\"period_ms\":900,\"floor\":256}}").pulse == PulseSettings(periodMs: 900, floor: 0))
    #expect(try loadJSON("{\(colours),\"pulse\":{\"period_ms\":900,\"floor\":-1}}").pulse == PulseSettings(periodMs: 900, floor: 0))
    #expect(try loadJSON("{\(colours),\"pulse\":{\"period_ms\":\"fast\"}}").pulse == .default)
    #expect(try loadJSON("{\(colours),\"pulse\":5}").pulse == .default)
}

@Test func theShippedConfigIsTheDefaultsWithADimIdle() throws {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("config/palette.json")
    var expected = Palette.default
    expected.idle = RGB(hex: "#002f15")!
    #expect(Palette.load(from: url) == expected)
}
