import AppKit
import ApplicationServices

enum Output {
    static let NX_KEYTYPE_SOUND_UP: Int32 = 0
    static let NX_KEYTYPE_SOUND_DOWN: Int32 = 1
    static let NX_KEYTYPE_PLAY: Int32 = 16
    static let NX_KEYTYPE_NEXT: Int32 = 17
    static let NX_KEYTYPE_PREVIOUS: Int32 = 18

    /// Prompts for Accessibility (needed to post key events) if not yet trusted.
    @discardableResult static func ensureAccessibility() -> Bool {
        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
    }

    /// Posts key down + key up.
    static func key(_ code: CGKeyCode, flags: CGEventFlags = []) {
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)
            e?.flags = flags
            e?.post(tap: .cghidEventTap)
        }
    }

    static func copy() { key(8, flags: .maskCommand) }  // kVK_ANSI_C
    static func paste() { key(9, flags: .maskCommand) } // kVK_ANSI_V

    /// Pass one of the NX_KEYTYPE_* constants.
    static func mediaKey(_ key: Int32) {
        for down in [true, false] {
            let state: Int32 = down ? 0xa : 0xb
            let event = NSEvent.otherEvent(
                with: .systemDefined, location: .zero,
                modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(state) << 8),
                timestamp: 0, windowNumber: 0, context: nil,
                subtype: 8, data1: Int((key << 16) | (state << 8)), data2: -1)
            event?.cgEvent?.post(tap: .cghidEventTap)
        }
    }

    /// Fire-and-forget `shortcuts run <name>`.
    static func runShortcut(_ name: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        p.arguments = ["run", name]
        try? p.run()
    }

    /// Blocks until `shortcuts list` finishes; call off the main thread.
    static func listShortcuts() -> [String] {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        p.arguments = ["list"]
        let pipe = Pipe()
        p.standardOutput = pipe
        guard (try? p.run()) != nil else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile() // read before wait, or a full pipe deadlocks
        p.waitUntilExit()
        return String(decoding: data, as: UTF8.self).split(separator: "\n").map(String.init)
    }
}
