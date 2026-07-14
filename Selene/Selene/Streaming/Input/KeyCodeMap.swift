import AppKit

/// GameStream's LiSendKeyboardEvent() expects real Windows VK_* codes
/// regardless of platform - this is a protocol requirement, not something
/// any macOS API can hand us directly. macOS keyCodes below are the
/// physical/layout-independent `kVK_*` constants (normally pulled from
/// Carbon/HIToolbox); they're hardcoded here to avoid linking Carbon for a
/// handful of numbers.
enum KeyCodeMap {
    static func winVirtualKey(for macKeyCode: UInt16) -> Int16? {
        table[macKeyCode]
    }

    private static let table: [UInt16: Int16] = [
        // Letters (kVK_ANSI_*)
        0x00: 0x41, // A
        0x0B: 0x42, // B
        0x08: 0x43, // C
        0x02: 0x44, // D
        0x0E: 0x45, // E
        0x03: 0x46, // F
        0x05: 0x47, // G
        0x04: 0x48, // H
        0x22: 0x49, // I
        0x26: 0x4A, // J
        0x28: 0x4B, // K
        0x25: 0x4C, // L
        0x2E: 0x4D, // M
        0x2D: 0x4E, // N
        0x1F: 0x4F, // O
        0x23: 0x50, // P
        0x0C: 0x51, // Q
        0x0F: 0x52, // R
        0x01: 0x53, // S
        0x11: 0x54, // T
        0x20: 0x55, // U
        0x09: 0x56, // V
        0x0D: 0x57, // W
        0x07: 0x58, // X
        0x10: 0x59, // Y
        0x06: 0x5A, // Z

        // Digits
        0x1D: 0x30, // 0
        0x12: 0x31, // 1
        0x13: 0x32, // 2
        0x14: 0x33, // 3
        0x15: 0x34, // 4
        0x17: 0x35, // 5
        0x16: 0x36, // 6
        0x1A: 0x37, // 7
        0x1C: 0x38, // 8
        0x19: 0x39, // 9

        // Punctuation (US ANSI layout)
        0x1B: 0xBD, // - -> VK_OEM_MINUS
        0x18: 0xBB, // = -> VK_OEM_PLUS
        0x21: 0xDB, // [ -> VK_OEM_4
        0x1E: 0xDD, // ] -> VK_OEM_6
        0x2A: 0xDC, // \ -> VK_OEM_5
        0x29: 0xBA, // ; -> VK_OEM_1
        0x27: 0xDE, // ' -> VK_OEM_7
        0x2B: 0xBC, // , -> VK_OEM_COMMA
        0x2F: 0xBE, // . -> VK_OEM_PERIOD
        0x2C: 0xBF, // / -> VK_OEM_2
        0x32: 0xC0, // ` -> VK_OEM_3

        // Control / whitespace
        0x24: 0x0D, // Return -> VK_RETURN
        0x30: 0x09, // Tab -> VK_TAB
        0x31: 0x20, // Space -> VK_SPACE
        0x33: 0x08, // Delete (backspace) -> VK_BACK
        0x35: 0x1B, // Escape -> VK_ESCAPE
        0x39: 0x14, // Caps Lock -> VK_CAPITAL

        // Modifiers (left/right)
        0x38: 0xA0, // Left Shift -> VK_LSHIFT
        0x3C: 0xA1, // Right Shift -> VK_RSHIFT
        0x3B: 0xA2, // Left Control -> VK_LCONTROL
        0x3E: 0xA3, // Right Control -> VK_RCONTROL
        0x3A: 0xA4, // Left Option -> VK_LMENU
        0x3D: 0xA5, // Right Option -> VK_RMENU
        0x37: 0x5B, // Left Command -> VK_LWIN
        0x36: 0x5C, // Right Command -> VK_RWIN

        // Function keys
        0x7A: 0x70, // F1
        0x78: 0x71, // F2
        0x63: 0x72, // F3
        0x76: 0x73, // F4
        0x60: 0x74, // F5
        0x61: 0x75, // F6
        0x62: 0x76, // F7
        0x64: 0x77, // F8
        0x65: 0x78, // F9
        0x6D: 0x79, // F10
        0x67: 0x7A, // F11
        0x6F: 0x7B, // F12

        // Arrows
        0x7B: 0x25, // Left
        0x7E: 0x26, // Up
        0x7C: 0x27, // Right
        0x7D: 0x28, // Down

        // Navigation cluster
        0x72: 0x2D, // Help/Insert -> VK_INSERT
        0x75: 0x2E, // Forward Delete -> VK_DELETE
        0x73: 0x24, // Home -> VK_HOME
        0x77: 0x23, // End -> VK_END
        0x74: 0x21, // Page Up -> VK_PRIOR
        0x79: 0x22, // Page Down -> VK_NEXT

        // Keypad
        0x52: 0x60, // Keypad 0
        0x53: 0x61, // Keypad 1
        0x54: 0x62, // Keypad 2
        0x55: 0x63, // Keypad 3
        0x56: 0x64, // Keypad 4
        0x57: 0x65, // Keypad 5
        0x58: 0x66, // Keypad 6
        0x59: 0x67, // Keypad 7
        0x5B: 0x68, // Keypad 8
        0x5C: 0x69, // Keypad 9
        0x43: 0x6A, // Keypad * -> VK_MULTIPLY
        0x45: 0x6B, // Keypad + -> VK_ADD
        0x4E: 0x6D, // Keypad - -> VK_SUBTRACT
        0x41: 0x6E, // Keypad . -> VK_DECIMAL
        0x4B: 0x6F, // Keypad / -> VK_DIVIDE
        0x4C: 0x0D, // Keypad Enter -> VK_RETURN
    ]
}
