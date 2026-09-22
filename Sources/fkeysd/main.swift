import AppKit
import Foundation
import FKeysCore

let stateDir = URL(fileURLWithPath: NSHomeDirectory())
    .appendingPathComponent(".claude/.fkeys")

let arguments = Array(CommandLine.arguments.dropFirst())

switch arguments.first {
case "status":
    print(Daemon(stateDir: stateDir).statusReport())

case "--help", "-h":
    print("""
    fkeysd — bind F1–F12 to Claude Code sessions in iTerm2

      fkeysd            run the daemon
      fkeysd status     print the current key bindings
    """)

case .none:
    // RegisterEventHotKey needs a window-server connection; .accessory gives one
    // without a Dock icon or a menu bar.
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let daemon = Daemon(stateDir: stateDir)
    daemon.start()
    app.run()

case .some(let unknown):
    FileHandle.standardError.write("fkeysd: unknown command '\(unknown)'\n".data(using: .utf8)!)
    exit(2)
}
