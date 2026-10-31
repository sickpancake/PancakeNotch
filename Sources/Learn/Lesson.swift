import Foundation

/// The hands-on lessons on the app window's Learn page.
public enum LessonID: String, CaseIterable, Identifiable, Sendable {
    case basics, nowPlaying, shelf, agents, aiUsage, timer

    public var id: Self { self }
}

/// Something the lesson noticed the user do. The app maps notch states / Shelf events to these.
public enum LessonSignal: Hashable, Sendable {
    case notchOpened, notchShrunk, notchClosed, shortcutSet,
         shelfItemAdded, shelfItemOpened, shelfItemClosed, shelfMenuOpened,
         shelfDraggedOut, shelfSeveralSelected, shelfCleared,
         musicPaused, musicPlayed, musicSkipped, musicSeeked, musicModeChanged, musicArtworkClicked,
         moduleSwitched,
         agentAllowed, agentOpened, agentsCleared,
         usageAccountsOpened, usageAccountChosen, usageRangeChosen,
         timerStarted, timerPausedAndResumed, timerStopped, timerCustomStarted, stopwatchLapped
}

/// One thing to try in a lesson. It ticks when its `signal` arrives.
public struct LessonStep: Identifiable, Sendable {
    public let id: String
    /// Short and imperative ("Hover to open").
    public let title: String
    /// One or two sentences on how to do it.
    public let detail: String
    /// SF Symbol name.
    public let symbol: String
    public let signal: LessonSignal
    /// Skipping it still lets the lesson count as done (e.g. picking a shortcut is up to you).
    public let isOptional: Bool

    public init(id: String, title: String, detail: String, symbol: String, signal: LessonSignal, isOptional: Bool = false) {
        self.id = id
        self.title = title
        self.detail = detail
        self.symbol = symbol
        self.signal = signal
        self.isOptional = isOptional
    }
}

/// A short, hands-on walk through one part of the app.
public struct Lesson: Identifiable, Sendable {
    public let id: LessonID
    public let title: String
    public let summary: String
    /// SF Symbol name.
    public let symbol: String
    public let steps: [LessonStep]

    public init(id: LessonID, title: String, summary: String, symbol: String, steps: [LessonStep]) {
        self.id = id
        self.title = title
        self.summary = summary
        self.symbol = symbol
        self.steps = steps
    }

    /// Every lesson, in the order the Learn page shows them.
    public static var all: [Lesson] { [basics, nowPlaying, shelf, agents, aiUsage, timer] }

    public static func lesson(_ id: LessonID) -> Lesson {
        switch id {
        case .basics: basics
        case .nowPlaying: nowPlaying
        case .shelf: shelf
        case .agents: agents
        case .aiUsage: aiUsage
        case .timer: timer
        }
    }

    /// Opening, shrinking and closing the notch, plus the keyboard shortcut.
    public static let basics = Lesson(
        id: .basics,
        title: String(localized: "Notch basics", comment: "Lesson title"),
        summary: String(localized: "Open the notch, keep it small, close it.", comment: "Lesson summary"),
        symbol: "rectangle.topthird.inset.filled",
        steps: [
            LessonStep(
                id: "basics.open",
                title: String(localized: "Hover to open", comment: "Lesson step title"),
                detail: String(localized: "Rest the pointer on the notch and it slides open.", comment: "Lesson step detail"),
                symbol: "cursorarrow.rays",
                signal: .notchOpened
            ),
            LessonStep(
                id: "basics.shrink",
                title: String(localized: "Click to keep it small", comment: "Lesson step title"),
                detail: String(localized: "Click an empty spot in the open notch and it shrinks to a small strip that stays put.", comment: "Lesson step detail"),
                symbol: "hand.tap",
                signal: .notchShrunk
            ),
            LessonStep(
                id: "basics.close",
                title: String(localized: "Click again to close", comment: "Lesson step title"),
                detail: String(localized: "Hover or click to open it again, then click an empty spot once more and it closes all the way.", comment: "Lesson step detail"),
                symbol: "xmark.circle",
                signal: .notchClosed
            ),
            LessonStep(
                id: "basics.shortcut",
                title: String(localized: "Pick a shortcut", comment: "Lesson step title"),
                detail: String(localized: "A key combination opens and closes the notch from any app. Set one below, or skip this step.", comment: "Lesson step detail"),
                symbol: "command",
                signal: .shortcutSet,
                isOptional: true
            ),
        ]
    )

    /// Pausing, skipping and jumping around in a pretend song, then moving to another module.
    public static let nowPlaying = Lesson(
        id: .nowPlaying,
        title: String(localized: "Now Playing", comment: "Lesson title"),
        summary: String(localized: "Control your music from the notch.", comment: "Lesson summary"),
        symbol: "music.note",
        steps: [
            LessonStep(
                id: "nowPlaying.open",
                title: String(localized: "Open the player", comment: "Lesson step title"),
                detail: String(localized: "A pretend song is playing: see its album art and sound bars beside the notch? Hover the notch to open it.", comment: "Lesson step detail"),
                symbol: "cursorarrow.rays",
                signal: .notchOpened
            ),
            LessonStep(
                id: "nowPlaying.pause",
                title: String(localized: "Pause the song", comment: "Lesson step title"),
                detail: String(localized: "Click the pause button in the middle.", comment: "Lesson step detail"),
                symbol: "pause.fill",
                signal: .musicPaused
            ),
            LessonStep(
                id: "nowPlaying.play",
                title: String(localized: "Play it again", comment: "Lesson step title"),
                detail: String(localized: "The same button carries on where you left off.", comment: "Lesson step detail"),
                symbol: "play.fill",
                signal: .musicPlayed
            ),
            LessonStep(
                id: "nowPlaying.skip",
                title: String(localized: "Skip to the next song", comment: "Lesson step title"),
                detail: String(localized: "Click the forward button. The back button goes to the start of the song, then the one before.", comment: "Lesson step detail"),
                symbol: "forward.fill",
                signal: .musicSkipped
            ),
            LessonStep(
                id: "nowPlaying.seek",
                title: String(localized: "Jump to another part", comment: "Lesson step title"),
                detail: String(localized: "Drag along the progress bar, or click anywhere on it.", comment: "Lesson step detail"),
                symbol: "timeline.selection",
                signal: .musicSeeked
            ),
            LessonStep(
                id: "nowPlaying.modes",
                title: String(localized: "Turn on shuffle or repeat", comment: "Lesson step title"),
                detail: String(localized: "The small buttons at either end. They light up while they're on.", comment: "Lesson step detail"),
                symbol: "shuffle",
                signal: .musicModeChanged
            ),
            LessonStep(
                id: "nowPlaying.artwork",
                title: String(localized: "Click the album art", comment: "Lesson step title"),
                detail: String(localized: "In your real notch, this brings the app that's playing to the front.", comment: "Lesson step detail"),
                symbol: "arrow.up.forward.app",
                signal: .musicArtworkClicked
            ),
            LessonStep(
                id: "nowPlaying.switch",
                title: String(localized: "Switch to the Shelf", comment: "Lesson step title"),
                detail: String(localized: "Pick it at the top left of the open notch, or swipe sideways there with two fingers.", comment: "Lesson step detail"),
                symbol: "rectangle.2.swap",
                signal: .moduleSwitched
            ),
        ]
    )

    /// Adding, opening, sharing and clearing items on the Shelf.
    public static let shelf = Lesson(
        id: .shelf,
        title: String(localized: "Shelf", comment: "Lesson title"),
        summary: String(localized: "Keep files, text and links in the notch.", comment: "Lesson summary"),
        symbol: "tray",
        steps: [
            LessonStep(
                id: "shelf.add",
                title: String(localized: "Drop a file on the notch", comment: "Lesson step title"),
                detail: String(localized: "Drag one of the practice files onto the notch.", comment: "Lesson step detail"),
                symbol: "tray.and.arrow.down",
                signal: .shelfItemAdded
            ),
            LessonStep(
                id: "shelf.open",
                title: String(localized: "Click it", comment: "Lesson step title"),
                detail: String(localized: "Click the item for a big preview.", comment: "Lesson step detail"),
                symbol: "hand.point.up.left",
                signal: .shelfItemOpened
            ),
            LessonStep(
                id: "shelf.back",
                title: String(localized: "Go back", comment: "Lesson step title"),
                detail: String(localized: "The arrow at the top left, or the Esc key, takes you back to your items.", comment: "Lesson step detail"),
                symbol: "chevron.left",
                signal: .shelfItemClosed
            ),
            LessonStep(
                id: "shelf.menu",
                title: String(localized: "Right-click an item", comment: "Lesson step title"),
                detail: String(localized: "Copy, AirDrop, Share and Remove live here.", comment: "Lesson step detail"),
                symbol: "contextualmenu.and.cursorarrow",
                signal: .shelfMenuOpened
            ),
            LessonStep(
                id: "shelf.dragOut",
                title: String(localized: "Drag an item out", comment: "Lesson step title"),
                detail: String(localized: "Drag it out of the notch into the dashed box, or anywhere you want a copy.", comment: "Lesson step detail"),
                symbol: "tray.and.arrow.up",
                signal: .shelfDraggedOut
            ),
            LessonStep(
                id: "shelf.select",
                title: String(localized: "Pick several", comment: "Lesson step title"),
                detail: String(localized: "Hold ⌘ and click two items.", comment: "Lesson step detail"),
                symbol: "command",
                signal: .shelfSeveralSelected
            ),
            LessonStep(
                id: "shelf.clear",
                title: String(localized: "Clear the Shelf", comment: "Lesson step title"),
                detail: String(localized: "Click Clear all, then click it again to confirm.", comment: "Lesson step detail"),
                symbol: "trash",
                signal: .shelfCleared
            ),
        ]
    )

    /// Answering a request, opening a thread and clearing the finished ones, on pretend agents.
    public static let agents = Lesson(
        id: .agents,
        title: String(localized: "Agents", comment: "Lesson title"),
        summary: String(localized: "See your AI agents and answer them.", comment: "Lesson summary"),
        symbol: "sparkles",
        steps: [
            LessonStep(
                id: "agents.allow",
                title: String(localized: "Allow a request", comment: "Lesson step title"),
                detail: String(localized: "A pretend agent wants to run a command. Open the notch and click Allow once. Deny says no.", comment: "Lesson step detail"),
                symbol: "checkmark.circle",
                signal: .agentAllowed
            ),
            LessonStep(
                id: "agents.open",
                title: String(localized: "Open a thread", comment: "Lesson step title"),
                detail: String(localized: "Click a thread to go to its app. In your real notch, that brings the app to the front.", comment: "Lesson step detail"),
                symbol: "arrow.up.forward.app",
                signal: .agentOpened
            ),
            LessonStep(
                id: "agents.clear",
                title: String(localized: "Clear finished", comment: "Lesson step title"),
                detail: String(localized: "Click Clear finished, beside the notch, to remove the threads that are done.", comment: "Lesson step detail"),
                symbol: "trash",
                signal: .agentsCleared
            ),
        ]
    )

    /// Choosing an account and a range on pretend accounts.
    public static let aiUsage = Lesson(
        id: .aiUsage,
        title: String(localized: "AI Usage", comment: "Lesson title"),
        summary: String(localized: "Check your plan limits and token use.", comment: "Lesson summary"),
        symbol: "gauge.with.dots.needle.50percent",
        steps: [
            LessonStep(
                id: "aiUsage.accounts",
                title: String(localized: "Open the account menu", comment: "Lesson step title"),
                detail: String(localized: "These are pretend accounts. Open the notch, then click the account at the top to see the list.", comment: "Lesson step detail"),
                symbol: "person.crop.circle",
                signal: .usageAccountsOpened
            ),
            LessonStep(
                id: "aiUsage.account",
                title: String(localized: "Pick an account", comment: "Lesson step title"),
                detail: String(localized: "Choose one to see its limits. All accounts adds token use and API value together; limits stay separate.", comment: "Lesson step detail"),
                symbol: "person.2",
                signal: .usageAccountChosen
            ),
            LessonStep(
                id: "aiUsage.range",
                title: String(localized: "Change the range", comment: "Lesson step title"),
                detail: String(localized: "Switch between Today, 7 days and 30 days to see more or less history.", comment: "Lesson step detail"),
                symbol: "calendar",
                signal: .usageRangeChosen
            ),
        ]
    )

    /// A quick timer to Done, pausing on the way, your own time on the wheels, and a stopwatch lap.
    public static let timer = Lesson(
        id: .timer,
        title: String(localized: "Timer", comment: "Lesson title"),
        summary: String(localized: "Time things from the notch: a timer and a stopwatch.", comment: "Lesson summary"),
        symbol: "timer",
        steps: [
            LessonStep(
                id: "timer.start",
                title: String(localized: "Start a quick timer", comment: "Lesson step title"),
                detail: String(localized: "Hover the notch to open it, then click the 10-second button at the top left.", comment: "Lesson step detail"),
                symbol: "play.fill",
                signal: .timerStarted
            ),
            LessonStep(
                id: "timer.pause",
                title: String(localized: "Pause it and carry on", comment: "Lesson step title"),
                detail: String(localized: "Click the pause button, then the play button. The time beside the notch stops while it's paused.", comment: "Lesson step detail"),
                symbol: "pause.fill",
                signal: .timerPausedAndResumed
            ),
            LessonStep(
                id: "timer.done",
                title: String(localized: "Stop it when it's done", comment: "Lesson step title"),
                detail: String(localized: "When the time is up you hear a sound and the notch opens on Done. Click Stop. Beside the notch it says Done until you do.", comment: "Lesson step detail"),
                symbol: "bell.fill",
                signal: .timerStopped
            ),
            LessonStep(
                id: "timer.custom",
                title: String(localized: "Set your own time", comment: "Lesson step title"),
                detail: String(localized: "Scroll or drag a wheel, or click it and type, then click Start.", comment: "Lesson step detail"),
                symbol: "dial.medium",
                signal: .timerCustomStarted
            ),
            LessonStep(
                id: "timer.lap",
                title: String(localized: "Time a lap", comment: "Lesson step title"),
                detail: String(localized: "Click Stopwatch at the top right, start it, then click the flag to mark a lap.", comment: "Lesson step detail"),
                symbol: "flag.fill",
                signal: .stopwatchLapped
            ),
        ]
    )
}
