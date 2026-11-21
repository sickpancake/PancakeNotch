import AgentsCore
import NotchCore
import SwiftUI

extension AgentsModule {
    /// Agents on Home (ADR-0042).
    public func homeWidget(_ kind: HomeWidgetKind, size: HomeWidgetSize, context: HomeWidgetContext) -> AnyView? {
        guard kind == .agents else { return nil }
        return AnyView(AgentsWidget(module: self, size: size))
    }
}

extension AIUsageModule {
    /// AI Usage on Home (ADR-0042).
    public func homeWidget(_ kind: HomeWidgetKind, size: HomeWidgetSize, context: HomeWidgetContext) -> AnyView? {
        guard kind == .aiUsage else { return nil }
        return AnyView(AIUsageWidget(module: self, size: size, now: context.now))
    }
}

/// Small: how many agents run or wait. Medium: the agent that matters most and what it's doing.
/// Large: a short list; an agent asking gets Deny and Review. Allow stays on the Agents page, where the
/// whole request is on screen (ADR-0037 security amendment).
struct AgentsWidget: View {
    let module: AgentsModule
    let size: HomeWidgetSize

    private var threads: [AgentThread] {
        // Waiting for you first, then working, then the rest, as the list orders them.
        module.center.threads.sorted { rank($0) < rank($1) }
    }

    private func rank(_ thread: AgentThread) -> Int {
        thread.status.needsYou ? 0 : thread.status.isFinished ? 2 : 1
    }

    var body: some View {
        switch size {
        case .small:
            HomeWidgetTile(symbol: module.symbol, title: module.title,
                           line: AgentsText.shortSummary(module.center.threads)
                               ?? String(localized: "None running", comment: "Home widget: no agents"))
        case .medium:
            VStack(alignment: .leading, spacing: 4) {
                header
                if let top = threads.first {
                    AgentWidgetRow(thread: top)
                } else {
                    empty
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        case .large:
            VStack(alignment: .leading, spacing: 4) {
                header
                if threads.isEmpty {
                    empty
                } else {
                    ForEach(threads.prefix(threads.first?.status.needsYou == true ? 2 : 3)) { thread in
                        AgentWidgetRow(thread: thread)
                            .transition(.opacity)
                    }
                    Spacer(minLength: 0)
                    if let asking = threads.first, asking.status.needsYou {
                        answer(asking)
                    }
                }
            }
            .animation(.easeInOut(duration: 0.2), value: threads.map(\.id))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var header: some View {
        HomeWidgetHeader(symbol: module.symbol, title: module.title)
    }

    private var empty: some View {
        HomeWidgetEmptyLine(String(localized: "No agents running"))
    }

    /// Deny works from here; Review opens Agents, where the whole request and Allow are.
    private func answer(_ thread: AgentThread) -> some View {
        HStack(spacing: 6) {
            if thread.canAnswer {
                NotchPill(title: String(localized: "Deny")) { module.center.deny(thread) }
                    .accessibilityHint(Text("Says no to \(thread.title)."))
            }
            NotchPill(title: String(localized: "Review"), prominent: true) {
                module.notch?.select(module.moduleID)
            }
            .accessibilityHint(Text("Opens Agents, where you see the whole request and can allow it."))
        }
    }
}

/// One agent: its status dot, its name, and its current step (or status) under it.
private struct AgentWidgetRow: View {
    let thread: AgentThread

    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            Circle()
                .fill(StatusColors.color(for: thread.status))
                .frame(width: 6, height: 6)
                .padding(.top, 4)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(thread.title)
                    .font(.system(size: 11.5, weight: .semibold))
                Text(thread.step ?? thread.status.label)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.55))
                    .contentTransition(.opacity)
                    .animation(.easeInOut(duration: 0.2), value: thread.step)
            }
            .lineLimit(1)
            .truncationMode(.tail)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Small: one gauge, the limit with the least left. Medium: the gauge, which limit, and when it resets.
struct AIUsageWidget: View {
    let module: AIUsageModule
    let size: HomeWidgetSize
    let now: Date

    /// The followed limit (Settings) of the account with the least left.
    private var reading: NearLimit? {
        let center = module.center
        return center.accounts.compactMap { account -> NearLimit? in
            guard let limit = center.limits[account.id]?.followed(center.settings.earLimit, now: now) else { return nil }
            return NearLimit(account: account, limit: limit)
        }
        .min { $0.limit.leftPercent(now: now) < $1.limit.leftPercent(now: now) }
    }

    var body: some View {
        if let reading {
            let left = reading.limit.leftPercent(now: now)
            switch size {
            case .small, .large:
                HomeSmallFace(caption: reading.limit.label) {
                    LimitRing(left: left / 100, size: 13)
                } value: {
                    percent(left, size: 17)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(AIUsageText.spoken(reading, now: now)))
            case .medium:
                HStack(spacing: 10) {
                    LimitRing(left: left / 100, size: 30)
                    VStack(alignment: .leading, spacing: 1) {
                        percent(left, size: 19)
                        Text([reading.limit.label, AIUsageText.reset(reading.limit.resetsAt, now: now)].compactMap { $0 }
                            .joined(separator: " · "))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white.opacity(0.55))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(AIUsageText.spoken(reading, now: now)))
            }
        } else if size == .small {
            HomeWidgetTile(symbol: module.symbol, title: module.title,
                           line: module.center.accounts.isEmpty
                               ? String(localized: "No accounts", comment: "Home widget: AI Usage found no accounts")
                               : String(localized: "No limits yet", comment: "Home widget: AI Usage has no limits to show"))
        } else {
            // The same title row and centred line as the other widgets with nothing to show.
            VStack(alignment: .leading, spacing: 4) {
                HomeWidgetHeader(symbol: module.symbol, title: module.title)
                HomeWidgetEmptyLine(module.center.accounts.isEmpty
                    ? String(localized: "No accounts found", comment: "Module Menu status")
                    : String(localized: "No limits yet", comment: "Home widget: AI Usage has no limits to show"))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func percent(_ left: Double, size: CGFloat) -> some View {
        Text("\(AIUsageText.percent(left))% left")
            .font(.system(size: size, weight: .semibold).monospacedDigit())
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .contentTransition(.numericText(value: left))
            .animation(.easeInOut(duration: 0.3), value: AIUsageText.percent(left))
    }
}
