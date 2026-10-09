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
