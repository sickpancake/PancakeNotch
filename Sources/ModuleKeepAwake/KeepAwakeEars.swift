import KeepAwakeCore
import NotchCore
import SwiftUI

/// Keep Awake's compact ear: the cup, inside a draining ring while a timed session runs. Nothing ticks: the
/// ring is drawn by the render server.
struct KeepAwakeEar: View {
    let module: KeepAwakeModule
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        let center = module.center
        Group {
            if center.session?.end != nil {
                KeepAwakeDial(module: module, size: 17, lineWidth: 1.5, cupScale: 0.46)
            } else {
                // Dim while off (the short shrink after a click, a strip after it ended): the bright cup
                // means it keeps the Mac awake.
                Image(systemName: KeepAwakeDial.symbol(center))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(center.isHolding ? 0.9 : 0.45))
            }
        }
        .frame(width: width, height: height)
        .accessibilityHidden(true)
    }
}

/// The strip under the compact notch when Keep Awake stopped by itself: the time ran out, or the battery
/// is low. Hovering or clicking the notch opens the page.
struct KeepAwakePeek: View {
    let reason: KeepAwakeEnd

    var body: some View {
        let text = KeepAwakeModule.stripText(reason)
        ViewThatFits(in: .horizontal) {
            line(text.title, text.detail)
            line(text.title, nil)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(text.spoken))
    }

    private func line(_ title: String, _ detail: String?) -> some View {
        HStack(spacing: 6) {
            Image(systemName: reason == .batteryLow ? "battery.25" : "cup.and.heat.waves")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .fixedSize()
            if let detail {
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
                    .fixedSize()
            }
        }
    }
}
