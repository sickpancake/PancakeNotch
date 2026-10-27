import AgentsCore
import ConvertKit
import ModuleShelf
import NotchCore
import NowPlayingCore
import SwiftUI

/// Quick fixes for the common problems (ADR-0027). Each card checks how things are right now and
/// offers the fix that applies, so no button shows that can't help. The website has the long answers.
struct HelpView: View {
    let context: AppContext
    @Environment(\.openURL) private var openURL

    private var navigation: AppNavigation { context.navigation }

    var body: some View {
        AppPage(
            title: String(localized: "Help"),
            subtitle: String(localized: "Quick fixes for the common problems. Each one checks how things are right now.")
        ) {
            notchCard
            musicCard
            shelfCard
            agentsCard
            connectCard
            aiUsageCard
            shortcutCard
            updatesCard
            startOverCard
            stillStuckCard
        }
    }

    // MARK: The notch

    @ViewBuilder
    private var notchCard: some View {
        let preferences = context.preferences
        SettingsCard(header: String(localized: "The notch doesn't appear")) {
            if !preferences.notchEnabled {
                SettingsRow(
                    title: String(localized: "The notch is switched off"),
                    subtitle: String(localized: "Turn it on and it's back straight away.")
                ) {
                    Button(String(localized: "Turn It On")) { preferences.notchEnabled = true }
                }
            } else {
                SettingsRow(
                    title: String(localized: "The notch is switched on"),
                    subtitle: String(localized: "Rest the pointer on the notch at the top of the screen to open it.")
                ) {
                    StatusCheck()
                }
            }
            SettingsRow(
                title: String(localized: "Use the MacBook's own screen"),
                subtitle: String(localized: "With an external display, move the pointer up to the top of the MacBook's screen.")
            ) {
                EmptyView()
            }
            if preferences.fullScreenHiding != .never {
                SettingsRow(
                    title: String(localized: "It hides in full screen"),
                    subtitle: preferences.fullScreenHiding == .always
                        ? String(localized: "Set to hide whenever an app fills the screen. Your keyboard shortcut still opens it, except over apps on your hide list.")
                        : String(localized: "While a full-screen video plays, it hides until you move the pointer.")
                ) {
                    Button(String(localized: "Notch Settings")) { navigation.section = .notch }
                }
            }
            MoreOnlineRow(topic: .notchNotShowing)
        }
    }

    // MARK: Music

    @ViewBuilder
    private var musicCard: some View {
        let settings = context.nowPlayingSettings
        let center = context.nowPlaying
        SettingsCard(header: String(localized: "Music doesn't show")) {
            if !settings.isEnabled {
                SettingsRow(
                    title: String(localized: "Now Playing is switched off"),
                    subtitle: String(localized: "Turn it on to see and control what's playing in the notch.")
                ) {
                    Button(String(localized: "Turn It On")) { settings.isEnabled = true }
                }
            } else {
                switch center.connection {
                case .connected, .practice:
                    SettingsRow(
                        title: String(localized: "Now Playing is connected"),
                        subtitle: String(localized: "Play something in Music, Spotify or your browser and it shows up in the notch.")
                    ) {
                        StatusCheck()
                    }
                case .starting:
                    SettingsRow(title: String(localized: "Connecting…"), subtitle: String(localized: "This takes a second or two.")) {
                        EmptyView()
                    }
                case .limited:
                    SettingsRow(
                        title: String(localized: "Only Music and Spotify show"),
                        subtitle: String(localized: "macOS isn't sharing what other apps play right now. Trying again often fixes it.")
                    ) {
                        Button(String(localized: "Try Again")) { center.retryConnection() }
                    }
                case .unavailable:
                    SettingsRow(
                        title: String(localized: "PancakeNotch can't see what's playing"),
                        subtitle: String(localized: "Trying again often fixes it. If not, quit PancakeNotch and open it again.")
                    ) {
                        Button(String(localized: "Try Again")) { center.retryConnection() }
                    }
                }
                if center.needsAutomationPermission {
                    SettingsRow(
                        title: String(localized: "Allow control of Music and Spotify"),
                        subtitle: String(localized: "macOS asked once. To change your answer, switch PancakeNotch on under Automation.")
                    ) {
                        Button(String(localized: "Allow Control…")) { HelpLinks.openAutomationSettings() }
                    }
                }
            }
            MoreOnlineRow(topic: .musicNotDetected)
        }
    }

    // MARK: Shelf

    @ViewBuilder
    private var shelfCard: some View {
        let settings = context.shelfSettings
        let store = context.shelfStore
        SettingsCard(header: String(localized: "The Shelf")) {
            if !settings.isEnabled {
                SettingsRow(
                    title: String(localized: "The Shelf is switched off"),
                    subtitle: String(localized: "Turn it on to keep files, text and links in the notch.")
                ) {
                    Button(String(localized: "Turn It On")) { settings.isEnabled = true }
                }
            } else {
                if !MissionControlDragGuard.isNeeded {
                    SettingsRow(
                        title: String(localized: "A drop doesn't land"),
                        subtitle: String(localized: "Dragging to the very top of the screen can open Mission Control instead. Drop a little lower, on the open notch, or turn off \"Drag windows to top of screen to enter Mission Control\" in Desktop & Dock.")
                    ) {
                        Button(String(localized: "Open Desktop & Dock")) { HelpLinks.openDesktopAndDockSettings() }
                    }
                } else if settings.dragToTop == .allowMissionControl {
                    SettingsRow(
                        title: String(localized: "Mission Control opens instead"),
                        subtitle: String(localized: "Dragging into the menu bar opens Mission Control, because Shelf settings let it. Drop a little lower, on the open notch, or let the Shelf keep the pointer below the menu bar.")
                    ) {
                        Button(String(localized: "Keep Mission Control Away")) { settings.dragToTop = .openShelf }
                    }
                } else {
                    SettingsRow(
                        title: String(localized: "A drop doesn't land"),
                        subtitle: String(localized: "While you drag something to the notch, the pointer stops just below the menu bar so Mission Control doesn't start. Let go over the open notch.")
                    ) {
                        EmptyView()
                    }
                }
                if settings.convertEnabled {
                    SettingsRow(
                        title: String(localized: "Convert says \"Too big\""),
                        subtitle: String(localized: "Converting runs in a small helper so PancakeNotch stays light. Set Quality to Smaller file in Shelf settings and big photos shrink enough to fit.")
                    ) {
                        Button(String(localized: "Use Smaller File")) { settings.convertQuality = .smaller }
                            .disabled(settings.convertQuality == .smaller)
                    }
                }
                SettingsRow(
                    title: String(localized: "An item disappeared"),
                    subtitle: String(localized: "The Shelf only remembers where files are. Moved or renamed files stay; a deleted file leaves the Shelf the next time the notch opens.")
                ) {
                    EmptyView()
                }
                SettingsRow(
                    title: store.items.count >= ShelfStore.capacity
                        ? String(localized: "The Shelf is full")
                        : String(localized: "It holds \(ShelfStore.capacity) items"),
                    subtitle: String(localized: "\(store.items.count) of \(ShelfStore.capacity) now. When it's full, the notch shows what didn't fit and lets you make room.")
                ) {
                    EmptyView()
                }
            }
            MoreOnlineRow(topic: .shelf)
        }
    }

    // MARK: Agents and AI Usage

    @ViewBuilder
    private var agentsCard: some View {
        let settings = context.agentsSettings
        SettingsCard(header: String(localized: "Agents")) {
            if !settings.agentsEnabled {
                SettingsRow(
                    title: String(localized: "Agents is switched off"),
                    subtitle: String(localized: "Turn it on to see your AI agents in the notch and answer their requests.")
                ) {
                    Button(String(localized: "Turn It On")) { settings.agentsEnabled = true }
                }
            } else {
                SettingsRow(
                    title: String(localized: "What Agents shows"),
                    subtitle: String(localized: "Every Claude Code, Codex and Cursor thread: working, needs you or done, with its subagents tucked under it. Allow once or Deny a request right in the notch, or click a thread to go to its app.")
                ) {
                    EmptyView()
                }
            }
            MoreOnlineRow(topic: .agents)
        }
    }

    /// What Connect does, and a Disconnect for each tool that has it.
    @ViewBuilder
    private var connectCard: some View {
        let connector = context.connector
        let connected = AgentTool.allCases.filter { connector.state($0) == .connected }
        SettingsCard(header: String(localized: "Connecting your AI tools")) {
            SettingsRow(
                title: String(localized: "What Connect does"),
                subtitle: String(localized: "It adds a small helper to the tool's hooks, so alerts are instant and you can Allow once or Deny right in the notch. Without it, Claude Code and Codex are followed from their own files.")
            ) {
                EmptyView()
            }
            ForEach(connected, id: \.self) { tool in
                SettingsRow(
                    title: String(localized: "\(tool.name) is connected"),
                    subtitle: tool == .codex
                        ? String(localized: "In Codex, type /hooks once and trust PancakeNotch's hooks. Disconnect takes the helper out again.")
                        : String(localized: "Disconnect takes the helper out again and leaves everything else in its hooks alone.")
                ) {
                    Button(String(localized: "Disconnect")) { connector.disconnect(tool) }
                        .accessibilityLabel(Text("Disconnect \(tool.name)"))
                }
            }
            if connected.isEmpty {
                SettingsRow(
                    title: String(localized: "Nothing is connected"),
                    subtitle: String(localized: "Connect a tool in Modules, under Agents settings.")
                ) {
                    Button(String(localized: "Open Modules")) { navigation.section = .modules }
                }
            }
            if let problem = connector.problem {
                SettingsRow(title: String(localized: "That didn't work"), subtitle: problem) {
                    EmptyView()
                }
            }
            MoreOnlineRow(topic: .agentsConnect)
        }
        .onAppear { connector.refresh() }
    }

    @ViewBuilder
    private var aiUsageCard: some View {
        let settings = context.agentsSettings
        SettingsCard(header: String(localized: "AI Usage")) {
            if !settings.usageEnabled {
                SettingsRow(
                    title: String(localized: "AI Usage is switched off"),
                    subtitle: String(localized: "Turn it on to see your plan limits and how many tokens you use.")
                ) {
                    Button(String(localized: "Turn It On")) { settings.usageEnabled = true }
                }
            }
            SettingsRow(
                title: String(localized: "How it finds your accounts"),
                subtitle: String(localized: "It looks for Claude Code and Codex folders in your home folder, like .claude and .codex. Missing one? Add its folder under AI Usage settings in Modules.")
            ) {
                EmptyView()
            }
            SettingsRow(
                title: String(localized: "What API value means"),
                subtitle: String(localized: "What your tokens would cost if you paid per use. Plan accounts, like Claude Pro or Max and ChatGPT Plus or Pro, don't pay it.")
            ) {
                EmptyView()
            }
            SettingsRow(
                title: String(localized: "It all stays on this Mac"),
                subtitle: String(localized: "PancakeNotch reads token counts and model names from files your tools already keep. It never saves what you or the agent wrote. When you open AI Usage, Codex is asked for its current limits (Codex checks with OpenAI); PancakeNotch itself sends nothing.")
            ) {
                EmptyView()
            }
            MoreOnlineRow(topic: .aiUsage)
        }
    }

    // MARK: Keyboard shortcut

    @ViewBuilder
    private var shortcutCard: some View {
        SettingsCard(header: String(localized: "The keyboard shortcut")) {
            if let hotKey = context.shortcuts.shortcut {
                SettingsRow(
                    title: String(localized: "Your shortcut is \(hotKey.displayString)"),
                    subtitle: String(localized: "If it does nothing, another app may already use it. Pick a different one.")
                ) {
                    Button(String(localized: "Change Shortcut")) { navigation.section = .keyboard }
                }
            } else {
                SettingsRow(
                    title: String(localized: "No shortcut yet"),
                    subtitle: String(localized: "Set one to open the notch from anywhere, even while it's hidden in full screen.")
                ) {
                    Button(String(localized: "Set a Shortcut")) { navigation.section = .keyboard }
                }
            }
        }
    }

    // MARK: Updates

    private var updatesCard: some View {
        UpdatesCard(updates: context.updates)
    }

    // MARK: Start over

    @ViewBuilder
    private var startOverCard: some View {
        SettingsCard(header: String(localized: "Start over")) {
            SettingsRow(
                title: String(localized: "The welcome"),
                subtitle: String(localized: "The short first-run tour of the notch basics.")
            ) {
                Button(String(localized: "Show Welcome Again")) { context.progress.showWelcomeAgain() }
            }
            SettingsRow(
                title: String(localized: "Practice in Learn"),
                subtitle: String(localized: "Hands-on lessons for the notch, the Shelf, Now Playing, Agents and AI Usage.")
            ) {
                Button(String(localized: "Open Learn")) { navigation.section = .learn }
            }
            if context.progress.homeBoxHidden {
                SettingsRow(
                    title: String(localized: "The Learn box on Home"),
                    subtitle: String(localized: "You hid it. It shows how many lessons are done.")
                ) {
                    Button(String(localized: "Show It Again")) { context.progress.homeBoxHidden = false }
                }
            }
        }
    }

    // MARK: Still stuck

    @ViewBuilder
    private var stillStuckCard: some View {
        SettingsCard(
            header: String(localized: "Still stuck?"),
            footer: String(localized: "The report opens in your browser with your app version, macOS version and Mac model filled in. Nothing is sent until you submit it.")
        ) {
            SettingsRow(
                title: String(localized: "Online help"),
                subtitle: String(localized: "Step-by-step answers for everything above, and more.")
            ) {
                Button { openURL(HelpLinks.helpPage) } label: {
                    Label(String(localized: "Open Help Site"), systemImage: "arrow.up.right")
                        .labelStyle(TrailingIconLabelStyle())
                }
            }
            SettingsRow(
                title: String(localized: "Report a problem"),
                subtitle: String(localized: "Tell us what happened on GitHub.")
            ) {
                Button { openURL(HelpLinks.reportProblem) } label: {
                    Label(String(localized: "Report a Problem"), systemImage: "arrow.up.right")
                        .labelStyle(TrailingIconLabelStyle())
                }
            }
        }
    }
}

/// The last row of a card: the topic's longer answer on the website.
private struct MoreOnlineRow: View {
    let topic: HelpTopic
    @Environment(\.openURL) private var openURL

    var body: some View {
        SettingsRow(title: String(localized: "More help online"), subtitle: String(localized: "Step by step, on the PancakeNotch website.")) {
            Button { openURL(HelpLinks.url(topic)) } label: {
                Label(String(localized: "Read More"), systemImage: "arrow.up.right")
                    .labelStyle(TrailingIconLabelStyle())
            }
        }
    }
}

/// A small white tick: this part is fine.
private struct StatusCheck: View {
    var body: some View {
        Image(systemName: "checkmark")
            .font(.app(size: 11, weight: .bold))
            .foregroundStyle(Color.black)
            .frame(width: 22, height: 22)
            .background(Color.white, in: .circle)
            .accessibilityLabel(Text("OK"))
    }
}

/// Shared wording for when updates were last checked.
enum UpdatesText {
    static func lastCheck(_ date: Date?, automatic: Bool) -> String {
        let schedule = automatic
            ? String(localized: "It checks once a day.")
            : String(localized: "Automatic checks are off.")
        guard let date else { return String(localized: "Not checked yet. \(schedule)") }
        let when = date.formatted(.relative(presentation: .named))
        return String(localized: "Last checked \(when). \(schedule)")
    }
}
