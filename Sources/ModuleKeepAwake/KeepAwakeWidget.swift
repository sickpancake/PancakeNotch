import KeepAwakeCore
import NotchCore
import SwiftUI

extension KeepAwakeModule {
    /// Keep Awake on Home (ADR-0042).
    public func homeWidget(_ kind: HomeWidgetKind, size: HomeWidgetSize, context: HomeWidgetContext) -> AnyView? {
        guard kind == .keepAwake else { return nil }
        return AnyView(KeepAwakeWidget(module: self, size: size, isLive: context.isLive))
    }
}

/// Small: whether it's on, and until when. Medium: the dial, the state, and Turn On or Turn Off.
struct KeepAwakeWidget: View {
    let module: KeepAwakeModule
    let size: HomeWidgetSize
    let isLive: Bool

    var body: some View {
        let center = module.center
        let status = KeepAwakeStatus(center)
        switch size {
        case .small, .large:
            HomeSmallFace(caption: Self.smallCaption(center)) {
                Image(systemName: KeepAwakeDial.symbol(center))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(center.isHolding ? 0.9 : 0.6))
                    .contentTransition(.symbolEffect(.replace))
            } value: {
                Text(center.isHolding ? String(localized: "On", comment: "Keep Awake widget") : String(localized: "Off", comment: "Keep Awake widget"))
                    .font(.system(size: 17, weight: .semibold))
                    .contentTransition(.opacity)
            }
            .animation(.easeInOut(duration: 0.2), value: center.isHolding)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(KeepAwakeStatus.spoken(center)))
        case .medium:
            HStack(spacing: 10) {
                // The same 30 pt ring as the Timer, AI Usage and Battery widgets.
                KeepAwakeDial(module: module, size: 30, lineWidth: 3, cupScale: 0.38, isLive: isLive)
                VStack(alignment: .leading, spacing: 1) {
                    Text(center.isHolding ? String(localized: "On", comment: "Keep Awake widget") : String(localized: "Off", comment: "Keep Awake widget"))
                        .font(.system(size: 19, weight: .semibold))
                        .contentTransition(.opacity)
                    Text(status.kind == .off ? module.title : status.detail)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(KeepAwakeStatus.spoken(center)))
                toggle(status)
            }
            .animation(.easeInOut(duration: 0.2), value: center.isHolding)
            .frame(maxHeight: .infinity)
        }
    }

    /// Small's caption: when a timed session ends ("3:13 AM"), short enough for the cell; nothing otherwise,
    /// since the cup already says what it is and On or Off says the rest.
    @MainActor
    static func smallCaption(_ center: KeepAwakeCenter) -> String? {
        guard center.isHolding, let end = center.session?.end else { return nil }
        return KeepAwakeText.time(end)
    }

    /// The same rules as the open page: Turn Off while on; Turn On, dimmed with the reason on a low battery.
    @ViewBuilder private func toggle(_ status: KeepAwakeStatus) -> some View {
        let center = module.center
        if center.isHolding || (status.kind == .batteryLow && center.stoppedForBattery && center.settings.plugIn == .turnBackOn) {
            NotchRoundButton(symbol: "power", label: String(localized: "Turn Off", comment: "Keep Awake"), size: 24) {
                module.user { center.turnOff() }
            }
        } else {
            NotchRoundButton(symbol: "power", label: String(localized: "Turn On", comment: "Keep Awake"), prominent: true, size: 24) {
                module.user { center.turnOn() }
            }
            .disabled(!center.canTurnOn)
            .opacity(center.canTurnOn ? 1 : 0.4)
            .help(center.canTurnOn ? Text(KeepAwakeText.length(center.settings.lastLength)) : Text(status.detail))
        }
    }
}
