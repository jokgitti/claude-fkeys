import AppKit
import Foundation
import FKeysCore

// Each path is overridable by environment variable, falling back to the
// NSHomeDirectory()-derived default: NSHomeDirectory() ignores $HOME, so a
// test harness needs another way to point the daemon at a temp directory.
let stateDir = ProcessInfo.processInfo.environment["FKEYS_STATE_DIR"].map(URL.init(fileURLWithPath:))
    ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude/.fkeys")
// Outside stateDir on purpose: stateDir is watched, and anything the daemon
// itself writes there re-triggers that watcher. See Daemon.swift's init doc.
let registryURL = ProcessInfo.processInfo.environment["FKEYS_REGISTRY"].map(URL.init(fileURLWithPath:))
    ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude/fkeys-registry.json")
let paletteURL = ProcessInfo.processInfo.environment["FKEYS_PALETTE"].map(URL.init(fileURLWithPath:))
    ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".config/fkeys/palette.json")

func fail(_ message: String) -> Never {
    FileHandle.standardError.write("fkeysd: \(message)\n".data(using: .utf8)!)
    exit(2)
}

func describe(_ report: [UInt8]) -> String {
    report.map { String(format: "%02x", $0) }.joined(separator: " ")
}

/// Send one report, or print it when the keyboard is not reachable.
func sendOrExplain(_ report: [UInt8]) {
    let transport = HIDTransport()
    guard transport.open() else {
        fail("""
        no QMK raw HID interface on 320f:5044 (usage page ff60, usage 61).
        Either the keyboard is unplugged, or it is still on stock firmware.
        The report that would have been sent:
          \(describe(report))
        """)
    }
    guard transport.send(report) else { fail("write failed; keyboard may have been unplugged") }
    print("sent: \(describe(report))")
}

let arguments = Array(CommandLine.arguments.dropFirst())

// A top-level var, not a case-local let: RegisterEventHotKey's callback and
// the reconcile Timer both hold only a weak reference to this Daemon, and a
// local's lifetime past its last syntactic use is unspecified. A top-level
// stored property lives for the process, so app.run() below can't outlive it.
var daemon: Daemon?

switch arguments.first {
case "status":
    print(Daemon(stateDir: stateDir, registryURL: registryURL).statusReport())

case "--dry-run":
    let states = StateStore(dir: stateDir).scan()
    let registry: Registry = (try? Data(contentsOf: registryURL))
        .flatMap { try? JSONDecoder().decode(Registry.self, from: $0) } ?? Registry()
    let keyStates = (1...HIDProtocol.keyCount).map { key in
        KeyState(registry.uuid(forKey: key).flatMap { states[$0] })
    }
    print("SET_PALETTE  \(describe(HIDProtocol.encodePalette(Palette.load(from: paletteURL))))")
    print("SET_STATES   \(describe(HIDProtocol.encodeStates(keyStates)))")

case "poke":
    guard arguments.count == 3,
          let key = Int(arguments[1]), (1...HIDProtocol.keyCount).contains(key)
    else { fail("usage: fkeysd poke <1-12> <off|working|idle|waiting>") }
    let named: [String: KeyState] = ["off": .off, "working": .working, "idle": .idle, "waiting": .waiting]
    guard let state = named[arguments[2]] else {
        fail("unknown state '\(arguments[2])'; expected off, working, idle or waiting")
    }
    var states = [KeyState](repeating: .off, count: HIDProtocol.keyCount)
    states[key - 1] = state
    sendOrExplain(HIDProtocol.encodePalette(Palette.load(from: paletteURL)))
    sendOrExplain(HIDProtocol.encodeStates(states))

case "poke-led":
    guard arguments.count == 3,
          let index = Int(arguments[1]), (0...97).contains(index),
          let colour = RGB(hex: arguments[2])
    else { fail("usage: fkeysd poke-led <0-97> <#rrggbb>") }
    // Reuse SET_PALETTE/SET_STATES: put the colour in the `working` slot, then
    // light only the F-key whose LED index matches. SET_STATES is the only path
    // to addressing an LED, so only the 12 F-row indices can be lit this way.
    guard let key = HIDProtocol.fKeyLEDIndices.firstIndex(of: index) else {
        fail("LED \(index) is not in the F-row table \(HIDProtocol.fKeyLEDIndices)")
    }
    var palette = Palette.load(from: paletteURL)
    palette.working = colour
    var states = [KeyState](repeating: .off, count: HIDProtocol.keyCount)
    states[key] = .working
    sendOrExplain(HIDProtocol.encodePalette(palette))
    sendOrExplain(HIDProtocol.encodeStates(states))

case "--help", "-h":
    print("""
    fkeysd — bind F1–F12 to Claude Code sessions in iTerm2

      fkeysd                          run the daemon
      fkeysd status                   print the current key bindings
      fkeysd --dry-run                print the reports that would be sent
      fkeysd poke <1-12> <state>      force one key's state
      fkeysd poke-led <f-row led> <#hex>   light one F-row LED, to verify indices
    """)

case .none:
    // RegisterEventHotKey needs a window-server connection; .accessory gives one
    // without a Dock icon or a menu bar.
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    daemon = Daemon(stateDir: stateDir, registryURL: registryURL)
    daemon?.start()
    app.run()

case .some(let unknown):
    fail("unknown command '\(unknown)'")
}
