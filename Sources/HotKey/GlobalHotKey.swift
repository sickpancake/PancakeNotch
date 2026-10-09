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

    private let action: @MainActor () -> Void
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    public init(action: @escaping @MainActor () -> Void) {
        self.action = action
    }

    /// Replaces any current shortcut with `hotKey`.
    public func register(_ hotKey: HotKey) throws(RegistrationError) {
        unregister()
        installHandlerIfNeeded()
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: 0x504E_4348, id: 1) // "PNCH"
        let status = RegisterEventHotKey(hotKey.keyCode, hotKey.carbonModifiers, id, GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else {
            throw status == eventHotKeyExistsErr ? .alreadyTaken : .failed(status)
        }
        hotKeyRef = ref
    }

    public func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        // Unretained: the app keeps this object for its whole lifetime.
        let context = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            // Carbon delivers hot-key events on the main thread.
            MainActor.assumeIsolated {
                Unmanaged<GlobalHotKey>.fromOpaque(context).takeUnretainedValue().action()
            }
            return noErr
        }, 1, &eventType, context, &handlerRef)
    }
}
