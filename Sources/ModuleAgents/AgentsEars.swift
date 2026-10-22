import AgentsCore
import SwiftUI

/// A still mark for a thread's status (nothing moves, in the list or the ear): a dotted circle while
/// it works, a white disc with "!" when it needs you, and an outlined circle with a check, a stop
/// square or an x for done, stopped and error.
struct AgentMark: View {
    let status: AgentStatus
    let size: CGFloat

    var body: some View {
        Group {
            switch status {
            case .needsYou:
                Image(systemName: "exclamationmark.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.black, .white)
            case .working:
                Image(systemName: "ellipsis.circle").foregroundStyle(.white.opacity(0.75))
            case .done:
                Image(systemName: "checkmark.circle").foregroundStyle(.white.opacity(0.75))
            case .stopped:
                Image(systemName: "stop.circle").foregroundStyle(.white.opacity(0.75))
            case .failed:
                Image(systemName: "xmark.circle").foregroundStyle(.white.opacity(0.75))
            }
        }
        .font(.system(size: size * 0.92, weight: .regular))
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// The compact ear: the most urgent thing as a mark and a number. Nothing here moves.
struct AgentsEar: View {
    let module: AgentsModule

    var body: some View {
        if let attention = module.center.attention {
            HStack(spacing: 3) {
                AgentMark(status: attention.status, size: 15)
                Text(attention.count > 9 ? "9+" : "\(attention.count)")
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(AgentsText.spoken(attention)))
        } else {
            // The short shrink after a click while nothing is going on.
            Image(systemName: module.symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.45))
                .accessibilityHidden(true)
        }
    }
}

/// The strip under the compact notch when a thread needs you or finishes: its tool, project and what happened.
struct AgentsPeek: View {
    let alert: AgentAlert

    var body: some View {
        let text = AgentsText.peek(alert)
        HStack(spacing: 6) {
            Image(systemName: alert.thread.tool.symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
            Text(text.subject)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .truncationMode(.tail)
            Text(text.verb)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.6))
                .fixedSize()
                .layoutPriority(1)
        }
        .lineLimit(1)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(text.subject) \(text.verb)"))
    }
}
