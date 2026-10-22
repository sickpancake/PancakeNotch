import AgentsCore
import SwiftUI

/// The left column: one account's limits (up to three), or one compact row per account when several are shown.
struct AIUsageLimits: View {
    let module: AIUsageModule

    var body: some View {
        let center = module.center
        let shown = center.shownAccounts
        if shown.count == 1, let account = shown.first {
            AccountLimitRows(account: account, limits: center.limits[account.id])
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Text("% left: session above, weekly below")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.white.opacity(0.45))
                PanelScroll(isSnapshot: module.isSnapshot) {
                    VStack(spacing: 0) {
                        ForEach(shown) { account in
                            AccountSummaryRow(account: account, limits: center.limits[account.id])
                        }
                    }
                }
            }
        }
    }
}

/// A quiet line where the bars would be.
private struct LimitsNote: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(.white.opacity(0.6))
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// "Session · On pace", a bar and "63% left · resets in 2h 14m", for each limit.
private struct AccountLimitRows: View {
    let account: AgentAccount
    let limits: AccountLimits?

    var body: some View {
        switch limits?.state {
        case .available?:
            let rows = limits?.limits.prefix(3) ?? []
            if rows.isEmpty {
                LimitsNote(text: String(localized: "Limits show up after you use \(account.tool.name) once", comment: "AI Usage: limits not seen yet"))
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, limit in
                        // The tool's update time sits on the first row, and only when it's old.
                        LimitRow(limit: limit, updatedAt: index == 0 ? limits?.updatedAt : nil)
                    }
                }
            }
        case .noLimits?:
            LimitsNote(text: String(localized: "Pay as you go: no plan limits", comment: "AI Usage: an account that pays per token"))
        case .notYet?, nil:
            LimitsNote(text: String(localized: "Limits show up after you use \(account.tool.name) once", comment: "AI Usage: limits not seen yet"))
        }
    }
}

private struct LimitRow: View {
    let limit: UsageLimit
    let updatedAt: Date?

    var body: some View {
        // The times move on once a minute while this is on screen.
        TimelineView(.everyMinute) { context in
            let now = context.date
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(AIUsageText.title(limit, now: now))
                        .font(.system(size: 11.5, weight: .semibold))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if let asOf = AIUsageText.asOf(updatedAt, now: now) {
                        Text(asOf)
                            .font(.system(size: 10.5))
                            .foregroundStyle(.white.opacity(0.45))
                            .lineLimit(1)
                    }
                }
                LeftBar(left: limit.leftPercent(now: now), pace: limit.evenLeftPercent(now: now), height: 6)
                Text(AIUsageText.detail(limit, now: now))
                    .font(.system(size: 11.5))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)
        }
    }
}

/// An account in the all-accounts list: its circle, name and plan, and two tiny bars for Session and Weekly.
private struct AccountSummaryRow: View {
    let account: AgentAccount
    let limits: AccountLimits?

    var body: some View {
        HStack(spacing: 8) {
            AccountCircle(account: account, size: 20)
            VStack(alignment: .leading, spacing: 0) {
                Text(account.name)
                    .font(.system(size: 12.5, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text([account.tool.shortName, account.plan].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
        .frame(height: 30)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var trailing: some View {
        switch limits?.state {
        case .available?:
            VStack(alignment: .trailing, spacing: 3) {
                ForEach([UsageLimit.Kind.session, .weekly], id: \.self) { kind in
                    if let limit = limits?.limits.first(where: { $0.kind == kind }) {
                        HStack(spacing: 5) {
                            LeftBar(left: limit.leftPercent(), pace: nil, height: 4)
                                .frame(width: 44)
                            Text("\(AIUsageText.percent(limit.leftPercent()))%")
                                .font(.system(size: 10.5).monospacedDigit())
                                .foregroundStyle(.white.opacity(0.6))
                                .frame(width: 26, alignment: .trailing)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Text("\(limit.label) \(AIUsageText.left(limit, now: .now))"))
                    }
                }
            }
        case .noLimits?:
            note(String(localized: "No plan limits", comment: "AI Usage: an account that pays per token"))
        case .notYet?, nil:
            note(String(localized: "Not seen yet", comment: "AI Usage: limits not seen yet"))
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10.5))
            .foregroundStyle(.white.opacity(0.45))
            .lineLimit(1)
    }
}

/// How much of a limit is left: a track, a white fill and, when known, a thin tick where even use would be.
struct LeftBar: View {
    /// 0…100.
    let left: Double
    /// Where "% left" would be if the limit were used evenly (0…100), or nil for no tick.
    let pace: Double?
    let height: CGFloat

    private static let tickWidth: CGFloat = 1.5
    /// How far the tick reaches above and below the bar.
    private static let tickOverhang: CGFloat = 2

    var body: some View {
        Canvas { context, size in
            let bar = CGRect(x: 0, y: Self.tickOverhang, width: size.width, height: height)
            context.fill(Path(roundedRect: bar, cornerRadius: height / 2), with: .color(.white.opacity(0.12)))
            let filled = bar.width * min(100, max(0, left)) / 100
            if filled > 0 {
                context.fill(Path(roundedRect: CGRect(x: 0, y: bar.minY, width: max(filled, height), height: height), cornerRadius: height / 2),
                             with: .color(.white))
            }
            if let pace {
                let x = min(size.width - Self.tickWidth, max(0, bar.width * min(100, max(0, pace)) / 100 - Self.tickWidth / 2))
                // A black gap on each side keeps the tick visible over the white fill.
                context.fill(Path(CGRect(x: x - 0.75, y: 0, width: Self.tickWidth + 1.5, height: size.height)), with: .color(.black))
                context.fill(Path(CGRect(x: x, y: 0, width: Self.tickWidth, height: size.height)), with: .color(.white.opacity(0.9)))
            }
        }
        .frame(height: height + 2 * Self.tickOverhang)
        // The tick's reach isn't part of the layout.
        .padding(.vertical, -Self.tickOverhang)
        .accessibilityHidden(true)
    }
}
