import AppKit
import Carbon.HIToolbox

/// A global keyboard shortcut: a key plus modifiers, saved in preferences.
public struct HotKey: Codable, Equatable, Sendable {
    /// Hardware key code (`kVK_*`), independent of keyboard layout.
    public let keyCode: UInt32
    /// `NSEvent.ModifierFlags` raw value, limited to ⌃ ⌥ ⇧ ⌘.
    public let modifiers: UInt
    /// What the key is called for display, e.g. "N", "Space", "F5".
    public let keyLabel: String

    static let allowedModifiers: NSEvent.ModifierFlags = [.control, .option, .shift, .command]

    /// Returns `nil` for shortcuts that would get in the way of normal typing: anything but a
    /// function key needs ⌃, ⌥ or ⌘.
    public init?(keyCode: UInt32, modifiers: NSEvent.ModifierFlags, keyLabel: String) {
        let modifiers = modifiers.intersection(Self.allowedModifiers)
        let isFunctionKey = Self.functionKeyLabels[keyCode] != nil
        guard isFunctionKey || !modifiers.intersection([.control, .option, .command]).isEmpty else { return nil }
        self.keyCode = keyCode
        self.modifiers = modifiers.rawValue
        self.keyLabel = keyLabel
    }

    /// Builds a shortcut from a key press, or `nil` if it isn't usable as one.
    public init?(event: NSEvent) {
        let keyCode = UInt32(event.keyCode)
        let label = Self.specialKeyLabels[keyCode]
            ?? event.characters(byApplyingModifiers: [])?.uppercased()
            ?? "?"
        self.init(keyCode: keyCode, modifiers: event.modifierFlags, keyLabel: label)
    }

    public var modifierFlags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers) }

    /// E.g. "⌥⌘N", in the standard macOS modifier order.
    public var displayString: String {
        let flags = modifierFlags
        var result = ""
        if flags.contains(.control) { result += "⌃" }
        if flags.contains(.option) { result += "⌥" }
        if flags.contains(.shift) { result += "⇧" }
        if flags.contains(.command) { result += "⌘" }
        return result + keyLabel
    }

    /// Modifiers in the form `RegisterEventHotKey` expects.
    var carbonModifiers: UInt32 {
        let flags = modifierFlags
        var result: UInt32 = 0
        if flags.contains(.control) { result |= UInt32(controlKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        return result
    }

    /// Shortcuts macOS or every app already uses (Quit, Close, Copy, screenshots, Spotlight, Mission
    /// Control, …). Taking one system-wide would break it everywhere, so the recorder refuses them.
    /// Matches the key's position and, for letters and symbols, what it types: app menus match ⌘C by
    /// the letter, so on Dvorak or AZERTY Copy sits on another key than on a US keyboard.
    public var isReservedBySystem: Bool {
        let flags = modifierFlags
        return Self.reserved.contains { reserved in
            guard reserved.modifiers == flags else { return false }
            return reserved.keyCode == keyCode || Self.usLabels[reserved.keyCode] == keyLabel
        }
    }

    /// What the reserved letter and symbol keys type on a US keyboard.
    private static let usLabels: [UInt32: String] = [
        UInt32(kVK_ANSI_Q): "Q", UInt32(kVK_ANSI_W): "W", UInt32(kVK_ANSI_H): "H", UInt32(kVK_ANSI_M): "M",
        UInt32(kVK_ANSI_Comma): ",", UInt32(kVK_ANSI_Grave): "`", UInt32(kVK_ANSI_A): "A", UInt32(kVK_ANSI_C): "C",
        UInt32(kVK_ANSI_V): "V", UInt32(kVK_ANSI_X): "X", UInt32(kVK_ANSI_Z): "Z", UInt32(kVK_ANSI_S): "S",
        UInt32(kVK_ANSI_O): "O", UInt32(kVK_ANSI_N): "N", UInt32(kVK_ANSI_P): "P", UInt32(kVK_ANSI_F): "F",
        UInt32(kVK_ANSI_T): "T", UInt32(kVK_ANSI_D): "D",
        UInt32(kVK_ANSI_1): "1", UInt32(kVK_ANSI_2): "2", UInt32(kVK_ANSI_3): "3", UInt32(kVK_ANSI_4): "4",
        UInt32(kVK_ANSI_5): "5", UInt32(kVK_ANSI_6): "6", UInt32(kVK_ANSI_7): "7", UInt32(kVK_ANSI_8): "8",
        UInt32(kVK_ANSI_9): "9",
    ]

    private static let reserved: [(keyCode: UInt32, modifiers: NSEvent.ModifierFlags)] = {
        let command: [Int] = [
            kVK_ANSI_Q, kVK_ANSI_W, kVK_ANSI_H, kVK_ANSI_M, kVK_ANSI_Comma, kVK_Tab, kVK_Space, kVK_ANSI_Grave,
            kVK_ANSI_A, kVK_ANSI_C, kVK_ANSI_V, kVK_ANSI_X, kVK_ANSI_Z, kVK_ANSI_S, kVK_ANSI_O, kVK_ANSI_N, kVK_ANSI_P,
            kVK_ANSI_F, kVK_ANSI_T, kVK_Delete, // ⌘⌫: Move to Trash
            // ⌘1…⌘9: tabs in browsers and Terminal, pages in this app's window.
            kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5, kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9,
        ]
        let shiftCommand: [Int] = [kVK_ANSI_Q, kVK_ANSI_Z, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5, kVK_Tab]
        let optionCommand: [Int] = [kVK_Escape, kVK_ANSI_D, kVK_ANSI_H, kVK_Space]
        let control: [Int] = [kVK_Space, kVK_UpArrow, kVK_DownArrow, kVK_LeftArrow, kVK_RightArrow]
        let controlCommand: [Int] = [kVK_ANSI_Q, kVK_ANSI_F, kVK_Space]
        func list(_ keys: [Int], _ modifiers: NSEvent.ModifierFlags) -> [(keyCode: UInt32, modifiers: NSEvent.ModifierFlags)] {
            keys.map { (UInt32($0), modifiers) }
        }
        return list(command, .command) + list(shiftCommand, [.shift, .command]) + list(optionCommand, [.option, .command])
            + list(control, .control) + list(controlCommand, [.control, .command])
    }()

    private static let functionKeyLabels: [UInt32: String] = [
        UInt32(kVK_F1): "F1", UInt32(kVK_F2): "F2", UInt32(kVK_F3): "F3", UInt32(kVK_F4): "F4",
        UInt32(kVK_F5): "F5", UInt32(kVK_F6): "F6", UInt32(kVK_F7): "F7", UInt32(kVK_F8): "F8",
        UInt32(kVK_F9): "F9", UInt32(kVK_F10): "F10", UInt32(kVK_F11): "F11", UInt32(kVK_F12): "F12",
        UInt32(kVK_F13): "F13", UInt32(kVK_F14): "F14", UInt32(kVK_F15): "F15", UInt32(kVK_F16): "F16",
        UInt32(kVK_F17): "F17", UInt32(kVK_F18): "F18", UInt32(kVK_F19): "F19", UInt32(kVK_F20): "F20",
    ]

    private static let specialKeyLabels: [UInt32: String] = functionKeyLabels.merging([
        UInt32(kVK_Space): "Space", UInt32(kVK_Return): "↩", UInt32(kVK_Tab): "⇥",
        UInt32(kVK_Delete): "⌫", UInt32(kVK_ForwardDelete): "⌦", UInt32(kVK_Escape): "⎋",
        UInt32(kVK_LeftArrow): "←", UInt32(kVK_RightArrow): "→",
        UInt32(kVK_UpArrow): "↑", UInt32(kVK_DownArrow): "↓",
        UInt32(kVK_Home): "↖", UInt32(kVK_End): "↘",
        UInt32(kVK_PageUp): "⇞", UInt32(kVK_PageDown): "⇟",
    ]) { first, _ in first }
}
