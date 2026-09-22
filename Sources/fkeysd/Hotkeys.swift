import AppKit
import Carbon.HIToolbox

/// System-wide F1–F12 hotkeys via Carbon RegisterEventHotKey.
///
/// Chosen over CGEventTap because RegisterEventHotKey needs no Accessibility
/// grant. It does need a process attached to the window server, which is why
/// main.swift sets an .accessory activation policy and runs an NSApplication.
final class HotkeyManager {
    /// Index 0 is F1.
    private static let virtualKeyCodes: [UInt32] = [
        UInt32(kVK_F1),  UInt32(kVK_F2),  UInt32(kVK_F3),  UInt32(kVK_F4),
        UInt32(kVK_F5),  UInt32(kVK_F6),  UInt32(kVK_F7),  UInt32(kVK_F8),
        UInt32(kVK_F9),  UInt32(kVK_F10), UInt32(kVK_F11), UInt32(kVK_F12),
    ]
    private static let signature: OSType = 0x464B_5953 // 'FKYS'

    /// Set before calling registerFunctionKeys(). The argument is 1...12.
    var onPress: ((Int) -> Void)?

    private var refs: [EventHotKeyRef?] = []
    private var handler: EventHandlerRef?

    /// Returns how many of the 12 keys were registered. Fewer than 12 means
    /// something else on the system already owns those combinations.
    @discardableResult
    func registerFunctionKeys() -> Int {
        installHandler()
        var registered = 0
        for (index, code) in Self.virtualKeyCodes.enumerated() {
            let id = EventHotKeyID(signature: Self.signature, id: UInt32(index + 1))
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(code, 0, id, GetEventDispatcherTarget(), 0, &ref)
            if status == noErr {
                refs.append(ref)
                registered += 1
            } else {
                FileHandle.standardError.write("fkeysd: F\(index + 1) not registered (OSStatus \(status))\n".data(using: .utf8)!)
            }
        }
        return registered
    }

    private func installHandler() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetEventDispatcherTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let status = GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &id
            )
            guard status == noErr, id.signature == HotkeyManager.signature else {
                return OSStatus(eventNotHandledErr)
            }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(context).takeUnretainedValue()
            manager.onPress?(Int(id.id))
            return noErr
        }, 1, &spec, context, &handler)
    }
}
