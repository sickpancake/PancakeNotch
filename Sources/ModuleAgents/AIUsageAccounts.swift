import AgentsCore
import SwiftUI

/// Two letters on a gray disc: the same gray for the same account.
struct AccountCircle: View {
    let account: AgentAccount
    let size: CGFloat

    var body: some View {
        Text(account.initials)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(.white.opacity(AIUsageText.circleShade(for: account)), in: Circle())
            .accessibilityHidden(true)
    }
}

/// The account in the band: the tool, the name, a small circle when the tool has several accounts, and a
/// chevron. A click opens the account menu. With one account there is nothing to choose, so it's a label.
struct AccountPill: View {
    let module: AIUsageModule
    @State private var isHovered = false

    var body: some View {
        let center = module.center
        let account = center.selectedAccount
        let name = account?.name ?? String(localized: "All accounts", comment: "AI Usage: every account at once")
        if center.accounts.count > 1 {
            Button {
                module.toggleMenu()
            } label: {
                label(center, account: account, name: name, canChoose: true)
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }
            .help(Text("Choose an account"))
            .accessibilityLabel(Text("Account: \(EmailPrivacy.masked(name))"))
            .accessibilityHint(Text("Opens the list of accounts."))
        } else {
            label(center, account: account, name: name, canChoose: false)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Account: \(EmailPrivacy.masked(name))"))
        }
    }

    private func label(_ center: UsageCenter, account: AgentAccount?, name: String, canChoose: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: account?.tool.symbol ?? "person.2")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
            // A click on the pill opens the menu; emails are shown in full from there.
            PrivateText(name, revealed: module.revealsEmails)
                .font(.system(size: 11.5, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.tail)
            if let account, center.hasSeveralAccounts(account.tool) {
                AccountCircle(account: account, size: 14)
            }
            if canChoose {
                Image(systemName: "chevron.down")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 22)
        .background(.white.opacity(canChoose && isHovered ? 0.16 : 0.08), in: Capsule())
        .contentShape(Capsule())
    }
}

// MARK: Menu

/// The scrim and the account menu, over the right side of the open panel. A click anywhere else on the
/// panel closes it.
struct AccountMenuOverlay: View {
    let module: AIUsageModule
    let layout: AgentsLayout

    private static let topInset: CGFloat = 6
    private static let trailingInset: CGFloat = 10

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.opacity(0.4)
                .contentShape(.rect)
                .onTapGesture { module.closeMenu() }
                .accessibilityHidden(true)
            // As wide as the band beside the notch, starting at the top: lower down it could be wider, but
            // then a few accounts would no longer fit above the panel's bottom edge.
            AccountMenu(module: module, maxHeight: layout.body.height - Self.topInset - 8)
                .frame(width: layout.bandSideWidth + 4)
                .padding(.top, Self.topInset)
                .padding(.trailing, Self.trailingInset)
                // The menu's own clicks don't reach the scrim.
                .onTapGesture {}
        }
    }
}

private struct AccountMenu: View {
    let module: AIUsageModule
    let maxHeight: CGFloat

    var body: some View {
        let center = module.center
        let rows = VStack(alignment: .leading, spacing: 0) {
            AllAccountsRow(module: module)
            ForEach(AgentTool.allCases.filter { tool in center.accounts.contains { $0.tool == tool } }, id: \.self) { tool in
                Text(tool.name)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.45))
                    .padding(.horizontal, 5)
                    .padding(.top, 4)
                    .padding(.bottom, 1)
                    .accessibilityAddTraits(.isHeader)
                ForEach(center.accounts.filter { $0.tool == tool }) { account in
                    AccountMenuRow(module: module, account: account)
                }
            }
        }
        .padding(4)
        // Taller than the panel (many accounts): scroll.
        ScrollViewReader { proxy in
            ViewThatFits(in: .vertical) {
                rows
                PanelScroll(isSnapshot: module.isSnapshot) { rows }
            }
            .onChange(of: module.focusedAccount) { _, choice in proxy.scrollTo(choice) }
        }
        .frame(maxHeight: maxHeight)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(.black)
                .strokeBorder(.white.opacity(0.16), lineWidth: 1)
        )
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityLabel(Text("Accounts"))
        .accessibilityAction(.escape) { module.closeMenu() }
    }
}

/// One choice in the menu: highlight on hover, a check when it's the current one.
private struct MenuChoice<Content: View>: View {
    let module: AIUsageModule
    let selection: AccountSelection
    let label: String
    let height: CGFloat
    @ViewBuilder let content: Content
    @State private var isHovered = false

    var body: some View {
        let isCurrent = module.center.selection == selection
        HStack(spacing: 5) {
            Image(systemName: "checkmark")
                .font(.system(size: 8.5, weight: .bold))
                .opacity(isCurrent ? 1 : 0)
                .frame(width: 9)
            content
        }
        .padding(.horizontal, 5)
        .frame(height: height)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(isHovered || module.focusedAccount == selection ? 0.14 : 0), in: .rect(cornerRadius: 7, style: .continuous))
        .contentShape(.rect(cornerRadius: 7, style: .continuous))
        .onHover { isHovered = $0; if $0 { module.focus(selection) } }
        .onTapGesture { module.choose(selection) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label))
        .accessibilityAddTraits(isCurrent ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { module.choose(selection) }
        .id(selection)
    }
}

private struct AllAccountsRow: View {
    let module: AIUsageModule

    var body: some View {
        let title = String(localized: "All accounts", comment: "AI Usage: every account at once")
        MenuChoice(module: module, selection: .all, label: title, height: 26) {
            Image(systemName: "person.2")
                .font(.system(size: 9, weight: .semibold))
                .frame(width: 20, height: 20)
                .background(.white.opacity(0.18), in: Circle())
                .accessibilityHidden(true)
            Text(title)
                .font(.system(size: 12.5, weight: .semibold))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }
}

private struct AccountMenuRow: View {
    let module: AIUsageModule
    let account: AgentAccount

    var body: some View {
        let limits = module.center.limits[account.id]
        let session = limits?.limits.first { $0.kind == .session }
        let weekly = limits?.limits.first { $0.kind == .weekly }
        let spoken = [EmailPrivacy.masked(account.name), account.email.map(EmailPrivacy.masked), account.isDefaultName ? nil : account.plan,
                      session.map { "\($0.label) \(AIUsageText.left($0, now: .now))" },
                      weekly.map { "\($0.label) \(AIUsageText.left($0, now: .now))" }]
            .compactMap { $0 }.joined(separator: ", ")
        // A name that already is the email isn't repeated: the plan takes the second line.
        let namedByEmail = account.email == account.name
        MenuChoice(module: module, selection: .account(account.id), label: spoken, height: 30) {
            AccountCircle(account: account, size: 20)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 4) {
                    PrivateText(account.name, revealed: module.revealsEmails, toggle: module.toggleEmails)
                        .font(.system(size: 11.5, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(namedByEmail ? .middle : .tail)
                    if let plan = account.plan, !namedByEmail, !account.isDefaultName {
                        Text(plan)
                            .font(.system(size: 10.5))
                            .foregroundStyle(.white.opacity(0.6))
                            .lineLimit(1)
                            .fixedSize()
                            .layoutPriority(1)
                    }
                }
                if let second = namedByEmail ? account.plan : account.email {
                    PrivateText(second, revealed: module.revealsEmails, toggle: module.toggleEmails)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if session != nil || weekly != nil {
                VStack(spacing: 3) {
                    TinyBar(limit: session)
                    TinyBar(limit: weekly)
                }
                .accessibilityHidden(true)
            }
        }
    }
}

/// A 36 pt bar for one limit's share left (nothing where the limit is missing).
private struct TinyBar: View {
    let limit: UsageLimit?

    var body: some View {
        if let limit {
            LeftBar(left: limit.leftPercent(), pace: nil, height: 3).frame(width: 36)
        } else {
            Color.clear.frame(width: 36, height: 3)
        }
    }
}
