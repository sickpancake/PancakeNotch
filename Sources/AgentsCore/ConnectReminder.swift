import FileWatching
import Foundation
import Observation

/// Reminds you to connect a tool that only shows up in Agents after Connect (issue #78). Today that's
/// Devin: Claude Code and Codex are read from their own files, so they show up without it.
///
/// It notices the tool when PancakeNotch starts, when you come back to it, when its window opens, and,
/// while the tool isn't on this Mac yet, the moment its app or folders appear (`FolderEntryWatcher`: the
/// folders they'd sit in, nothing below them, no polling). The watch stops once the tool is found or
/// you've said Not Now. Finding it costs a few file checks; the hook files are read only once it's there.
@MainActor
@Observable
public final class ConnectReminder {
    /// The tools reminded about, in order.
    public static let tools: [AgentTool] = [.devin]

    /// Tools on this Mac at the last check.
    public private(set) var found: Set<AgentTool> = []
    /// The tool just connected from a reminder, for a moment's "connected" note with what to do next.
    /// Not saved: it goes with Done, or when the note leaves the screen.
    public private(set) var justConnected: AgentTool?
    /// Asked once per tool when it's first found and not connected, so the notch can show its strip.
    /// Returns whether the strip showed; if not (the notch was open, Agents is off), it's asked again at
    /// the next check.
    @ObservationIgnored public var onRemind: (@MainActor (AgentTool) -> Bool)?

    @ObservationIgnored private let settings: AgentsSettings
    @ObservationIgnored private let connector: @MainActor () -> AgentConnector
    @ObservationIgnored private let home: URL
    /// `/Applications`; a stand-in folder in tests.
    @ObservationIgnored private let applications: String
    @ObservationIgnored private let isPreview: Bool
    @ObservationIgnored private var watcher: FolderEntryWatcher?
    @ObservationIgnored private let queue = DispatchQueue(label: "io.github.sickpancake.PancakeNotch.connect-reminder")

    /// - Parameter connector: made only once a tool is found (it reads every tool's hook files).
    public convenience init(settings: AgentsSettings, home: URL = FileManager.default.homeDirectoryForCurrentUser,
                            connector: @escaping @MainActor () -> AgentConnector) {
        self.init(settings: settings, home: home, applications: "/Applications", connector: connector)
    }

    init(settings: AgentsSettings, home: URL, applications: String, connector: @escaping @MainActor () -> AgentConnector) {
        self.settings = settings
        self.home = home
        self.applications = applications
        self.connector = connector
        isPreview = false
    }

    private init(preview tool: AgentTool?, settings: AgentsSettings) {
        self.settings = settings
        home = URL(fileURLWithPath: "/var/empty")
        applications = "/var/empty"
        let connector = AgentConnector.preview(tool.map { [$0: .notConnected] } ?? [:], settings: settings)
        self.connector = { connector }
        isPreview = true
        found = tool.map { [$0] } ?? []
    }

    /// Pretend: `tool` is on this Mac and not connected. Connect only changes what's shown; nothing is
    /// read or watched.
    public static func preview(_ tool: AgentTool?, settings: AgentsSettings) -> ConnectReminder {
        ConnectReminder(preview: tool, settings: settings)
    }

    /// The tool to remind about now: on this Mac, not connected, and not put off with Not Now.
    public var tool: AgentTool? {
        Self.tools.first { tool in
            found.contains(tool) && !settings.connectRemindersDone.contains(tool) && connector().state(tool) == .notConnected
        }
    }

    /// Why the last Connect didn't work, in plain words.
    public var problem: String? {
        tool == nil ? nil : connector().problem
    }

    /// Looks for the tools again (a few file checks), shows the notch's strip for one that's new, and
    /// watches for the ones still to come.
    public func check() {
        if !isPreview {
            let now = Set(Self.tools.filter { isOnMac($0) })
            if now != found { found = now }
            // A tool installed since the connector last looked, or connected in its own settings meanwhile.
            if now.contains(where: { !settings.connectRemindersDone.contains($0) }) { connector().refresh() }
        }
        if let tool, !settings.notchRemindedTools.contains(tool), onRemind?(tool) == true {
            settings.notchRemindedTools.insert(tool)
        }
        updateWatch()
    }

    /// Connects the tool reminded about. Returns whether it worked; if not, `problem` says why.
    @discardableResult
    public func connect() -> Bool {
        guard let tool else { return false }
        let done = connector().connect(tool)
        if done {
            settings.connectRemindersDone.insert(tool)
            justConnected = tool
        } else {
            check()
        }
        return done
    }

    /// Not Now: no more reminders for this tool. Connect stays in Agents' settings.
    public func notNow() {
        guard let tool else { return }
        settings.connectRemindersDone.insert(tool)
        updateWatch()
    }

    /// The "connected" note was read (Done) or left the screen.
    public func finish() {
        if justConnected != nil { justConnected = nil }
    }

    /// Whether the watch is on, for tests.
    var isWatching: Bool { watcher != nil }

    // MARK: Finding

    private func isOnMac(_ tool: AgentTool) -> Bool {
        switch tool {
        case .devin: AccountFinder.hasDevin(home: home, applications: applications)
        case .claude, .codex, .cursor, .github: false
        }
    }

    private func paths(_ tool: AgentTool) -> [String] {
        switch tool {
        case .devin: AccountFinder.devinPaths(home: home, applications: applications)
        case .claude, .codex, .cursor, .github: []
        }
    }

    /// Watches only while a tool could still turn up and be reminded about; a fresh watcher each time,
    /// so a folder created meanwhile (`~/.config`) is watched in its parent's place.
    private func updateWatch() {
        watcher?.stop()
        watcher = nil
        let waiting = Self.tools.filter { !found.contains($0) && !settings.connectRemindersDone.contains($0) }
        guard !isPreview, !waiting.isEmpty else { return }
        watcher = FolderEntryWatcher(paths: waiting.flatMap(paths), queue: queue) { [weak self] in
            Task { @MainActor in self?.check() }
        }
    }
}
