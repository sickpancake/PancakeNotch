import Carbon.HIToolbox

/// Registers one system-wide shortcut with the Carbon hot-key API: works while other apps are in
/// front and needs no Accessibility or Input Monitoring permission.
@MainActor
public final class GlobalHotKey {
    public enum RegistrationError: Error, Equatable {
        /// Another app already uses this shortcut.
        case alreadyTaken
        case failed(OSStatus)
    }

    private static var nextID: UInt32 = 0
    private let registration: Registration
    var eventID: EventHotKeyID { registration.id }

    public init(action: @escaping @MainActor () -> Void) {
        Self.nextID &+= 1
        registration = Registration(id: EventHotKeyID(signature: 0x504E_4348, id: Self.nextID), action: action)
    }

    /// Replaces any current shortcut with `hotKey`.
    public func register(_ hotKey: HotKey) throws(RegistrationError) {
        unregister()
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(registration).toOpaque()
        let handlerStatus = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            let registration = Unmanaged<Registration>.fromOpaque(context).takeUnretainedValue()
            var id = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard status == noErr, id.signature == registration.id.signature, id.id == registration.id.id else {
                return OSStatus(eventNotHandledErr)
            }
            // Carbon delivers hot-key events on the main thread.
            MainActor.assumeIsolated { registration.action() }
            return noErr
        }, 1, &eventType, context, &registration.handlerRef)
        guard handlerStatus == noErr else { throw .failed(handlerStatus) }

        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(hotKey.keyCode, hotKey.carbonModifiers, registration.id, GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else {
            unregister()
            throw status == eventHotKeyExistsErr ? .alreadyTaken : .failed(status)
        }
        registration.hotKeyRef = ref
    }

    public func unregister() {
        registration.clear()
    }
}

/// Carbon retains a raw context pointer. Keep it alive with its handler, and remove both Carbon
/// resources before freeing it, including when a temporary shortcut controller goes away.
/// Access is confined to the main actor and synchronous destruction; this owner also lets Swift 6.0
/// clean up the non-Sendable Carbon handles without an actor-isolated deinitializer.
private final class Registration: @unchecked Sendable {
    let id: EventHotKeyID
    let action: @MainActor () -> Void
    var hotKeyRef: EventHotKeyRef?
    var handlerRef: EventHandlerRef?

    init(id: EventHotKeyID, action: @escaping @MainActor () -> Void) {
        self.id = id
        self.action = action
    }

    func clear() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
        if let handlerRef { RemoveEventHandler(handlerRef) }
        handlerRef = nil
    }

    deinit { clear() }
}
