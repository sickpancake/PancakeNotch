import AppKit
import Carbon.HIToolbox
import Testing
@testable import HotKey

struct HotKeyTests {
    @Test func displaysModifiersInMacOrder() throws {
        let hotKey = try #require(HotKey(keyCode: UInt32(kVK_ANSI_N), modifiers: [.command, .shift, .option, .control], keyLabel: "N"))
        #expect(hotKey.displayString == "⌃⌥⇧⌘N")
    }

    @Test func convertsToCarbonModifiers() throws {
        let hotKey = try #require(HotKey(keyCode: UInt32(kVK_ANSI_N), modifiers: [.command, .option], keyLabel: "N"))
        #expect(hotKey.carbonModifiers == UInt32(cmdKey | optionKey))
    }

    @Test func plainLettersAreRejected() {
        #expect(HotKey(keyCode: UInt32(kVK_ANSI_N), modifiers: [], keyLabel: "N") == nil)
        #expect(HotKey(keyCode: UInt32(kVK_ANSI_N), modifiers: [.shift], keyLabel: "N") == nil)
    }

    @Test func functionKeysWorkAlone() {
        #expect(HotKey(keyCode: UInt32(kVK_F5), modifiers: [], keyLabel: "F5") != nil)
    }

    @Test func ignoresOtherModifierFlags() throws {
        let hotKey = try #require(HotKey(keyCode: UInt32(kVK_ANSI_N), modifiers: [.command, .capsLock, .function], keyLabel: "N"))
        #expect(hotKey.modifierFlags == .command)
    }

    @Test func survivesSaving() throws {
        let hotKey = try #require(HotKey(keyCode: UInt32(kVK_Space), modifiers: [.option], keyLabel: "Space"))
        let data = try JSONEncoder().encode(hotKey)
        #expect(try JSONDecoder().decode(HotKey.self, from: data) == hotKey)
    }
}
