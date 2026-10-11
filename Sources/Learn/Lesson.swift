import Foundation

/// The hands-on lessons on the app window's Learn page.
public enum LessonID: String, CaseIterable, Identifiable, Sendable {
    case basics, shelf

    public var id: Self { self }
}

/// Something the lesson noticed the user do. The app maps notch states / Shelf events to these.
public enum LessonSignal: Hashable, Sendable {
    case notchOpened, notchShrunk, notchClosed, shortcutSet,
         shelfItemAdded, shelfItemOpened, shelfItemClosed, shelfMenuOpened,
         shelfDraggedOut, shelfSeveralSelected, shelfCleared
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
    public static var all: [Lesson] { [basics, shelf] }

    public static func lesson(_ id: LessonID) -> Lesson {
        switch id {
        case .basics: basics
        case .shelf: shelf
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
                detail: String(localized: "Drag one of the practice files below onto the notch.", comment: "Lesson step detail"),
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
                detail: String(localized: "Drag it out of the notch into the box below, or anywhere you want a copy.", comment: "Lesson step detail"),
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
}
