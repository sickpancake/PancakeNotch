import AgentsCore
import AppKit
import ModuleAgents
import SwiftUI

/// Agents on the Modules page: a practice notch with pretend threads, what it does with its switch,
/// and its settings while it's on.
struct AgentsModuleCard: View {
    let context: AppContext
    @Binding var showsSettings: Bool
    let learn: () -> Void

    private let points = [
        String(localized: "Follows Claude Code and Codex from their own files, and Cursor after Connect"),
        String(localized: "A count beside the notch tells you who is working or needs you"),
        String(localized: "Allow once or Deny a request without leaving your app"),
        String(localized: "Click a thread to jump to the app it runs in"),
    ]

    var body: some View {
        ModuleCard(
            context: context,
            moduleID: "agents",
            practice: .agents,
            summary: String(localized: "Every AI agent thread in one list: working, needs you or done. Answer a request right from the notch."),
            points: points,
            inactiveHint: String(localized: "Turn on Agents to try it here."),
            activeHint: String(localized: "These agents are pretend. Hover or click the notch and try Allow once."),
            learnHint: String(localized: "Opens a hands-on Agents lesson on the Learn page."),
            showsSettings: $showsSettings,
            learn: learn
        ) {
            AgentsSettingsRows(settings: context.agentsSettings, connector: context.connector)
        }
    }
}

/// AI Usage on the Modules page, built the same way as Agents.
struct AIUsageModuleCard: View {
    @State private var resetExampleRequest = 0
    let context: AppContext
    @Binding var showsSettings: Bool
    let learn: () -> Void

    private let points = [
        String(localized: "How much of each plan limit is left, for every Claude Code and Codex account"),
        String(localized: "Tokens and API value for today, 7 days or 30 days"),
        String(localized: "A small gauge beside the notch, and a heads-up when an account is nearly out"),
        String(localized: "Read from files on your Mac. Only Codex is asked for fresh limits, by Codex itself"),
    ]

    var body: some View {
        ModuleCard(
            context: context,
            moduleID: "aiUsage",
            practice: .aiUsage,
            resetExampleRequest: resetExampleRequest,
            summary: String(localized: "How much of your AI plans you've used, and what your tokens would cost pay-per-use."),
            points: points,
            inactiveHint: String(localized: "Turn on AI Usage to try it here."),
            activeHint: String(localized: "These accounts are pretend. Hover or click the notch and pick one."),
            learnHint: String(localized: "Opens a hands-on AI Usage lesson on the Learn page."),
            showsSettings: $showsSettings,
            learn: learn
        ) {
            AIUsageSettingsRows(settings: context.agentsSettings, usage: context.usage, connector: context.connector,
                                showResetExample: { resetExampleRequest += 1 })
        }
    }
}

/// One of these modules in one container: its practice notch, what it does with its switch, and a
/// "Settings" dropdown that's there only while it's on.
private struct ModuleCard<Settings: View>: View {
    let context: AppContext
    let moduleID: String
    let practice: PracticeKind
    var resetExampleRequest = 0
    let summary: String
    let points: [String]
    let inactiveHint: String
    let activeHint: String
    let learnHint: String
    @Binding var showsSettings: Bool
    let learn: () -> Void
    @ViewBuilder let settings: Settings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let info = AppContext.moduleInfo(moduleID)
        let isOn = context.isEnabled(moduleID)
        VStack(spacing: 0) {
            NotchStage(
                behavior: context.preferences.notchBehavior,
                arrangement: context.arrangement,
                isActive: isOn,
                // The pretend threads and accounts only while the module is on.
                practice: isOn ? [practice] : [],
                inactiveHint: inactiveHint,
                activeHint: activeHint,
                badge: .practice,
                resetExampleRequest: resetExampleRequest
            )
            .background(Color.black)
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 16, topTrailingRadius: 16, style: .continuous))

            AppPalette.hairline.frame(height: 1)

            ModuleAbout(
                symbol: info.symbol,
                title: info.title,
                summary: summary,
                points: points,
                learnTitle: String(localized: "Try it"),
                learnHint: learnHint,
                isOn: Binding(get: { isOn }, set: { value in withAnimation(animation) { context.setEnabled(moduleID, value) } }),
                learn: learn
            )
            .padding(AppMetrics.cardInset)

            if isOn {
                AppPalette.hairline.frame(height: 1)
                SettingsDisclosure(isOpen: showsSettings, label: String(localized: "\(info.title) settings")) {
                    withAnimation(animation) { showsSettings.toggle() }
                }
                .id(ModulesView.settingsAnchor(moduleID))
                if showsSettings {
                    AppPalette.hairline.frame(height: 1)
                    settings
                        .transition(.opacity)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .glassPanel()
    }

    private var animation: Animation {
        .easeInOut(duration: reduceMotion ? 0.15 : 0.25)
    }
}

/// Rows with hairlines between them, under a module card's "Settings" header.
private struct HairlineRows<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            Group(subviews: content) { rows in
                ForEach(rows) { row in
                    if row.id != rows.first?.id {
                        AppPalette.hairline
                            .frame(height: 1)
                            .padding(.horizontal, AppMetrics.cardInset)
                    }
                    row
                }
            }
        }
    }
}

// MARK: Agents settings

/// Agents' settings: which tools are connected, and when it pops up.
struct AgentsSettingsRows: View {
    @Bindable var settings: AgentsSettings
    let connector: AgentConnector

    var body: some View {
        HairlineRows {
            SettingsRowLabel(
                title: String(localized: "Connect your tools"),
                subtitle: String(localized: "Without Connect, PancakeNotch follows Claude Code and Codex from their own files. Connect adds a small helper to the tool's hooks: instant alerts, and Allow once / Deny right in the notch. Cursor shows up only after Connect.")
            )
            .settingsRowPadding()
            ForEach(AgentTool.allCases, id: \.self) { tool in
                ConnectRow(tool: tool, connector: connector)
            }
            if let problem = connector.problem {
                Label(problem, systemImage: "exclamationmark.triangle")
                    .font(.app(size: 12.5, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .settingsRowPadding()
            }
            SettingsRow(
                title: String(localized: "Name agents by"),
                subtitle: nameSubtitle
            ) {
                MonochromeSegmented(
                    title: String(localized: "Name agents by"),
                    options: AgentNameStyle.allCases.map { ($0, $0.label) },
                    selection: $settings.nameStyle
                )
            }
            SettingsRow(
                title: String(localized: "Under the name"),
                subtitle: detailSubtitle
            ) {
                MonochromeSegmented(
                    title: String(localized: "Under the name"),
                    options: AgentDetailStyle.allCases.map { ($0, $0.label) },
                    selection: $settings.detailStyle
                )
            }
            SettingsRow(
                title: String(localized: "Show agents from"),
                subtitle: String(localized: "Agents from the others are left out of the list, the closed notch and pop-ups.")
            ) {
                MonochromeChips(
                    title: String(localized: "Show agents from"),
                    options: AgentTool.allCases.map { ($0, $0.shortName) },
                    selection: shownTools
                )
            }
            SettingsRow(
                title: String(localized: "Keep finished agents"),
                subtitle: String(localized: "How long a finished agent stays in the list after you've seen it.")
            ) {
                MonochromeSegmented(
                    title: String(localized: "Keep finished agents"),
                    options: KeepFinished.allCases.map { ($0, $0.label) },
                    selection: $settings.keepFinished
                )
            }
            SettingsRow(
                title: String(localized: "Show what each agent is doing"),
                subtitle: String(localized: "A line like \"Editing NotchView.swift\" under a working agent.")
            ) {
                Toggle(String(localized: "Show what each agent is doing"), isOn: $settings.showsSteps)
                    .labelsHidden()
            }
            SettingsRow(
                title: String(localized: "Show subagents"),
                subtitle: String(localized: "The helpers an agent starts, behind a small button under it.")
            ) {
                Toggle(String(localized: "Show subagents"), isOn: $settings.showsSubagents)
                    .labelsHidden()
            }
            SettingsRow(
                title: String(localized: "Pop up when an agent needs you"),
                subtitle: String(localized: "A short note slides out under the notch when a request is waiting.")
            ) {
                Toggle(String(localized: "Pop up when an agent needs you"), isOn: $settings.peeksOnNeedsYou)
                    .labelsHidden()
            }
            SettingsRow(
                title: String(localized: "Pop up when an agent finishes"),
                subtitle: String(localized: "Only after 30 seconds of work or more.")
            ) {
                Toggle(String(localized: "Pop up when an agent finishes"), isOn: $settings.peeksOnFinish)
                    .labelsHidden()
            }
        }
        .onAppear { connector.refresh() }
    }

    /// The tools shown, as the opposite of the hidden ones. At least one always stays on.
    private var shownTools: Binding<Set<AgentTool>> {
        Binding {
            Set(AgentTool.allCases).subtracting(settings.hiddenTools)
        } set: { shown in
            guard !shown.isEmpty else { return }
            settings.hiddenTools = Set(AgentTool.allCases).subtracting(shown)
        }
    }

    private var nameSubtitle: String {
        switch settings.nameStyle {
        case .title: String(localized: "The conversation's title from Claude Code or Codex. Its folder until it has one.")
        case .lastMessage: String(localized: "The last message you sent it. Its title until you send one.")
        case .branch: String(localized: "The git branch it works on. Its title outside a git project.")
        }
    }

    private var detailSubtitle: String {
        switch settings.detailStyle {
        case .folder: String(localized: "Its project folder. Its last message when it's named after the folder.")
        case .lastMessage: String(localized: "The last message you sent it. Its folder until you send one.")
        case .branch: String(localized: "The git branch it works on. Its folder outside a git project.")
        }
    }
}

/// One tool: whether it's on this Mac, and Connect or Disconnect.
private struct ConnectRow: View {
    let tool: AgentTool
    let connector: AgentConnector

    var body: some View {
        let state = connector.state(tool)
        HStack(spacing: 12) {
            Image(systemName: tool.symbol)
                .font(.app(size: 13, weight: .semibold))
                .frame(width: 30, height: 30)
                .background(AppPalette.selection, in: .rect(cornerRadius: 8, style: .continuous))
                .accessibilityHidden(true)
            SettingsRowLabel(title: tool.name, subtitle: subtitle(state))
            HStack(spacing: 8) {
                switch state {
                case .notFound:
                    EmptyView()
                case .notConnected:
                    Button(String(localized: "Connect")) { connector.connect(tool) }
                        .accessibilityLabel(Text("Connect \(tool.name)"))
                case .connected:
                    ConnectedBadge()
                    Button(String(localized: "Disconnect")) { connector.disconnect(tool) }
                        .accessibilityLabel(Text("Disconnect \(tool.name)"))
                }
            }
            .fixedSize()
        }
        .settingsRowPadding()
    }

    private func subtitle(_ state: AgentConnector.State) -> String? {
        switch state {
        case .notFound: String(localized: "Not on this Mac")
        case .notConnected: String(localized: "Not connected")
        case .connected: tool == .codex ? String(localized: "In Codex, type /hooks once and trust PancakeNotch's hooks.") : nil
        }
    }
}

private struct ConnectedBadge: View {
    var body: some View {
        Label(String(localized: "Connected"), systemImage: "checkmark")
            .font(.app(size: 12, weight: .semibold))
            .foregroundStyle(AppPalette.primaryText)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(AppPalette.hover, in: Capsule())
            .overlay(PillOutline(color: AppPalette.hairline))
    }
}

// MARK: AI Usage settings

/// AI Usage's settings: the accounts it found, adding a folder, what the closed notch shows, and the
/// near-limit warning.
struct AIUsageSettingsRows: View {
    @Bindable var settings: AgentsSettings
    let usage: UsageCenter
    let connector: AgentConnector
    var showResetExample: (() -> Void)?
    /// Why the last folder wasn't added.
    @State private var addProblem: String?

    var body: some View {
        HairlineRows {
            if usage.accounts.isEmpty {
                SettingsRowLabel(
                    title: String(localized: "No accounts found yet"),
                    subtitle: String(localized: "They show up once Claude Code or Codex has been used on this Mac. If yours live somewhere else, add the folder below.")
                )
                .settingsRowPadding()
            }
            ForEach(usage.accounts) { account in
                AccountRow(account: account, isAdded: isAdded(account), rename: { rename(account, to: $0) }, remove: { remove(account) })
            }
            SettingsRow(
                title: String(localized: "Add an account folder"),
                subtitle: addProblem ?? String(localized: "For a Claude Code or Codex folder PancakeNotch didn't find, like .claude-work.")
            ) {
                Button(String(localized: "Add Account Folder…"), action: addFolder)
            }
            SettingsRow(
                title: String(localized: "Beside the closed notch"),
                subtitle: earModeSubtitle
            ) {
                MonochromeSegmented(
                    title: String(localized: "Beside the closed notch"),
                    options: UsageEarMode.allCases.map { ($0, $0.label) },
                    selection: $settings.earMode
                )
            }
            SettingsRow(
                title: String(localized: "Account"),
                subtitle: String(localized: "Which account the closed notch and the close-to-limit pop-up follow.")
            ) {
                Menu {
                    Button(String(localized: "Closest to its limit")) { settings.earAccount = .all }
                    ForEach(usage.accounts) { account in
                        Button(accountLabel(account)) { settings.earAccount = .account(account.id) }
                    }
                } label: {
                    Text(earAccountLabel)
                }
                .menuStyle(.button)
                .buttonStyle(PillButtonStyle())
                .accessibilityLabel(Text("Account: \(earAccountLabel)"))
            }
            .disabled(settings.earMode == .never && !settings.warnsNearLimit)
            SettingsRow(
                title: String(localized: "Limit"),
                subtitle: String(localized: "Session is the 5-hour limit. Closest is whichever has less left.")
            ) {
                MonochromeSegmented(
                    title: String(localized: "Limit"),
                    options: UsageEarLimit.allCases.map { ($0, $0.label) },
                    selection: $settings.earLimit
                )
            }
            .disabled(settings.earMode == .never && !settings.warnsNearLimit)
            SettingsRow(
                title: String(localized: "Pop up when an account is close to its limit"),
                subtitle: String(localized: "Once, under 10% left, for the account and limit above.")
            ) {
                Toggle(String(localized: "Pop up when an account is close to its limit"), isOn: $settings.warnsNearLimit)
                    .labelsHidden()
            }
            SettingsRow(
                title: String(localized: "Pop up when a limit resets"),
                subtitle: String(localized: "For any account and limit you used. A short strip shows the account, plan and what reset, even over full-screen apps. Recent resets catch up within 30 minutes.")
            ) {
                HStack(spacing: 12) {
                    if let showResetExample {
                        Button(String(localized: "Show example"), action: showResetExample)
                            .buttonStyle(PillButtonStyle())
                            .disabled(!settings.usageEnabled)
                            .help(String(localized: "Play a pretend reset in the practice notch above."))
                    }
                    Toggle(String(localized: "Pop up when a limit resets"), isOn: $settings.peeksOnReset)
                        .labelsHidden()
                }
            }
            Label(String(localized: "Everything stays on this Mac. PancakeNotch saves token counts and model names, never what you or the agent wrote."), systemImage: "lock")
                .font(.app(size: 12.5))
                .foregroundStyle(AppPalette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .settingsRowPadding()
        }
    }

    private var earModeSubtitle: String {
        switch settings.earMode {
        case .never: String(localized: "AI Usage shows only when you open the notch.")
        case .nearLimit: String(localized: "A small gauge while the account below has under 10% left.")
        case .always: String(localized: "A small gauge with what's left of the account below, all the time.")
        }
    }

    /// "Claude · Work", with emails half hidden.
    private func accountLabel(_ account: AgentAccount) -> String {
        account.isDefaultName ? account.name : "\(account.tool.shortName) · \(EmailPrivacy.masked(account.name))"
    }

    private var earAccountLabel: String {
        if case .account(let id) = settings.earAccount, let account = usage.accounts.first(where: { $0.id == id }) {
            return accountLabel(account)
        }
        return String(localized: "Closest to its limit")
    }

    private func rename(_ account: AgentAccount, to name: String) {
        settings.setNickname(name, for: account.id)
        usage.renamed()
    }

    /// Whether the user added this folder (then they can take it away again).
    private func isAdded(_ account: AgentAccount) -> Bool {
        settings.addedFolders.contains { Self.standardized($0) == account.folder.standardizedFileURL.path }
    }

    private func remove(_ account: AgentAccount) {
        settings.addedFolders.removeAll { Self.standardized($0) == account.folder.standardizedFileURL.path }
        usage.refreshAccounts()
        connector.refresh()
    }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        // The folders are hidden ones (.claude-work).
        panel.showsHiddenFiles = true
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        panel.prompt = String(localized: "Add")
        panel.message = String(localized: "Choose a Claude Code or Codex folder, like .claude-work or .codex.")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let path = url.standardizedFileURL.path
        if AgentsDetection.tool(ofFolder: url) == nil {
            addProblem = String(localized: "That folder isn't a Claude Code or Codex folder.")
        } else if usage.accounts.contains(where: { $0.folder.standardizedFileURL.path == path }) {
            addProblem = String(localized: "That folder is already in your list.")
        } else {
            addProblem = nil
            settings.addedFolders.append(path)
            usage.refreshAccounts()
            connector.refresh()
        }
    }

    private static func standardized(_ path: String) -> String {
        URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL.path
    }
}

/// One account: initials, its name (changeable) and what PancakeNotch knows about it.
private struct AccountRow: View {
    let account: AgentAccount
    let isAdded: Bool
    let rename: (String) -> Void
    let remove: () -> Void
    /// The name being typed; nil when not renaming.
    @State private var draft: String?
    /// The email shows in full after a click on it.
    @State private var revealsEmail = false
    @FocusState private var isTyping: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text(account.initials)
                .font(.app(size: 12, weight: .semibold))
                .frame(width: 34, height: 34)
                .background(AppPalette.selection, in: .circle)
                .overlay(Circle().strokeBorder(AppPalette.hairline))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                if draft != nil {
                    TextField(account.name, text: Binding(get: { draft ?? "" }, set: { draft = $0 }))
                        .textFieldStyle(.plain)
                        .font(.app(size: 13.5, weight: .medium))
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .background(AppPalette.hover, in: .rect(cornerRadius: 8, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(AppPalette.hairlineStrong))
                        .focused($isTyping)
                        .onAppear { isTyping = true }
                        .onSubmit(save)
                        .onExitCommand { draft = nil }
                        .accessibilityLabel(Text("Name for \(EmailPrivacy.masked(account.name))"))
                } else {
                    PrivateText(account.name, revealed: revealsEmail) { revealsEmail.toggle() }
                        .font(.app(size: 13.5, weight: .medium))
                    HStack(spacing: 0) {
                        if let email = account.email, email != account.name {
                            PrivateText(email, revealed: revealsEmail) { revealsEmail.toggle() }
                            if !account.isDefaultName { Text(verbatim: " · ") }
                        }
                        if !account.isDefaultName { Text(details) }
                    }
                    .font(.app(size: 12.5))
                    .foregroundStyle(AppPalette.secondaryText)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) {
                if draft != nil {
                    Button(String(localized: "Cancel")) { draft = nil }
                    Button(String(localized: "Save"), action: save)
                        .buttonStyle(ProminentPillButtonStyle())
                } else {
                    Button(String(localized: "Rename")) { draft = account.name }
                    .accessibilityLabel(Text("Rename \(EmailPrivacy.masked(account.name))"))
                    if isAdded {
                        Button(String(localized: "Remove"), action: remove)
                            .accessibilityLabel(Text("Remove \(EmailPrivacy.masked(account.name))"))
                            .accessibilityHint(Text("Takes this folder off the list. The folder itself stays."))
                    }
                }
            }
            .fixedSize()
        }
        .settingsRowPadding()
    }

    /// "Pro · Claude Code", after the email when the account has been renamed.
    private var details: String {
        [account.plan, account.tool.name]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    /// Empty text restores the provider, tier and optional account number.
    private func save() {
        guard let draft else { return }
        if draft != account.name { rename(draft) }
        self.draft = nil
    }
}
