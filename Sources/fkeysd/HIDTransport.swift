import Foundation
import IOKit.hid
import FKeysCore

/// Writes 32-byte output reports to the GMMK Pro's QMK raw HID interface.
///
/// That interface only exists once custom QMK firmware is flashed; on stock
/// Glorious firmware `open()` returns false and the daemon runs without lights.
final class HIDTransport {
    private static let vendorID = 0x320F
    private static let productID = 0x5044
    private static let usagePage = 0xFF60   // QMK raw HID
    private static let usage = 0x61

    private var manager: IOHIDManager?
    private var device: IOHIDDevice?

    var isOpen: Bool { device != nil }

    @discardableResult
    func open() -> Bool {
        close()
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let criteria: [String: Any] = [
            kIOHIDVendorIDKey as String: Self.vendorID,
            kIOHIDProductIDKey as String: Self.productID,
            kIOHIDPrimaryUsagePageKey as String: Self.usagePage,
            kIOHIDPrimaryUsageKey as String: Self.usage,
        ]
        IOHIDManagerSetDeviceMatching(manager, criteria as CFDictionary)
        guard IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess,
              let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>,
              let first = devices.first
        else {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            return false
        }
        self.manager = manager
        self.device = first
        return true
    }

    /// Report id 0, as QMK raw HID expects.
    func send(_ report: [UInt8]) -> Bool {
        precondition(report.count == HIDProtocol.reportSize)
        guard let device else { return false }
        let result = report.withUnsafeBufferPointer { buffer in
            IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, 0, buffer.baseAddress!, buffer.count)
        }
        if result != kIOReturnSuccess {
            // The keyboard was probably unplugged. Drop the handle so the next
            // open() re-matches instead of writing to a dead device forever.
            close()
            return false
        }
        return true
    }

    func close() {
        device = nil
        if let manager {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        manager = nil
    }
}
