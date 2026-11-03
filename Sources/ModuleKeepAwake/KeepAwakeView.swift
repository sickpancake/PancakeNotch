import KeepAwakeCore
import NotchCore
import SwiftUI

/// Where things sit in the open Keep Awake panel (origin top-left, y down): a band beside the hardware notch
/// with the Screen switch, then the page under it.
struct KeepAwakeLayout: Equatable {
    static let sidePadding: CGFloat = 20
    static let bottomPadding: CGFloat = 14

    let body: CGSize
    let bandHeight: CGFloat
    let notchWidth: CGFloat

    init(_ layout: NotchLayout) {
        body = layout.bodySize(for: .expanded)
        bandHeight = layout.geometry.notchRect.height
        notchWidth = layout.geometry.notchRect.width
    }

    var bandSideWidth: CGFloat { max(0, (body.width - notchWidth) / 2 - Self.sidePadding) }
}

/// The open Keep Awake page: what it's doing and why, Turn On / Turn Off and +30 min, and the lengths.
struct KeepAwakeView: View {
    let module: KeepAwakeModule
    let layout: KeepAwakeLayout

    var body: some View {
        VStack(spacing: 0) {
            band
                .frame(height: layout.bandHeight)
                .padding(.horizontal, KeepAwakeLayout.sidePadding)
            VStack(alignment: .leading, spacing: 14) {
                KeepAwakeState(module: module)
                LengthRow(module: module)
            }
            .padding(.horizontal, KeepAwakeLayout.sidePadding)
            .padding(.bottom, KeepAwakeLayout.bottomPadding)
            .frame(maxHeight: .infinity)
        }
        .frame(width: layout.body.width, height: layout.body.height, alignment: .top)
        .foregroundStyle(.white)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Keep Awake"))
    }

    /// Beside the notch: nothing on the left (the module tabs live there), the Screen switch on the right.
    private var band: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            Color.clear.frame(width: layout.notchWidth)
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                ScreenSwitch(module: module)
            }
            .frame(width: layout.bandSideWidth)
        }
    }
}

/// Screen on · Can sleep, in the style of the Timer's mode switch: the Screen setting, at hand.
private struct ScreenSwitch: View {
    let module: KeepAwakeModule

    var body: some View {
        let settings = module.center.settings
        HStack(spacing: 2) {
            SwitchSegment(title: String(localized: "Screen on", comment: "Keep Awake: the screen stays on"),
                          spoken: String(localized: "Screen stays on"), isSelected: settings.screen == .staysOn) {
                module.user { settings.screen = .staysOn }
            }
            SwitchSegment(title: String(localized: "Can sleep", comment: "Keep Awake: the screen can sleep"),
                          spoken: String(localized: "Screen can sleep and lock"), isSelected: settings.screen == .canTurnOff) {
                module.user { settings.screen = .canTurnOff }
            }
        }
        .padding(2)
        .background(.white.opacity(0.08), in: Capsule())
        .fixedSize()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Screen"))
    }
}

private struct SwitchSegment: View {
    let title: String
    let spoken: String
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
                .foregroundStyle(.white.opacity(isSelected ? 1 : isHovered ? 0.85 : 0.6))
                .padding(.horizontal, 10)
                .frame(height: 20)
                .background(.white.opacity(isSelected ? 0.18 : 0), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel(Text(spoken))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// The ring with the cup, the state in words, and the buttons.
private struct KeepAwakeState: View {
    let module: KeepAwakeModule

    var body: some View {
        let center = module.center
        Group {
            if let end = center.session?.end, module.pageTicks {
                // "min left" changes once a minute, on the minute before the end, only while this page shows
                // (ADR-0041, AGENTS.md rule 2).
                let left = max(0, end.timeIntervalSince(center.now))
                TimelineView(.periodic(from: end.addingTimeInterval(-((left / 60).rounded(.up) + 1) * 60), by: 60)) { context in
                    face(now: context.date)
                }
            } else {
                face(now: center.now)
            }
        }
    }

    private func face(now: Date) -> some View {
        let center = module.center
        let status = KeepAwakeStatus(center)
        return HStack(spacing: 18) {
            KeepAwakeDial(module: module, size: 64, lineWidth: 4)
            VStack(alignment: .leading, spacing: 3) {
                Text(status.title)
                    .font(.system(size: 19, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(detail(status, now: now))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                if let note = note(status) {
                    Text(note)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(KeepAwakeStatus.spoken(center)))
            Spacer(minLength: 0)
            controls(status)
        }
    }

    private func detail(_ status: KeepAwakeStatus, now: Date) -> String {
        guard status.kind == .holding, let left = module.center.remaining(at: now) else { return status.detail }
        return status.detail + " · " + KeepAwakeText.left(left)
    }

    /// What the screen does, said once, plainly (the lock is the part people don't expect).
    private func note(_ status: KeepAwakeStatus) -> String? {
        guard status.kind == .holding else { return nil }
        return module.center.settings.screen == .staysOn
            ? String(localized: "The screen stays on and won't lock by itself", comment: "Keep Awake: what the screen does")
            : String(localized: "The screen can sleep and lock; your Mac keeps working", comment: "Keep Awake: what the screen does")
    }

    @ViewBuilder
    private func controls(_ status: KeepAwakeStatus) -> some View {
        let center = module.center
        HStack(spacing: 8) {
            if status.kind == .holding {
                if center.session?.end != nil {
                    NotchPill(title: String(localized: "+30 min", comment: "Keep Awake: add half an hour"), symbol: "plus") {
                        module.user { center.extend() }
                    }
                    // A day ahead is the most: nothing more to add.
                    .disabled(!center.canExtend)
                    .opacity(center.canExtend ? 1 : 0.4)
                    .help(center.canExtend ? Text("Add 30 minutes") : Text("Keep Awake runs at most a day ahead"))
                    .accessibilityLabel(Text("Add 30 minutes"))
                }
                NotchPill(title: String(localized: "Turn Off", comment: "Keep Awake"), symbol: "power") {
                    module.user { center.turnOff() }
                }
                .accessibilityHint(Text(center.session == nil
                    ? String(localized: "Stays off until this work ends.")
                    : String(localized: "Lets your Mac sleep as usual.")))
            } else {
                NotchPill(title: String(localized: "Turn On", comment: "Keep Awake"), symbol: "power", prominent: true) {
                    module.user { center.turnOn() }
                }
                .disabled(!center.canTurnOn)
                .opacity(center.canTurnOn ? 1 : 0.4)
                .help(Text(KeepAwakeText.length(center.settings.lastLength)))
                .accessibilityHint(Text("Keeps your Mac awake: \(KeepAwakeText.length(center.settings.lastLength))."))
            }
        }
        .fixedSize()
    }
}

/// The lengths as small buttons: each starts (or restarts) a session that long. The one a plain Turn On uses
/// has a faint outline.
private struct LengthRow: View {
    let module: KeepAwakeModule

    var body: some View {
        let center = module.center
        VStack(alignment: .leading, spacing: 6) {
            Text("Keep awake for")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
            HStack(spacing: 6) {
                ForEach(KeepAwakeLength.choices, id: \.self) { length in
                    LengthButton(title: KeepAwakeText.length(length), isLast: center.settings.lastLength == length) {
                        module.user { center.turnOn(length) }
                    }
                    .accessibilityLabel(Text(length.seconds == nil
                        ? String(localized: "Keep awake until I stop")
                        : String(localized: "Keep awake for \(KeepAwakeText.length(length))")))
                    .accessibilityAddTraits(center.settings.lastLength == length ? .isSelected : [])
                }
            }
        }
        .disabled(!center.canTurnOn)
        .opacity(center.canTurnOn ? 1 : 0.4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Keep awake for"))
    }
}

private struct LengthButton: View {
    let title: String
    let isLast: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .frame(height: 26)
                .background(.white.opacity(isHovered ? 0.2 : 0.11), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay {
                    if isLast {
                        RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(.white.opacity(0.28), lineWidth: 1)
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .animation(.easeOut(duration: 0.15), value: isHovered)
        }
        .buttonStyle(PressableStyle())
        .onHover { isHovered = $0 }
    }
}

/// A ring with the cup inside: draining for a timed session, full while it keeps the Mac awake otherwise, a
/// faint track while off. Drawn by the render server (no ticking).
struct KeepAwakeDial: View {
    let module: KeepAwakeModule
    let size: CGFloat
    let lineWidth: CGFloat
    var cupScale: CGFloat = 0.34

    var body: some View {
        let center = module.center
        ZStack {
            DrainingRing(plan: Self.plan(center), epoch: center.clockEpoch, lineWidth: lineWidth, isSnapshot: module.isSnapshot, now: { center.now })
            Image(systemName: Self.symbol(center))
                .font(.system(size: size * cupScale, weight: .semibold))
                .foregroundStyle(.white.opacity(center.isHolding ? 0.9 : 0.45))
                .contentTransition(.symbolEffect(.replace))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    @MainActor
    static func plan(_ center: KeepAwakeCenter) -> RingPlan {
        guard center.isHolding else { return .still(0) }
        if let session = center.session, let end = session.end, let total = session.total, total > 0 {
            return .drain(end: end, total: total)
        }
        return .still(1)
    }

    @MainActor
    static func symbol(_ center: KeepAwakeCenter) -> String {
        if center.isEnabled, center.batteryLow, !center.isHolding { return "battery.25" }
        return center.isHolding ? "cup.and.heat.waves.fill" : "cup.and.heat.waves"
    }
}
