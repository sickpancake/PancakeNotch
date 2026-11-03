import Foundation
import IOKit.ps
import IOKit.pwr_mgt

/// What the Mac is kept from doing.
public enum PowerHoldKind: Equatable, Sendable {
    /// The screen stays on, and so the Mac stays awake (`PreventUserIdleDisplaySleep`).
    case screen
    /// Only idle system sleep is held off: the screen dims, sleeps and locks as usual
    /// (`PreventUserIdleSystemSleep`).
    case system
}

/// Holds the Mac awake, or lets it go. The real one is an IOKit power assertion; tests and practice use
/// one that only remembers.
@MainActor
public protocol PowerHolding: AnyObject {
    /// `nil` lets the Mac sleep as usual. Setting the same kind again does nothing.
    func hold(_ kind: PowerHoldKind?)
}

/// A public IOKit power assertion, no admin rights (ADR-0041). macOS drops it by itself if the app quits
/// or crashes, so the Mac never stays awake for a process that's gone. It shows in `pmset -g assertions`
/// as "PancakeNotch Keep Awake".
@MainActor
public final class PowerAssertion: PowerHolding {
    private var id = IOPMAssertionID(0)
    private var current: PowerHoldKind?

    public init() {}

    public func hold(_ kind: PowerHoldKind?) {
        guard kind != current else { return }
        release()
        guard let kind else { return }
        let type = kind == .screen ? kIOPMAssertPreventUserIdleDisplaySleep : kIOPMAssertPreventUserIdleSystemSleep
        var newID = IOPMAssertionID(0)
        let result = IOPMAssertionCreateWithName(type as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), "PancakeNotch Keep Awake" as CFString, &newID)
        guard result == kIOReturnSuccess else { return }
        id = newID
        current = kind
    }

    private func release() {
        if current != nil { IOPMAssertionRelease(id) }
        id = 0
        current = nil
    }
}

/// A stand-in that holds nothing: practice copies, snapshots and tests (which read `kind`).
@MainActor
public final class PretendPowerHold: PowerHolding {
    public private(set) var kind: PowerHoldKind?
    /// Every change, for tests.
    public private(set) var changes: [PowerHoldKind?] = []

    public init() {}

    public func hold(_ kind: PowerHoldKind?) {
        guard kind != self.kind else { return }
        self.kind = kind
        changes.append(kind)
    }
}

/// On battery or plugged in, and how full the battery is.
public struct PowerState: Equatable, Sendable {
    /// Running on the battery (not on the power adapter).
    public var onBattery: Bool
    /// The built-in battery's charge in percent, or `nil` when there's no battery.
    public var percent: Int?

    public init(onBattery: Bool, percent: Int?) {
        self.onBattery = onBattery
        self.percent = percent
    }

    /// A Mac on the power adapter (or one without a battery).
    public static let pluggedIn = PowerState(onBattery: false, percent: nil)

    /// Read from IOKit now.
    public static func current() -> PowerState {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else { return .pluggedIn }
        let onBattery = (IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String?) == kIOPSBatteryPowerValue
        var percent: Int?
        let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] ?? []
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  description[kIOPSIsPresentKey] as? Bool != false,
                  let current = description[kIOPSCurrentCapacityKey] as? Int,
                  let max = description[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }
            percent = Int((Double(current) / Double(max) * 100).rounded())
        }
        return PowerState(onBattery: onBattery, percent: percent)
    }
}

/// Tells when the power source or the battery's charge changes, from IOKit's run-loop notification: no
/// polling (AGENTS.md rule 2). It fires about once per percent, and on plugging in or out.
@MainActor
public final class PowerSourceWatcher {
    private var source: CFRunLoopSource?
    private var box: Unmanaged<Box>?

    private final class Box {
        let changed: @MainActor () -> Void
        init(_ changed: @escaping @MainActor () -> Void) { self.changed = changed }
    }

    public init() {}

    /// Starts telling `changed` (on the main thread). Calling it again replaces the callback.
    public func start(_ changed: @escaping @MainActor () -> Void) {
        stop()
        let box = Unmanaged.passRetained(Box(changed))
        let callback: IOPowerSourceCallbackType = { context in
            guard let context else { return }
            let box = Unmanaged<Box>.fromOpaque(context).takeUnretainedValue()
            // Added to the main run loop, so this runs on the main thread.
            MainActor.assumeIsolated { box.changed() }
        }
        guard let loopSource = IOPSNotificationCreateRunLoopSource(callback, box.toOpaque())?.takeRetainedValue() else {
            box.release()
            return
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), loopSource, .defaultMode)
        self.source = loopSource
        self.box = box
    }

    public func stop() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode) }
        source = nil
        box?.release()
        box = nil
    }
}
