import Carbon.HIToolbox
import Testing
@testable import HotKey

struct GlobalHotKeyTests {
    @Test @MainActor func routesEventsAndReleasesTemporaryRegistrations() throws {
        var firstCount = 0
        var secondCount = 0
        let first = GlobalHotKey { firstCount += 1 }
        let firstKey = try #require(HotKey(keyCode: UInt32(kVK_F18), modifiers: [.control, .option, .command], keyLabel: "F18"))
        let secondKey = try #require(HotKey(keyCode: UInt32(kVK_F19), modifiers: [.control, .option, .command], keyLabel: "F19"))
        try first.register(firstKey)
        defer { first.unregister() }

        var second: GlobalHotKey? = GlobalHotKey { secondCount += 1 }
        let secondID = try #require(second).eventID
        try #require(second).register(secondKey)
        #expect(send(first.eventID) == noErr)
        #expect(firstCount == 1)
        #expect(secondCount == 0)
        #expect(send(secondID) == noErr)
        #expect(secondCount == 1)

        second?.unregister()
        #expect(send(secondID) == eventNotHandledErr)
        try #require(second).register(secondKey)
        second = nil
        // Its handler must be gone as well as the key: no dangling callback or stolen shortcut.
        #expect(send(secondID) == eventNotHandledErr)
        try first.register(secondKey)
        #expect(send(first.eventID) == noErr)
        #expect(firstCount == 2)
        #expect(secondCount == 1)
    }

    /// Sends only to this process's Carbon event target; doesn't synthesize a keyboard press.
    @MainActor private func send(_ id: EventHotKeyID) -> OSStatus {
        var event: EventRef?
        let status = CreateEvent(nil, OSType(kEventClassKeyboard), UInt32(kEventHotKeyPressed), 0, 0, &event)
        guard status == noErr, let event else { return status }
        defer { ReleaseEvent(event) }
        var id = id
        let parameterStatus = SetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                               MemoryLayout<EventHotKeyID>.size, &id)
        guard parameterStatus == noErr else { return parameterStatus }
        return SendEventToEventTarget(event, GetApplicationEventTarget())
    }
}
