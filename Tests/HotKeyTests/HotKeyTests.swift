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

    @Test func systemShortcutsAreReserved() throws {
        let quit = try #require(HotKey(keyCode: UInt32(kVK_ANSI_Q), modifiers: .command, keyLabel: "Q"))
        let screenshot = try #require(HotKey(keyCode: UInt32(kVK_ANSI_4), modifiers: [.shift, .command], keyLabel: "4"))
        let spotlight = try #require(HotKey(keyCode: UInt32(kVK_Space), modifiers: .command, keyLabel: "Space"))
        #expect(quit.isReservedBySystem)
        #expect(screenshot.isReservedBySystem)
        #expect(spotlight.isReservedBySystem)
        let firstTab = try #require(HotKey(keyCode: UInt32(kVK_ANSI_1), modifiers: .command, keyLabel: "1"))
        let trash = try #require(HotKey(keyCode: UInt32(kVK_Delete), modifiers: .command, keyLabel: "⌫"))
        #expect(firstTab.isReservedBySystem)
        #expect(trash.isReservedBySystem)
    }

    @Test func systemShortcutsAreReservedOnOtherLayouts() throws {
        // Dvorak types C on the US I key; AZERTY types M on the US semicolon key.
        let dvorakCopy = try #require(HotKey(keyCode: UInt32(kVK_ANSI_I), modifiers: .command, keyLabel: "C"))
        let azertyMinimize = try #require(HotKey(keyCode: UInt32(kVK_ANSI_Semicolon), modifiers: .command, keyLabel: "M"))
        let dvorakFree = try #require(HotKey(keyCode: UInt32(kVK_ANSI_I), modifiers: [.option, .command], keyLabel: "C"))
        #expect(dvorakCopy.isReservedBySystem)
        #expect(azertyMinimize.isReservedBySystem)
        #expect(!dvorakFree.isReservedBySystem)
    }

    @Test func freeShortcutsAreNotReserved() throws {
        let notch = try #require(HotKey(keyCode: UInt32(kVK_ANSI_N), modifiers: [.option, .command], keyLabel: "N"))
        let quitWithOption = try #require(HotKey(keyCode: UInt32(kVK_ANSI_Q), modifiers: [.option, .control], keyLabel: "Q"))
        #expect(!notch.isReservedBySystem)
        #expect(!quitWithOption.isReservedBySystem)
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

    @Test func decodingValidatesSavedShortcuts() {
        for json in [
            #"{"keyCode":45,"modifiers":0,"keyLabel":"N"}"#,
            #"{"keyCode":45,"modifiers":131072,"keyLabel":"N"}"#,
            #"{"keyCode":4294967295,"modifiers":524288,"keyLabel":"N"}"#,
            #"{"keyCode":12,"modifiers":1048576,"keyLabel":"Q"}"#,
        ] {
            #expect(throws: DecodingError.self) { try JSONDecoder().decode(HotKey.self, from: Data(json.utf8)) }
            // ShortcutController uses try?: rejected data falls back to its unassigned default.
            #expect((try? JSONDecoder().decode(HotKey.self, from: Data(json.utf8))) == nil)
        }
    }

    @Test func survivesSaving() throws {
        let hotKey = try #require(HotKey(keyCode: UInt32(kVK_Space), modifiers: [.option], keyLabel: "Space"))
        let data = try JSONEncoder().encode(hotKey)
        #expect(try JSONDecoder().decode(HotKey.self, from: data) == hotKey)
    }
}
