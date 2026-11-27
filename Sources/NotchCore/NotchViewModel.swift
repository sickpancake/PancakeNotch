import AppKit
import Observation
import os
import SwiftUI

/// Owns the notch state and the hover/click rules that move between states (ADR-0011), and which
/// module the open notch shows (ADR-0010).
@MainActor
@Observable
public final class NotchViewModel {
    public private(set) var state: NotchState
    public var layout: NotchLayout

    /// Where the notch rests when not expanded: `.compact` while a module is active (music playing,
    /// the Shelf nearly full). Kept up to date by `activityChanged()`.
    public var restingState: NotchState = .closed {
        didSet { if state != .expanded { transition(to: restingTarget) } }
    }

    /// Where closing goes: the resting state, or Compact during a module's brief compact moment.
    var restingTarget: NotchState {
        isShowingBriefly || staysCompact || layout.isPeeking ? max(restingState, .compact) : restingState
    }

    /// Keeps the current state regardless of hover (used by `PANCAKENOTCH_DEBUG_STATE`).
    public var isPinned = false

    /// The modules in the notch (Now Playing, the Shelf), in any order: `arrangement` ranks them.
    /// Empty shows the placeholder and refuses drops.
    public var modules: [any NotchModule] = [] {
        didSet { modulesChanged(from: oldValue) }
    }

    /// The single module, for callers that host one (tests, a lesson's practice notch).
    public var module: (any NotchModule)? {
        get { selectedModule }
        set { modules = newValue.map { [$0] } ?? [] }
    }

    /// Ranking, favorites, ear sides and how to move between modules.
    public var arrangement: ModuleArrangement

    /// The module the open notch shows (or would show).
    public private(set) var selectedID: String?
    /// The open notch shows Home (the widget grid) instead of a module (ADR-0042).
    public private(set) var showsHome = false {
        didSet {
            if !showsHome { endHomeEditing(); resetHomeMotion() }
            guard showsHome, !oldValue else { return }
            homeVisit &+= 1
            onHomeEvent?(.opened)
        }
    }
    /// The open notch shows the Library (every module, searchable) instead of Home or a module (ADR-0045).
    public private(set) var showsLibrary = false {
        didSet { if !showsLibrary, oldValue { library.reset() } }
    }
    /// A module's page shows: neither Home nor the Library.
    public var showsModule: Bool { !showsHome && !showsLibrary }
    /// The Library's search, highlight and notes.
    public let library = NotchLibrary()
    /// Where Esc and the Library button go back to from the Library: where the person came from.
    @ObservationIgnored private var libraryReturn: NotchPlace = .home
    /// How the page that's arriving comes in (a slide from its side, grown from the bar or from a tile).
    public private(set) var entrance: NotchEntrance = .slide(forward: true)
    /// Home and the Library while the pager moves between them: the position in `hubPages` (0 = the first),
    /// following the fingers or settling. `nil` at rest, when only the current one is drawn.
    private(set) var hubPosition: CGFloat?
    /// Where the pager's last move started, so the page it brings in starts beside it.
    private(set) var hubOrigin: Int?
    @ObservationIgnored private var hubMotion = HomeScrollMotion()
    @ObservationIgnored private var hubGeneration = 0
    /// A menu from the bar or the Library is up: the notch stays open under it.
    public private(set) var isShowingMenu = false
    /// Counts the times Home has come up, so what's read once per opening (Statistics) knows a new one.
    public private(set) var homeVisit = 0
    /// Told when Home comes up and when a widget click opens something (Learn's Home lesson).
    @ObservationIgnored public var onHomeEvent: ((NotchHomeEvent) -> Void)?
    /// Home's layout, the "When the notch opens" choice and the one-time hint. Memory-only unless the
    /// app hands in the saved one.
    public var home: HomeSettings
    /// Which of Home's non-empty pages shows (0 = the first). Home always opens on the first. Always a
    /// real page: when the layout loses pages (a widget removed in the editor), it falls back to the last.
    public var homePage: Int { min(chosenHomePage, max(0, homePages.count - 1)) }
    private var chosenHomePage = 0
    /// The last page change went to a later page, for the slide.
    public private(set) var homePageForward = true
    @ObservationIgnored private var homeScroll = HomePageScrollTracker()
    @ObservationIgnored private var homeMotion = HomeScrollMotion()
    private(set) var homeScrollPosition: CGFloat?
    private(set) var homeMovingPages: [Int] = []
    private(set) var homeAnimationOrigin: Int?
    @ObservationIgnored private var homeMotionGeneration = 0

    var homeRenderedPages: [Int] {
        homeMovingPages.isEmpty ? [homePage] : homeMovingPages.filter { homePages.indices.contains($0) }
    }

    private func resetHomeMotion() {
        homeMotionGeneration &+= 1
        homeMotion = HomeScrollMotion()
        homeScrollPosition = nil
        homeMovingPages = []
        homeAnimationOrigin = nil
    }

    private func settleHome(to index: Int) {
        homeMotion.end()
        homeMotionGeneration &+= 1
        let generation = homeMotionGeneration
        withAnimation(.smooth(duration: 0.28, extraBounce: 0), completionCriteria: .removed) {
            chosenHomePage = index
            homeScrollPosition = CGFloat(index)
        } completion: { [weak self] in
            guard let self, self.homeMotionGeneration == generation else { return }
            self.resetHomeMotion()
        }
    }
    /// Draws the Battery and Statistics widgets (the app has their data). `nil` shows plain tiles.
    @ObservationIgnored public var homeExtras: HomeExtraWidgets?
    /// Set for off-screen snapshots: Home's widgets show this time and never tick.
    @ObservationIgnored public var snapshotClock: Date?
    /// The module whose strip shows under the compact notch right now (see `peek`).
    public private(set) var peekModuleID: String?
    @ObservationIgnored private var peekGeneration = 0

    /// Window availability for automatic strips; full screen can be temporarily revealed.
    public var automaticPeeksAvailable = true
    @ObservationIgnored var prepareAutomaticPeek: ((Bool) -> Bool)?

    /// Modules by ranking, #1 first.
    public var rankedModules: [any NotchModule] {
        arrangement.sorted(modules) { $0.moduleID }
    }

    public var selectedModule: (any NotchModule)? {
        modules.first { $0.moduleID == selectedID } ?? rankedModules.first
    }

    /// Gives the notch keyboard focus, e.g. after a click inside the Shelf. Set by the window controller.
    @ObservationIgnored public var requestKeyFocus: (() -> Void)?
    /// Hands keyboard focus back to the previous app. Called when the notch leaves the expanded state.
    @ObservationIgnored public var releaseKeyFocus: (() -> Void)?
    /// Whether the notch's window has the keyboard now. Set by the window controller (and the preview).
    @ObservationIgnored public var hasKeyFocus: (() -> Bool)?
    /// Posted when a drag this app took part in ended (a drop on a notch, a drag out of a module), by
    /// the real notch or a preview: the drag watcher doesn't see those releases.
    static let dragSettled = Notification.Name("NotchViewModel.dragSettled")

    /// Asks the window to fit a state. Called with the larger state before an animation starts,
    /// and with the final state once it settles.
    @ObservationIgnored public var fitWindow: ((NotchState) -> Void)?

    /// Called each time the notch opens.
    @ObservationIgnored public var onOpen: (() -> Void)?
    /// Called when a module's view appears in the open notch (statistics), with its ID.
    @ObservationIgnored public var onModuleShown: ((String) -> Void)?
    /// Home's gear: opens the app window. `nil` hides the gear (previews).
    @ObservationIgnored public var openSettings: (() -> Void)?
    /// Opens a page of the app window from Home (the editor, Modules, Statistics). `nil` in previews,
    /// where those links are hidden.
    @ObservationIgnored public var openAppPage: ((NotchAppPage) -> Void)?

    /// The latest state change came from a click on the notch (or Esc), not hover, a drag or a timer.
    /// Lessons count only those for "click to keep it small" and "click again to close".
    @ObservationIgnored public private(set) var lastChangeWasClick = false
    @ObservationIgnored private var isHandlingClick = false

    /// Hover delays and haptics from Settings.
    @ObservationIgnored public var behavior: NotchBehavior {
        didSet {
            // Cancel a queued hover-open, including if the user switches back before its delay ends.
            // An expanded notch may have a queued close: keep that close when the setting changes.
            if behavior.openOnClickOnly, !oldValue.openOnClickOnly, state != .expanded {
                hoverTask?.cancel()
            }
        }
    }
    /// Current pointer position in screen coordinates; injectable for tests.
    @ObservationIgnored private let pointerLocation: @MainActor () -> CGPoint
    /// Whether Mission Control is up; injectable for tests.
    @ObservationIgnored private let isMissionControlActive: @MainActor () -> Bool
    /// Set when a click shrinks the open panel: closing then stops at Compact instead of the resting state,
    /// until the open panel is clicked again (ADR-0011). Hovering still opens it.
    @ObservationIgnored private var staysCompact = false
    /// Right after a click shrinks the panel the pointer is still on the notch: hovering opens it again
    /// only once the pointer has left.
    @ObservationIgnored private var waitsForPointerToLeave = false
    @ObservationIgnored private var hoverTask: Task<Void, Never>?
    @ObservationIgnored private var wasOpenedByHover = false
    private static let logger = Logger(subsystem: "io.github.sickpancake.PancakeNotch", category: "notch")
    /// A module asked to close through Compact next time (the Shelf after a drop), for this long.
    @ObservationIgnored private var briefCompactOnClose: (duration: Duration, moduleID: String?)?
    @ObservationIgnored private var isShowingBriefly = false
    /// The module the brief compact moment is for: it gets an ear even if it isn't active.
    private var briefModuleID: String?
    @ObservationIgnored private var briefTask: Task<Void, Never>?
    @ObservationIgnored private var peekTask: Task<Void, Never>?
    /// Whether the last peek deadline found the pointer on the strip (internal for tests).
    @ObservationIgnored var isPeekHeld = false
    /// Whether the last observed pointer position was on the strip: moving on or off it is what
    /// `updatePeekHover` reacts to, since no new outline enter arrives inside the outline.
    @ObservationIgnored private var pointerWasOnPeekStrip = false
    /// Closes a notch a module's alert opened, if nobody touched it (`openForAttention`). Anything the user
    /// does, and every open, close and reset, cancels it, so it never closes a notch someone is using.
    @ObservationIgnored private var attentionTask: Task<Void, Never>?
    /// How long an alert's open notch (the Timer's Done card) waits untouched before it closes.
    @ObservationIgnored public var attentionCloseDelay: Duration = .seconds(10)
    /// Set by the window controller: opens for a module's alert only where the notch can show (not
    /// switched off or hidden), over a full-screen app only when asked. `nil` in previews.
    @ObservationIgnored public var presentAttention: ((_ moduleID: String, _ revealsInFullScreen: Bool) -> Void)?
    /// Set by the window controller: shows a module's strip for an alert only where the notch can show,
    /// over a full-screen app only when asked. `nil` in previews.
    @ObservationIgnored public var presentPeek: ((_ moduleID: String, _ duration: Duration, _ revealsInFullScreen: Bool) -> Void)?
    @ObservationIgnored private var transitionID = 0
    /// Settled in Closed: the ears (faded out under the notch) aren't built, about 1 MiB less while the
    /// notch rests (measured). Every way out of Closed wakes them before it animates.
    public private(set) var earsAsleep = false
    /// The window is on screen (set by the window controller): hidden, nothing in it needs to tick.
    public var isOnScreen = true { didSet { if !isOnScreen { endHomeEditing(); resetHomeMotion() } } }
    @ObservationIgnored private var swipe = NotchSwipeTracker()
    /// The Mac's or PancakeNotch's own Reduce Motion: Home's page scrolling follows it.
    @ObservationIgnored public let motion: MotionSettings
    @ObservationIgnored private var motionToken: NotificationToken?

    public init(
        layout: NotchLayout,
        state: NotchState = .closed,
        behavior: NotchBehavior = NotchBehavior(),
        arrangement: ModuleArrangement? = nil,
        home: HomeSettings? = nil,
        motion: MotionSettings? = nil,
        pointerLocation: @escaping @MainActor () -> CGPoint = { NSEvent.mouseLocation },
        isMissionControlActive: @escaping @MainActor () -> Bool = { MissionControlDetector.isActive }
    ) {
        self.layout = layout
        self.state = state
        self.earsAsleep = state == .closed
        self.behavior = behavior
        self.arrangement = arrangement ?? ModuleArrangement()
        self.home = home ?? HomeSettings()
        self.motion = motion ?? .shared
        self.pointerLocation = pointerLocation
        self.isMissionControlActive = isMissionControlActive
        watchNavigation()
        motionToken = NotificationToken(
            observing: MotionSettings.didChangeNotification, from: self.motion
        ) { [weak self] in self?.motionChanged() }
    }

    /// Reduce Motion went on or off: a Home page caught between two places (a scroll that was moving,
    /// settling or held by fingers) jumps to the page it was going to. Reduce Motion draws one page and
    /// never finishes that scroll, so without this the page would stay stuck halfway once it's off again,
    /// with its widgets not clickable.
    func motionChanged() {
        resetHomeMotion()
    }

    // MARK: Modules

    private func modulesChanged(from oldModules: [any NotchModule]) {
        let removed = oldModules.filter { old in !modules.contains { $0 === old } }
        let added = modules.filter { new in !oldModules.contains { $0 === new } }
        let selectedBefore = oldModules.first { $0.moduleID == selectedID } ?? arrangement.sorted(oldModules) { $0.moduleID }.first
        let wasMenu = !showsModule
        for module in removed {
            if state == .expanded, module === selectedBefore, showsModule { module.notchDidClose() }
            module.attach(to: nil)
        }
        if selectedID == nil || !modules.contains(where: { $0.moduleID == selectedID }) {
            selectedID = rankedModules.first?.moduleID
        }
        if !homeIsAvailable { showsHome = false }
        // The last module went away while it showed: Home takes its place.
        if modules.isEmpty, state == .expanded, homeIsAvailable, !showsHome, !showsLibrary {
            chosenHomePage = 0 // Home always comes up on its first page.
            showsHome = true
        }
        for module in added { module.attach(to: self) }
        // Attached while already open (e.g. pinned with PANCAKENOTCH_DEBUG_STATE=expanded), or Home
        // went away with the module before last.
        if state == .expanded, showsModule, let selected = selectedModule,
           wasMenu || selected !== selectedBefore || added.contains(where: { $0 === selected }) {
            selected.notchDidOpen()
        }
        if let peekModuleID, !modules.contains(where: { $0.moduleID == peekModuleID }) {
            endPeek(animated: true)
        }
        activityChanged()
    }

    /// A module's `isActive` changed: the notch rests in Compact while any module is active.
    public func activityChanged() {
        let resting: NotchState = modules.contains { $0.isActive } ? .compact : .closed
        if restingState != resting { restingState = resting }
    }

    /// Shows a module in the open notch (a tab, Home, the Library, a swipe). Only the user switches; opening
    /// picks the module itself (`open`).
    public func select(_ moduleID: String) {
        select(moduleID, entrance: nil)
    }

    /// `entrance` says how the page comes in; `nil` slides it in from its side of the bar.
    func select(_ moduleID: String, entrance: NotchEntrance?) {
        endHomeEditing()
        guard let target = modules.first(where: { $0.moduleID == moduleID }) else { return }
        cancelAttentionClose()
        let previous = selectedModule
        let wasPlace = !showsModule
        let arriving = entrance ?? .slide(forward: isForward(from: currentPlace, to: .module(moduleID)))
        withAnimation(Self.switchAnimation(reducesMotion: motion.reducesMotion)) {
            self.entrance = arriving
            showsHome = false
            showsLibrary = false
            selectedID = moduleID
        }
        resetHub()
        guard previous !== target || wasPlace else { return }
        if state == .expanded {
            if !wasPlace { previous?.notchDidClose() }
            target.notchDidOpen()
            moduleShown(moduleID)
        }
        if previous !== target { previous?.userSwitchedAway() }
    }

    /// A module's page came up in the open notch: statistics, and the Library's Recently used.
    private func moduleShown(_ moduleID: String) {
        onModuleShown?(moduleID)
        arrangement.noteOpened(moduleID)
    }

    /// Opens or closes Home in the open notch. With no module to go back to, Home stays. From the Library,
    /// Home slides in beside it.
    public func toggleHome() {
        // While editing, the Home button finishes editing and stays on Home.
        if isEditingHome {
            endHomeEditing()
            return
        }
        guard state == .expanded, homeIsAvailable, !isModuleHeld else { return }
        if showsHome {
            leaveHub()
        } else {
            showHub(.home, entrance: .reveal)
        }
    }

    /// Opens or closes the Library (its button): from a module it grows from the bar, from Home it slides in
    /// beside it. On the Library it goes back to where the person came from. The search takes typing right
    /// away (a click means the person is here to use it).
    public func toggleLibrary() {
        guard state == .expanded, !isModuleHeld else { return }
        if showsLibrary {
            goBackFromLibrary()
        } else {
            showHub(.library, entrance: .reveal, typing: .yes)
        }
    }

    // MARK: Places (ADR-0045)

    /// Where the open notch is now.
    public var currentPlace: NotchPlace {
        if showsLibrary { return .library }
        if showsHome { return .home }
        return selectedModule.map { .module($0.moduleID) } ?? .home
    }

    /// The Library, Home and every module, in the bar's order: the Library on its side of Home (or of the
    /// tabs, with tabs only), then the modules by ranking. Swipes and ←/→ walk it one step at a time.
    public var strip: [NotchPlace] {
        let modules = rankedModules.map { NotchPlace.module($0.moduleID) }
        guard homeIsAvailable else {
            return arrangement.librarySide == .left ? [.library] + modules : modules + [.library]
        }
        return (arrangement.librarySide == .left ? [.library, .home] : [.home, .library]) + modules
    }

    /// Home and the Library in the bar's order: the pages the pager slides between.
    var hubPages: [NotchPlace] { strip.filter(\.isHub) }

    private func isForward(from: NotchPlace, to: NotchPlace) -> Bool {
        let places = strip
        return (places.firstIndex(of: to) ?? 0) >= (places.firstIndex(of: from) ?? 0)
    }

    /// Moves one step along the bar's order: a two-finger swipe, or ←/→ (`byKey`) on Home or past the
    /// Library's first or last tile.
    public func showAdjacentPlace(forward: Bool, byKey: Bool = false) {
        guard !isModuleHeld, !isEditingHome, let next = adjacentPlace(forward: forward) else { return }
        go(to: next, entrance: .slide(forward: forward), typing: byKey ? .yes : .ifNotchHasKeyboard)
    }

    /// Shows `place`. `typing` says whether the Library's search takes the keyboard on arriving.
    func go(to place: NotchPlace, entrance: NotchEntrance, typing: LibraryTyping = .no) {
        switch place {
        case .module(let id): select(id, entrance: entrance)
        case .home, .library: showHub(place, entrance: entrance, typing: typing)
        }
    }

    /// Brings up Home or the Library. From a module the pair comes in with `entrance`; between the two the
    /// pager slides.
    private func showHub(_ place: NotchPlace, entrance: NotchEntrance, typing: LibraryTyping = .no) {
        let toLibrary = place == .library
        guard state == .expanded, toLibrary || homeIsAvailable, toLibrary ? !showsLibrary : !showsHome else { return }
        endHomeEditing()
        cancelAttentionClose()
        let wasModule = showsModule
        if toLibrary {
            libraryReturn = currentPlace
            startLibraryTyping(typing)
        }
        if wasModule {
            withAnimation(Self.switchAnimation(reducesMotion: motion.reducesMotion)) {
                self.entrance = entrance
                showsHome = !toLibrary
                showsLibrary = toLibrary
                if !toLibrary { chosenHomePage = 0 }
            }
            selectedModule?.notchDidClose()
        } else {
            slideHub(to: place)
        }
    }

    /// From Home back to the module it covers.
    private func leaveHub() {
        guard let module = selectedModule else { return }
        cancelAttentionClose()
        withAnimation(Self.switchAnimation(reducesMotion: motion.reducesMotion)) {
            entrance = .slide(forward: isForward(from: currentPlace, to: .module(module.moduleID)))
            showsHome = false
            showsLibrary = false
        }
        resetHub()
        if state == .expanded { module.notchDidOpen() }
    }

    /// Esc on an empty search, or the Library button again: back where the person came from (Home when
    /// that module is gone, or the current module when there's no Home).
    func goBackFromLibrary() {
        guard showsLibrary else { return }
        if let id = libraryReturn.moduleID, modules.contains(where: { $0.moduleID == id }) {
            select(id, entrance: .slide(forward: isForward(from: .library, to: libraryReturn)))
        } else if homeIsAvailable {
            slideHub(to: .home)
        } else if let module = selectedModule {
            select(module.moduleID)
        }
    }

    /// Home ↔ Library: the pager glides there, or cross-fades with Reduce Motion.
    private func slideHub(to place: NotchPlace) {
        let pages = hubPages
        guard let to = pages.firstIndex(of: place) else { return }
        let from = pages.firstIndex(of: currentPlace)
        let toLibrary = place == .library
        if motion.reducesMotion || snapshotClock != nil || from == nil {
            resetHub()
            withAnimation(Self.switchAnimation(reducesMotion: motion.reducesMotion)) {
                showsHome = !toLibrary
                showsLibrary = toLibrary
                if !toLibrary { chosenHomePage = 0 }
            }
            return
        }
        if hubPosition == nil { hubOrigin = from }
        settleHub(at: to) {
            self.showsHome = !toLibrary
            self.showsLibrary = toLibrary
            if !toLibrary { self.chosenHomePage = 0 }
        }
    }

    /// The pager's settling glide, the same as Home's pages; `change` flips the place with it. Once it has
    /// arrived only the current page stays drawn.
    private func settleHub(at index: Int, _ change: () -> Void = {}) {
        hubMotion.end()
        hubGeneration &+= 1
        let generation = hubGeneration
        withAnimation(.smooth(duration: 0.28, extraBounce: 0), completionCriteria: .removed) {
            change()
            hubPosition = CGFloat(index)
        } completion: { [weak self] in
            guard let self, self.hubGeneration == generation else { return }
            self.resetHub()
        }
    }

    private func resetHub() {
        hubGeneration &+= 1
        hubMotion = HomeScrollMotion()
        hubPosition = nil
        hubOrigin = nil
    }

    // MARK: Library (ADR-0045)

    /// Whether the Library's search takes the keyboard when the Library comes up.
    enum LibraryTyping {
        /// Not now: a click in the field starts typing.
        case no
        /// Only if the notch has the keyboard already (a swipe: hovering never takes typing from another app).
        case ifNotchHasKeyboard
        /// Yes: the person clicked or pressed a key here.
        case yes
    }

    private func startLibraryTyping(_ request: LibraryTyping) {
        switch request {
        case .no: return
        case .ifNotchHasKeyboard: guard hasKeyFocus?() == true else { return }
        case .yes: requestKeyFocus?()
        }
        library.isTyping = true
        library.focusRequest &+= 1
    }

    /// A click in the Library's search field: type there.
    public func libraryFieldClicked() {
        guard showsLibrary else { return }
        cancelAttentionClose()
        startLibraryTyping(.yes)
    }

    /// The words in the Library's search changed. The highlight goes to the best match, so Return opens it.
    public func setLibraryQuery(_ text: String) {
        guard showsLibrary, text != library.query else { return }
        let held = libraryHoldsOpen
        library.query = text
        let results = libraryResults
        library.highlight = SearchWords.words(in: text).isEmpty ? nil : (results.first(where: \.isOn) ?? results.first)?.id
        if held, !libraryHoldsOpen { holdReleased() }
    }

    /// Every module for the Library in ranking order: switched-on ones with their status, and the switched-off
    /// ones the app knows (practice notches list only their own modules).
    public var libraryEntries: [LibraryEntry] {
        let tabbed = arrangement.navigation == .tabsAndMenu ? Set(barTabIDs) : []
        let on: [LibraryEntry] = rankedModules.map { module in
            let id = module.moduleID
            let favorite = arrangement.navigation == .tabsAndMenu && arrangement.isFavorite(id)
            return LibraryEntry(id: id, title: module.title, symbol: module.symbol, status: module.menuStatus,
                                isOn: true, isFavorite: favorite, isFavoriteWithoutRoom: favorite && !tabbed.contains(id),
                                waitsForYou: module.waitsForYou)
        }
        guard !homeLeavesOutMissing else { return on }
        let off = ModuleArrangement.knownModules.filter { id in !modules.contains { $0.moduleID == id } }.map { id in
            let info = ModuleCatalog.info(id)
            return LibraryEntry(id: id, title: info.title, symbol: info.symbol,
                                status: String(localized: "Off", comment: "Library: a switched-off module's tile"),
                                isOn: false, isFavorite: false, isFavoriteWithoutRoom: false, waitsForYou: false)
        }
        return arrangement.sorted(on + off) { $0.id }
    }

    /// The Library's tiles for the words typed: matching names first, then other words, in ranking order.
    public var libraryResults: [LibraryEntry] { NotchLibrary.results(libraryEntries, for: library.query) }

    /// Up to three switched-on modules opened lately, newest first, for "Recently used". None while a search
    /// is typed: the tiles show what it found.
    public var libraryRecents: [LibraryEntry] {
        guard SearchWords.words(in: library.query).isEmpty else { return [] }
        let entries = libraryEntries
        return Array(arrangement.recent.compactMap { id in entries.first { $0.id == id && $0.isOn } }.prefix(3))
    }

    /// Where each tile sits in the open panel (unit point), so a module opened from it grows out of it.
    /// Kept up to date by the Library's view.
    @ObservationIgnored var libraryTileAnchors: [String: UnitPoint] = [:]
    /// How many tiles fit across, for ↑ and ↓.
    var libraryColumns: Int { LibraryMetrics.columns(in: layout) }

    /// Opens a module from the Library (a tile, a recent row, Return): it grows out of its tile. A switched-off
    /// module opens its card on the app window's Modules page, where it's turned on.
    public func openFromLibrary(_ moduleID: String) {
        guard showsLibrary else { return }
        guard modules.contains(where: { $0.moduleID == moduleID }) else {
            openAppPage?(.module(moduleID))
            return
        }
        select(moduleID, entrance: libraryTileAnchors[moduleID].map { .grow(from: $0) })
        onHomeEvent?(.openedFromLibrary(moduleID))
    }

    /// Esc clears the search, then goes back; Return opens the highlighted tile; the arrows walk the tiles,
    /// and ←/→ past the first or last one go on along the bar.
    private func handleLibraryKey(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 53:
            if !library.query.isEmpty { setLibraryQuery("") } else { goBackFromLibrary() }
            return true
        case 36, 76:
            guard let id = library.highlight else { return false }
            openFromLibrary(id)
            return true
        case 123, 124:
            // An arrow key means the person is at the keyboard: typing goes to the search from now on.
            if !library.isTyping { startLibraryTyping(.yes) }
            moveLibraryHighlight(by: event.keyCode == 124 ? 1 : -1, leavesAtEnds: true)
            return true
        case 125, 126:
            if !library.isTyping { startLibraryTyping(.yes) }
            moveLibraryHighlight(by: event.keyCode == 125 ? libraryColumns : -libraryColumns, leavesAtEnds: false)
            return true
        default:
            return false
        }
    }

    private func moveLibraryHighlight(by step: Int, leavesAtEnds: Bool) {
        let ids = libraryResults.map(\.id)
        guard let current = library.highlight, let index = ids.firstIndex(of: current) else {
            if ids.isEmpty, leavesAtEnds { showAdjacentPlace(forward: step > 0, byKey: true); return }
            library.highlight = step > 0 ? ids.first : ids.last
            return
        }
        let next = index + step
        if ids.indices.contains(next) {
            library.highlight = ids[next]
        } else if leavesAtEnds {
            showAdjacentPlace(forward: step > 0, byKey: true)
        }
    }

    // MARK: Favorites (ADR-0045)

    /// How many favorites the bar has room for beside Home and the Library, on this screen.
    public var favoriteCapacity: Int { NotchModuleBar.fit(for: self).capacity }

    /// Switched-on favorites: each takes a tab.
    private var favoriteCount: Int { rankedModules.filter { arrangement.isFavorite($0.moduleID) }.count }

    /// Whether another favorite fits in the bar. Favorites only make tabs with "Home and tabs".
    public var canAddFavorite: Bool {
        arrangement.navigation == .tabsAndMenu && favoriteCount < favoriteCapacity
    }

    /// Adds or removes a favorite. Adding is refused while the bar is full, and the Library says why.
    /// Returns whether it changed.
    @discardableResult
    public func toggleFavorite(_ moduleID: String) -> Bool {
        let removing = arrangement.isFavorite(moduleID)
        guard removing || canAddFavorite else {
            showLibraryNote(.barFull)
            return false
        }
        withAnimation(motion.reducesMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.3, dampingFraction: 0.85)) {
            arrangement.toggleFavorite(moduleID)
        }
        return true
    }

    /// Shows a short note under the Library's tiles for a few seconds (longer for VoiceOver, which also
    /// reads it out).
    private func showLibraryNote(_ note: LibraryNote) {
        library.noteTask?.cancel()
        withAnimation(.easeInOut(duration: 0.2)) { library.note = note }
        AccessibilityNotification.Announcement(LibraryText.note(note)).post()
        let seconds = NSWorkspace.shared.isVoiceOverEnabled ? 8 : 3
        library.noteTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, let self else { return }
            withAnimation(.easeInOut(duration: 0.2)) { self.library.note = nil }
        }
    }

    /// A right-click menu from the bar or the Library opened or closed: the notch stays open under it.
    func menuShowingChanged(_ showing: Bool) {
        isShowingMenu = showing
        if !showing { holdReleased() }
    }

    /// Opens the app window on a module's card (its settings open when it's switched on).
    public func openSettings(for moduleID: String) {
        openAppPage?(.module(moduleID))
    }

    /// Home is there unless the person chose tabs only (Notch settings).
    public var homeIsAvailable: Bool { arrangement.navigation != .tabs }

    /// Follows the navigation setting, so choosing tabs only while Home shows goes back to a module.
    /// Observation only: nothing runs until the setting changes.
    private func watchNavigation() {
        withObservationTracking { _ = arrangement.navigation } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.navigationChanged()
                self?.watchNavigation()
            }
        }
    }

    private func navigationChanged() {
        guard showsHome, !homeIsAvailable else { return }
        withAnimation(Self.switchAnimation(reducesMotion: motion.reducesMotion)) { showsHome = false }
        if state == .expanded { selectedModule?.notchDidOpen() }
    }

    /// Whether the widgets on this layout page may tick: Home shows in the open notch, on screen, and this
    /// is the page that shows (one sliding away stops at once). Never in a snapshot.
    public func homeIsLive(onPage page: Int) -> Bool {
        guard !isEditingHome, state == .expanded, showsHome, isOnScreen, snapshotClock == nil else { return false }
        return homePages.indices.contains(homePage) && homePages[homePage] == page
    }

    /// Home's pages that hold something, in order: the ones the open notch scrolls through.
    public var homePages: [Int] {
        let pages = homeLayout.nonEmptyPages
        guard isEditingHome else { return pages }
        if let free = (0..<HomeLayout.pageCount).first(where: { !pages.contains($0) }) {
            return (pages + [free]).sorted()
        }
        return pages
    }

    public private(set) var isEditingHome = false
    public var showsHomePicker = false
    @ObservationIgnored private var homeOutsideLocal: Any?
    @ObservationIgnored private var homeOutsideGlobal: Any?

    public func beginHomeEditing() {
        guard state == .expanded, showsHome, isOnScreen, !isEditingHome else { return }
        resetHomeMotion()
        let shownPage = homePages.indices.contains(homePage) ? homePages[homePage] : 0
        cancelAttentionClose()
        hoverTask?.cancel()
        isEditingHome = true
        chosenHomePage = homePages.firstIndex(of: shownPage) ?? 0
        home.hasSeenIntro = true
        requestKeyFocus?()
        // Snapshot models never install native input observers.
        guard snapshotClock == nil else { return }
        homeOutsideLocal = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            self?.homeOutsideClick()
            return event
        }
        homeOutsideGlobal = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.homeOutsideClick()
        }
    }

    private func homeOutsideClick() {
        if !layout.outline(for: state, contains: pointerLocation()) { endHomeEditing() }
    }

    public func endHomeEditing(keepsNotchFocused: Bool = false) {
        guard isEditingHome else { return }
        let shownPage = homePages.indices.contains(homePage) ? homePages[homePage] : 0
        isEditingHome = false
        chosenHomePage = homePages.firstIndex(of: shownPage) ?? 0
        showsHomePicker = false
        if let monitor = homeOutsideLocal { NSEvent.removeMonitor(monitor) }
        if let monitor = homeOutsideGlobal { NSEvent.removeMonitor(monitor) }
        homeOutsideLocal = nil
        homeOutsideGlobal = nil
        guard !keepsNotchFocused else { return }
        releaseKeyFocus?()
        holdReleased()
    }

    /// The notch's Undo and Redo for Home edits: the same history the window editor walks, so an edit
    /// made on either surface steps back (or forward again) from here too.
    public func undoHomeEdit() {
        guard let previous = home.history.undo(current: home.layout) else { return }
        withAnimation(Self.switchAnimation(reducesMotion: motion.reducesMotion)) { home.layout = previous }
    }

    public func redoHomeEdit() {
        guard let next = home.history.redo(current: home.layout) else { return }
        withAnimation(Self.switchAnimation(reducesMotion: motion.reducesMotion)) { home.layout = next }
    }

    /// Practice notches (Settings, Learn) leave out the widgets of modules they don't have, instead of
    /// showing them as turned off.
    public var homeLeavesOutMissing = false

    /// The layout Home draws: the saved one, less missing modules' widgets in a practice notch.
    public var homeLayout: HomeLayout {
        guard homeLeavesOutMissing else { return home.layout }
        let present = Set(modules.map(\.moduleID))
        var layout = home.layout
        layout.placements.removeAll { placement in placement.kind.moduleID.map { !present.contains($0) } ?? false }
        return layout
    }

    /// Shows another of Home's pages (scrolling, the page dots, the arrow keys, VoiceOver).
    public func showHomePage(_ index: Int) {
        guard showsHome, homePages.indices.contains(index), index != homePage else { return }
        cancelAttentionClose()
        homePageForward = index > homePage
        if isEditingHome || motion.reducesMotion || snapshotClock != nil {
            resetHomeMotion()
            withAnimation(Self.switchAnimation(reducesMotion: motion.reducesMotion)) { chosenHomePage = index }
        } else {
            if homeScrollPosition == nil { homeScrollPosition = CGFloat(homePage) }
            homeAnimationOrigin = homePage
            homeMovingPages = [homePage, index]
            settleHome(to: index)
        }
    }

    /// A click on a widget, away from its buttons: opens what it belongs to. Stopwatch opens the Timer,
    /// Statistics the app window's Statistics page; Clock and Battery do nothing.
    public func openFromHome(_ kind: HomeWidgetKind) {
        guard !isEditingHome else { return }
        if kind == .statistics {
            openAppPage?(.statistics)
            return
        }
        guard let moduleID = kind.moduleID, let module = modules.first(where: { $0.moduleID == moduleID }) else { return }
        select(moduleID)
        module.openedFromHome(kind)
        onHomeEvent?(.widgetOpened(kind))
    }

    /// The modules that may have a tab, by ranking: the favorites, or every module with tabs only. The bar
    /// shows as many as fit (`barTabIDs`); the rest live in the Library (ADR-0045).
    public var tabModules: [any NotchModule] {
        let ranked = rankedModules
        guard arrangement.navigation == .tabsAndMenu else { return ranked }
        return ranked.filter { arrangement.isFavorite($0.moduleID) }
    }

    /// The modules that have a tab in the bar right now, in order.
    public var barTabIDs: [String] { NotchModuleBar.fit(for: self).tabModuleIDs }

    /// Switched-on favorites the bar has no room for, by ranking: they live in the Library (ADR-0045).
    public var favoritesWithoutTab: [String] {
        guard arrangement.navigation == .tabsAndMenu else { return [] }
        let tabbed = Set(barTabIDs)
        return tabModules.map(\.moduleID).filter { !tabbed.contains($0) }
    }

    /// The module showing that has no tab (not a favorite, or no room): its icon sits just right of the
    /// camera, lit like a selected tab. Not with the name button, which names it already.
    public var visitingModule: (any NotchModule)? {
        guard showsModuleBar, showsModule, arrangement.navigation != .menu, let module = selectedModule,
              !barTabIDs.contains(module.moduleID) else { return nil }
        return module
    }

    /// Whether the bar shows: always, unless a module needs the notch to itself (a prompt, a drag out).
    public var showsModuleBar: Bool {
        isEditingHome || !isModuleHeld
    }

    /// A scroll in the open notch: a sideways two-finger swipe moves along the bar (Library, Home, modules),
    /// unless it scrolls something inside the module. `point` is in notch-body coordinates. Returns whether
    /// it was used.
    @discardableResult
    public func handleScroll(_ event: NSEvent, at point: CGPoint) -> Bool {
        // Follow the fingers whatever the "natural scrolling" setting: positive = fingers moving right.
        let fingersX = event.isDirectionInvertedFromDevice ? event.scrollingDeltaX : -event.scrollingDeltaX
        guard state == .expanded else {
            // A gesture that started before the notch opened scrolls something else, not the modules.
            swipe.ignoreCurrentGesture()
            return false
        }
        if !showsModule { return scrollHub(event, fingersX: fingersX) }
        if event.phase == .began, selectedModule?.scrollsHorizontally(at: point) == true {
            swipe.ignoreCurrentGesture()
            return false
        }
        guard let forward = swipe.handle(
            phase: NotchSwipeTracker.Phase(event),
            deltaX: fingersX,
            deltaY: event.scrollingDeltaY,
            isPrecise: event.hasPreciseScrollingDeltas
        ) else { return false }
        showAdjacentPlace(forward: forward)
        return true
    }

    /// Scrolling on Home or the Library: up and down turn Home's pages (the Library's tiles scroll by
    /// themselves); sideways moves along the bar, the pager following the fingers between Home and the
    /// Library. While editing, with Reduce Motion or a mouse wheel it moves one step per gesture instead.
    private func scrollHub(_ event: NSEvent, fingersX: CGFloat) -> Bool {
        let phase = NotchSwipeTracker.Phase(event)
        let precise = event.hasPreciseScrollingDeltas
        guard isEditingHome || motion.reducesMotion || !precise else {
            return handleHubPreciseScroll(phase: phase, deltaY: event.scrollingDeltaY, fingersX: fingersX,
                                          time: event.timestamp, momentum: !event.momentumPhase.isEmpty)
        }
        if showsHome, let step = homeScroll.handle(phase: phase, deltaY: event.scrollingDeltaY,
            deltaX: event.scrollingDeltaX, isPrecise: precise, time: event.timestamp) {
            showHomePage(homePage + step)
            return true
        }
        guard !isEditingHome, let forward = swipe.handle(phase: phase, deltaX: fingersX,
            deltaY: event.scrollingDeltaY, isPrecise: precise) else { return false }
        showAdjacentPlace(forward: forward)
        return true
    }

    /// A trackpad gesture on Home or the Library (`fingersX` positive while the fingers move right).
    @discardableResult
    func handleHubPreciseScroll(phase: NotchSwipeTracker.Phase, deltaY: CGFloat, fingersX: CGFloat,
                                time: TimeInterval, momentum: Bool = false) -> Bool {
        // On the Library an up-or-down gesture belongs to its tiles' scroll view, end and glide included; only
        // a sideways one is the pager's. Home takes every gesture (its pages scroll up and down).
        let onHome = showsHome
        let sideways = hubMotion.horizontal
        if momentum {
            if hubMotion.active { finishHubScroll(time: time) }
            if onHome { handleHomePreciseScroll(phase: phase, deltaY: deltaY, deltaX: -fingersX, time: time, momentum: true) }
            return onHome || sideways
        }
        if phase == .ended {
            finishHubScroll(time: time)
            _ = swipe.handle(phase: .ended, deltaX: 0, deltaY: 0, isPrecise: true)
            if onHome { handleHomePreciseScroll(phase: .ended, deltaY: 0, deltaX: 0, time: time) }
            return onHome || sideways
        }
        if phase == .began {
            cancelAttentionClose()
            resetHub()
            hubMotion.begin(page: hubPages.firstIndex(of: currentPlace) ?? 0, time: time)
        }
        // Home's pages take a gesture that goes up or down.
        if showsHome, handleHomePreciseScroll(phase: phase, deltaY: deltaY, deltaX: -fingersX, time: time) {
            return true
        }
        guard phase == .began || phase == .changed, hubMotion.active else { return false }
        hubMotion.move(y: deltaY, x: -fingersX, time: time)
        guard hubMotion.horizontal, !isEditingHome else { return false }
        // Towards a module (Home → the first module): one flick switches, as between modules.
        if let forward = swipe.handle(phase: phase, deltaX: fingersX, deltaY: deltaY, isPrecise: true),
           let next = adjacentPlace(forward: forward), !next.isHub {
            go(to: next, entrance: .slide(forward: forward))
            return true
        }
        // Between Home and the Library the pages follow the fingers (resisting at the ends).
        let width = layout.bodySize(for: .expanded).width
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            if hubOrigin == nil { hubOrigin = hubMotion.origin }
            hubPosition = hubMotion.sidewaysPosition(width: width, count: hubPages.count)
        }
        return true
    }

    /// The fingers lifted during a sideways gesture between Home and the Library: settle on the nearest
    /// page, or the next one for a flick. Arriving on the Library this way doesn't take the keyboard.
    private func finishHubScroll(time: TimeInterval) {
        guard hubMotion.active else { return }
        let pages = hubPages
        guard hubMotion.horizontal, hubPosition != nil else { hubMotion.end(); return }
        let target = hubMotion.sidewaysTarget(width: layout.bodySize(for: .expanded).width, count: pages.count, time: time)
        guard pages.indices.contains(target), pages[target] != currentPlace else {
            settleHub(at: hubMotion.origin)
            return
        }
        let place = pages[target]
        let toLibrary = place == .library
        if toLibrary {
            libraryReturn = currentPlace
            startLibraryTyping(.ifNotchHasKeyboard)
        }
        endHomeEditing()
        settleHub(at: target) {
            self.showsHome = !toLibrary
            self.showsLibrary = toLibrary
            if !toLibrary { self.chosenHomePage = 0 }
        }
    }

    /// The place one step along the bar, if there is one.
    private func adjacentPlace(forward: Bool) -> NotchPlace? {
        let places = strip
        guard let index = places.firstIndex(of: currentPlace) else { return nil }
        let next = index + (forward ? 1 : -1)
        return places.indices.contains(next) ? places[next] : nil
    }

    /// Picks what to open on: the module asked for (its ear or strip was pointed at, a drag), else the
    /// first by ranking that waits for you (an agent's question, a finished timer), else Home when the
    /// person chose it in Settings, else the first module that wants it (music playing), otherwise the one
    /// used last, or Home if that module is idle and Home is available. Home also opens when there are
    /// no modules (ADR-0010, ADR-0011 amendment 2026-11-03, ADR-0042).
    private func chooseModuleForOpening(_ moduleID: String?, preferringHome: Bool = false) {
        resetHomeMotion()
        showsHome = false
        showsLibrary = false
        entrance = .slide(forward: true)
        chosenHomePage = 0
        let ranked = rankedModules
        if let moduleID, modules.contains(where: { $0.moduleID == moduleID }) {
            selectedID = moduleID
        } else if preferringHome, homeIsAvailable {
            // The "+n" chip opens Home, which shows every displaced module's widget.
            showsHome = true
        } else if preferringHome,
                  let displaced = earAllocation().displacedModuleIDs.first(where: { id in
                      modules.contains { $0.moduleID == id } }) {
            // With tabs-only navigation the chip opens on the best-ranked displaced module instead.
            selectedID = displaced
        } else if let waiting = ranked.first(where: { $0.waitsForYou }) {
            selectedID = waiting.moduleID
        } else if homeIsAvailable, home.opening == .home || modules.isEmpty {
            showsHome = true
        } else if let focused = ranked.first(where: { $0.wantsFocus }) {
            selectedID = focused.moduleID
        } else if homeIsAvailable, selectedModule?.isIdleForOpening == true {
            showsHome = true
        }
    }

    @discardableResult
    func handleHomePreciseScroll(phase: NotchSwipeTracker.Phase, deltaY: CGFloat, deltaX: CGFloat,
                                 time: TimeInterval, momentum: Bool = false) -> Bool {
        // Native momentum belongs to the completed gesture, never to the spring.
        if momentum {
            if homeMotion.active { finishHomeScroll(time: time) }
            return true
        }
        if phase == .began {
            cancelAttentionClose()
            resetHomeMotion()
            homeMotion.begin(page: homePage, time: time)
        }
        if phase == .ended {
            finishHomeScroll(time: time)
            return true
        }
        guard phase == .began || phase == .changed, homeMotion.active else { return false }
        homeMotion.move(y: deltaY, x: deltaX, time: time)
        guard homeMotion.vertical else { return false }
        let height = HomeWidgetMetrics.pageStride(in: HomeWidgetMetrics.gridArea(in: layout))
        let position = homeMotion.position(height: height, count: homePages.count)
        let direction = position >= CGFloat(homeMotion.origin) ? 1 : -1
        let lastPage = max(0, homePages.count - 1)
        let neighbour = min(lastPage, max(0, homeMotion.origin + direction))
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            homeScrollPosition = position
            homeMovingPages = Array(Set([homeMotion.origin, neighbour])).sorted()
            chosenHomePage = homeMotion.target(height: height, count: homePages.count, time: time)
        }
        return true
    }

    private func finishHomeScroll(time: TimeInterval) {
        guard homeMotion.active else { return }
        let target = homeMotion.target(height: HomeWidgetMetrics.pageStride(in: HomeWidgetMetrics.gridArea(in: layout)),
                                       count: homePages.count, time: time)
        if homeMovingPages.isEmpty { resetHomeMotion(); return }
        let revealed = homeMovingPages.first(where: { $0 != homeMotion.origin }) ?? homeMotion.origin
        let neighbour = target == homeMotion.origin ? revealed : target
        homeMovingPages = Array(Set([homeMotion.origin, neighbour])).sorted()
        settleHome(to: target)
    }

    /// The module that takes this drag: the current one if it does, else the first by ranking.
    func module(accepting pasteboard: NSPasteboard) -> (any NotchModule)? {
        if let selected = selectedModule, selected.canAcceptDrag(pasteboard) { return selected }
        return rankedModules.first { $0.canAcceptDrag(pasteboard) }
    }

    // MARK: Ears

    /// One compact ear's content, with an ID so a change of owner can animate.
    public struct EarSlot {
        public let id: String
        public let moduleID: String
        public let view: AnyView
        /// Added to the "+n" overflow count when this ear shows it (`CompactEars.mergedCount`).
        public var mergedCount: Int = 0
    }

    /// The "+n" count inside an ear: how many active modules didn't fit the two spots, and the ear
    /// that shows it. Pointing at it opens Home, where the displaced modules' widgets show.
    public struct EarOverflow: Equatable, Sendable {
        public enum Side: Sendable { case left, right }
        public let side: Side
        public let count: Int
    }

    /// The overflow count for the current allocation, or `nil` when every candidate fits or a
    /// peeking module's strip is showing (the ears keep their full width then).
    var earOverflow: EarOverflow? {
        if layout.isPeeking { return nil }
        let allocation = earAllocation()
        guard let side = allocation.overflowSide else { return nil }
        return EarOverflow(side: side == .left ? .left : .right, count: allocation.displacedModuleIDs.count)
    }

    /// The pointer is on the "+n" count: the strip at the outer edge of the ear that shows it
    /// (`NotchLayout.earCountWidth` wide, the ear's full height). The rest of the ear keeps its module's
    /// click, and while a module is peeking the count is hidden.
    func pointerOverEarOverflow() -> Bool {
        guard state == .compact, !layout.isPeeking, let overflow = earOverflow else { return false }
        let point = pointerLocation()
        let notch = layout.geometry.notchRect
        let earBottom = notch.maxY - layout.geometry.compactHeight
        guard point.y >= earBottom, point.y <= notch.maxY else { return false }
        let earWidth = layout.compactEarWidth
        let count = NotchLayout.earCountWidth
        switch overflow.side {
        case .left: return point.x >= notch.minX - earWidth && point.x < notch.minX - earWidth + count
        case .right: return point.x >= notch.maxX + earWidth - count && point.x < notch.maxX + earWidth
        }
    }

    /// The same ownership decision drives drawing and opening from an ear. Availability is read
    /// without building views, including when the selected module is the shrink-after-click fallback.
    private func earAllocation() -> EarAllocator.Allocation {
        var shown = rankedModules.filter { $0.isActive || $0.moduleID == briefModuleID }
        // Keep the strip's owner until its exit animation ends, so no fallback ear flashes in.
        if shown.isEmpty, peekModuleID == nil || staysCompact, let selected = selectedModule { shown = [selected] }
        let candidates = shown.compactMap { module -> EarAllocator.Candidate? in
            guard let configuration = module.earConfiguration else { return nil }
            return EarAllocator.Candidate(moduleID: module.moduleID, configuration: configuration,
                waitsForYou: module.waitsForYou,
                borrowsSecond: module.moduleID == briefModuleID && !module.isActive)
        }
        return EarAllocator.allocate(candidates, swapsSides: arrangement.swapsEarSides)
    }

    /// Build content only for the allocated owners. A lone module's main and extra views share
    /// one construction, and retain their existing animation IDs.
    public func ears(layout: NotchLayout) -> (left: EarSlot?, right: EarSlot?) {
        let allocation = earAllocation()
        // The ear showing the "+n" count lays its module out in the room the count leaves.
        let countSide = layout.isPeeking ? nil : allocation.overflowSide
        let countOwner = countSide == .left ? allocation.left?.moduleID : countSide == .right ? allocation.right?.moduleID : nil
        var content: [String: CompactEars] = [:]
        for owner in [allocation.left?.moduleID, allocation.right?.moduleID].compactMap({ $0 }) {
            if content[owner] == nil {
                var ownerLayout = layout
                if owner == countOwner { ownerLayout.compactEarReserve = NotchLayout.earCountWidth }
                content[owner] = modules.first { $0.moduleID == owner }?.compactEars(layout: ownerLayout)
            }
        }
        func render(_ slot: EarAllocator.Slot?) -> EarSlot? {
            guard let slot, let ears = content[slot.moduleID] else { return nil }
            let view: AnyView?
            let mergedCount: Int
            switch slot.content {
            case .main: view = ears.main; mergedCount = ears.mergedCount
            case .extra: view = ears.extra; mergedCount = 0
            }
            return view.map { EarSlot(id: slot.id, moduleID: slot.moduleID, view: $0, mergedCount: mergedCount) }
        }
        return (render(allocation.left), render(allocation.right))
    }

    /// The module the pointer is on in the compact notch: the strip's module anywhere on the strip, else the
    /// module whose ear it's over. Clicking opens that module; hovering an ear can open it too.
    /// `nil` in the middle, over the hardware notch, where opening picks the module itself.
    func moduleUnderPointer() -> String? {
        guard state == .compact else { return nil }
        let point = pointerLocation()
        if peekStripContains(point) {
            guard let peekModuleID, modules.contains(where: { $0.moduleID == peekModuleID }) else { return nil }
            return peekModuleID
        }
        let notch = layout.geometry.notchRect
        guard layout.outline(for: .compact, contains: point) else { return nil }
        guard point.x < notch.minX || point.x >= notch.maxX else { return nil }
        let allocation = earAllocation()
        return (point.x < notch.minX ? allocation.left : allocation.right)?.moduleID
    }

    private func peekStripContains(_ point: CGPoint) -> Bool {
        let geometry = layout.geometry
        return state == .compact && layout.isPeeking
            && point.y < geometry.notchRect.maxY - geometry.compactHeight
            && layout.outline(for: .compact, contains: point)
    }

    /// The peek strip's view while a module is peeking.
    var peekView: AnyView? {
        guard layout.isPeeking, let peekModuleID else { return nil }
        return modules.first { $0.moduleID == peekModuleID }?.peekView(layout: layout)
    }

    // MARK: Hover, clicks and drags

    /// Called when the pointer enters or leaves the notch outline.
    public func hoverChanged(_ isHovering: Bool) {
        updatePeekHover()
        // When the window shrinks (e.g. after a click shrinks the panel), AppKit reports the pointer
        // leaving and coming straight back. A "left" while it's still on the notch isn't real: ignoring it
        // keeps the click's "don't reopen" in place.
        if !isHovering, layout.outline(for: state, contains: pointerLocation()) { return }
        hoverTask?.cancel()
        cancelAttentionClose()
        guard !isPinned else { return }
        if isHovering {
            guard !behavior.openOnClickOnly, state != .expanded, !waitsForPointerToLeave,
                  !peekStripContains(pointerLocation()) else { return }
            scheduleHoverOpen()
        } else {
            waitsForPointerToLeave = false
            scheduleCloseIfIdle()
        }
    }

    /// A drag from another app entered the notch: open right away, no hover delay (ADR-0011), on the
    /// module that takes it.
    public func dragEntered(focusing moduleID: String? = nil) {
        guard !isPinned else { return }
        hoverTask?.cancel()
        if state != .expanded {
            open(focusing: moduleID)
        } else if let moduleID, moduleID != selectedModule?.moduleID || !showsModule, !isModuleHeld {
            select(moduleID)
        }
    }

    /// A file drag elsewhere on screen came near the notch: open before it reaches the top edge, where
    /// macOS would start Mission Control instead (ADR-0011).
    public func dragApproached(_ pasteboard: NSPasteboard? = nil) {
        dragEntered(focusing: pasteboard.flatMap { module(accepting: $0)?.moduleID })
    }

    /// A drag that opened the notch early moved away or was released, maybe somewhere else (or Mission
    /// Control took it). AppKit sends no hover events during a drag, so check where the pointer is now.
    /// Over the notch, the window's own drag events handle the drop (and may not have arrived yet).
    public func approachingDragEnded() {
        guard !layout.outline(for: state, contains: pointerLocation()) else { return }
        modules.forEach { $0.dragEnded() }
        scheduleCloseIfIdle()
    }

    /// Grows the open panel to the taller version a module asked for (the Shelf's editor and preview),
    /// or back. The panel goes back to normal on its own when the notch closes.
    public func setTall(_ tall: Bool) {
        setPanelHeight(tall ? .tall : .regular)
    }

    /// Grows or shrinks the open panel to `height` (the Shelf's Convert row is `.medium`). The panel
    /// goes back to normal on its own when the notch closes.
    public func setPanelHeight(_ height: PanelHeight) {
        guard layout.panelHeight != height, height == .regular || state == .expanded else { return }
        let grows = height > layout.panelHeight
        transitionID += 1
        let id = transitionID
        var target = layout
        target.panelHeight = height
        withAnimation(Self.tallAnimation(reducesMotion: motion.reducesMotion)) {
            layout = target
        } completion: { [weak self] in
            guard let self, self.transitionID == id else { return }
            self.fitWindow?(self.state)
        }
        // Grow the window now, shrink it once the animation settles.
        if grows { fitWindow?(state) }
    }

    /// The drag left the notch without dropping: close like a hover exit.
    public func dragExited() {
        modules.forEach { $0.dragEnded() }
        scheduleCloseIfIdle()
    }

    /// A drag over the notch finished (dropped or cancelled). The pointer may have left during it,
    /// and AppKit sends no hover events while dragging, so check where it is now.
    public func dragConcluded() {
        NotificationCenter.default.post(name: Self.dragSettled, object: self)
        modules.forEach { $0.dragEnded() }
        closeIfPointerOutside()
    }

    /// A drag out of a module ended (dropped or cancelled).
    public func dragOutEnded() {
        NotificationCenter.default.post(name: Self.dragSettled, object: self)
    }

    /// The panel stopped being the key window: key presses go elsewhere now.
    public func keyFocusLost() {
        endHomeEditing()
        modules.forEach { $0.keyFocusLost() }
        // Another app took the keyboard: the typed search stays, but no longer holds the notch open.
        if library.isTyping {
            library.isTyping = false
            holdReleased()
        }
    }

    /// The module stopped holding the notch open (menu dismissed, drag-out ended, prompt answered).
    public func holdReleased() {
        closeIfPointerOutside()
    }

    /// Something may have moved the pointer away without a hover exit, e.g. a swipe to another Space
    /// (macOS hides the notch during it). Closes like a hover exit if the pointer isn't on the notch.
    public func pointerMayHaveLeft() {
        updatePeekHover()
        guard !isPinned, !layout.outline(for: state, contains: pointerLocation()) else { return }
        // A hover-open still waiting for its delay would otherwise open it with the pointer gone.
        hoverTask?.cancel()
        waitsForPointerToLeave = false
        scheduleCloseIfIdle()
    }

    /// A key press while the notch has keyboard focus: the module first, then Escape leaves Home
    /// or closes.
    public func handleKey(_ event: NSEvent) -> Bool {
        cancelAttentionClose()
        if isEditingHome, event.keyCode == 53 { endHomeEditing(); return true }
        if isEditingHome, event.charactersIgnoringModifiers?.lowercased() == "z",
           event.modifierFlags.contains(.command) {
            if event.modifierFlags.contains(.shift) { redoHomeEdit() } else { undoHomeEdit() }
            return true
        }
        if showsModule, selectedModule?.handleKey(event) == true { return true }
        if showsLibrary, handleLibraryKey(event) { return true }
        if showsHome, event.keyCode == 125 || event.keyCode == 126 { // Down and Up arrows: Home's pages
            showHomePage(homePage + (event.keyCode == 125 ? 1 : -1))
            return true
        }
        if showsHome, event.keyCode == 123 || event.keyCode == 124 { // Left and Right: along the bar
            showAdjacentPlace(forward: event.keyCode == 124, byKey: true)
            return true
        }
        // 1–9: the module with that number on the Modules page (switched-off ones keep theirs), 0:
        // Home. Not while typing in a field, or when something holds the module open (the tabs hide
        // then too).
        if let digit = Self.digitKeyCodes.firstIndex(of: event.keyCode),
           event.modifierFlags.intersection([.command, .option, .control]).isEmpty,
           !(event.window?.firstResponder is NSTextView), isEditingHome || !isHeld {
            if digit == 0 {
                guard homeIsAvailable else { return false }
                if !showsHome { toggleHome() }
                return true
            }
            let order = arrangement.order
            guard order.indices.contains(digit - 1),
                  let module = modules.first(where: { $0.moduleID == order[digit - 1] }) else { return false }
            // The person is still typing here: finish any Home edit without giving the keys back
            // or closing the notch under the module they just picked.
            endHomeEditing(keepsNotchFocused: true)
            select(module.moduleID)
            return true
        }
        if event.keyCode == 53 { // Escape: leave Home for the module, else close all the way
            if showsHome, selectedModule != nil {
                toggleHome()
                return true
            }
            staysCompact = false
            isHandlingClick = true
            defer { isHandlingClick = false }
            close()
            return true
        }
        return false
    }

    /// Key codes of the 0–9 keys on the top row, in digit order.
    private static let digitKeyCodes: [UInt16] = [29, 18, 19, 20, 21, 23, 22, 26, 28, 25]

    /// True while anything needs the notch to stay open: editing Home, a module (a prompt, a drag out), a
    /// menu, or a search being typed in the Library.
    var isHeld: Bool { isEditingHome || isModuleHeld || isShowingMenu || libraryHoldsOpen }

    /// A module needs the notch to itself: the bar hides and moving to another place is off.
    var isModuleHeld: Bool { modules.contains { $0.holdsOpen } }

    /// A search typed in the Library holds the notch open, like any field being typed in.
    var libraryHoldsOpen: Bool { showsLibrary && library.isTyping && !library.query.isEmpty }

    private func closeIfPointerOutside() {
        guard !layout.outline(for: state, contains: pointerLocation()) else { return }
        scheduleCloseIfIdle()
    }

    private func scheduleCloseIfIdle() {
        guard !isPinned, state > restingState, !isHeld else { return }
        schedule(after: behavior.closeDelay) { model in
            guard !model.isHeld else { return }
            model.close()
        }
    }

    /// A click opens the notch. On the open panel it shrinks it to Compact, where it then stays
    /// (hovering opens it, leaving shrinks it back); the next click on the open panel closes it all
    /// the way (ADR-0011).
    public func tap() {
        Self.logger.debug("Tap in \(self.state.rawValue, privacy: .public)")
        isHandlingClick = true
        defer { isHandlingClick = false }
        cancelAttentionClose()
        guard state == .expanded else {
            if pointerOverEarOverflow() {
                open(preferringHome: true)
            } else {
                open(focusing: moduleUnderPointer())
            }
            // Opened with a click: its keys (1–9, 0, Esc) work right away, as after the shortcut.
            if state == .expanded, !modules.isEmpty { requestKeyFocus?() }
            return
        }
        // Editing Home: a click in a gap, the band or the side (widgets and buttons take their own) finishes.
        if isEditingHome {
            endHomeEditing()
            return
        }
        guard !isHeld else { return }
        hoverTask?.cancel()
        if staysCompact {
            staysCompact = false
            close()
            // The pointer is still there: don't reopen until it has left.
            waitsForPointerToLeave = true
        } else {
            staysCompact = true
            waitsForPointerToLeave = true
            transition(to: .compact)
        }
    }

    /// Opens or closes the notch, e.g. from the keyboard shortcut. Closing goes all the way.
    public func toggle() {
        guard state != .expanded else {
            staysCompact = false
            close()
            return
        }
        open()
    }

    /// Opens the panel on the most relevant module (or `moduleID`), unless Mission Control is up: the
    /// notch is hidden there but still gets the pointer, and opening it would cover the Spaces bar and
    /// steal its clicks.
    /// `preferringHome` is the "+n" overflow chip's path: it opens Home when available, else the
    /// best-ranked displaced module (see `chooseModuleForOpening`).
    public func open(focusing moduleID: String? = nil, fromHover: Bool = false, preferringHome: Bool = false) {
        hoverTask?.cancel()
        cancelAttentionClose()
        guard !isMissionControlActive() else {
            Self.logger.info("Not opening: Mission Control is up")
            return
        }
        waitsForPointerToLeave = false
        briefTask?.cancel()
        isShowingBriefly = false
        briefModuleID = nil
        endPeek(animated: false)
        if state != .expanded { chooseModuleForOpening(moduleID, preferringHome: preferringHome) }
        wasOpenedByHover = fromHover
        transition(to: .expanded)
    }

    public func close() {
        hoverTask?.cancel()
        cancelAttentionClose()
        waitsForPointerToLeave = false
        if let brief = briefCompactOnClose {
            briefCompactOnClose = nil
            showBriefly(for: brief.duration, moduleID: brief.moduleID)
        }
        transition(to: restingTarget)
    }

    /// A module's alert (a timer that finished) wants to be seen: opens where the notch can show, through
    /// the window controller (`presentAttention`), or right here in a preview.
    public func requestAttention(from module: any NotchModule, revealsInFullScreen: Bool) {
        guard modules.contains(where: { $0 === module }) else { return }
        if isEditingHome { endHomeEditing(); select(module.moduleID) }
        if let presentAttention {
            presentAttention(module.moduleID, revealsInFullScreen)
        } else {
            openForAttention(focusing: module.moduleID)
        }
    }

    /// A module's alert (a timer that finished) wants to be seen, but only as its strip under the notch for
    /// `duration`, not by opening the notch. Shown where the notch can show, like `requestAttention`; not
    /// while Mission Control is up (the ear tells instead). Hovering holds the strip; clicking opens it.
    public func requestPeek(from module: any NotchModule, for duration: Duration, revealsInFullScreen: Bool) {
        guard modules.contains(where: { $0 === module }), !isMissionControlActive() else { return }
        if let presentPeek {
            presentPeek(module.moduleID, duration, revealsInFullScreen)
        } else {
            peek(module, for: duration)
        }
    }

    /// Opens on `moduleID` for an alert. Left untouched for `attentionCloseDelay` with the pointer away,
    /// it closes again; the module's ear keeps showing what happened. Does nothing while already open.
    public func openForAttention(focusing moduleID: String) {
        if isEditingHome {
            endHomeEditing()
            select(moduleID)
            return
        }
        guard !isPinned, state != .expanded else { return }
        open(focusing: moduleID)
        guard state == .expanded else { return }
        let delay = attentionCloseDelay
        attentionTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            self.attentionTask = nil
            guard self.state == .expanded, !self.isHeld,
                  !self.layout.outline(for: self.state, contains: self.pointerLocation()) else { return }
            self.close()
        }
    }

    /// A module's own control was used (a click, or VoiceOver with the pointer elsewhere): the notch is in
    /// use, so the alert's close is off.
    public func userInteracted() {
        cancelAttentionClose()
    }

    private func cancelAttentionClose() {
        attentionTask?.cancel()
        attentionTask = nil
    }

    /// The next close goes through Compact and stays there for `duration` (e.g. the Shelf confirming a
    /// drop with its count), then the notch goes back to its resting state. `module` gets an ear for it.
    public func closeThroughCompact(for duration: Duration, showing module: (any NotchModule)? = nil) {
        briefCompactOnClose = (duration, module?.moduleID)
    }

    private func showBriefly(for duration: Duration, moduleID: String?) {
        isShowingBriefly = true
        briefModuleID = moduleID
        briefTask?.cancel()
        briefTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled, let self else { return }
            self.endBriefCompact()
        }
    }

    private func endBriefCompact() {
        briefTask?.cancel()
        briefTask = nil
        guard isShowingBriefly else { return }
        isShowingBriefly = false
        briefModuleID = nil
        if state != .expanded { transition(to: restingTarget) }
    }

    /// Shows `module`'s peek strip for `duration`, holding it if the pointer is over the strip at expiry.
    /// Ignored while the notch is open.
    @discardableResult
    public func peek(_ module: any NotchModule, for duration: Duration,
                     revealOverFullScreen: Bool = false, waitingForOtherPeeks: Bool = false) -> Bool {
        guard state != .expanded, !isPinned, !isMissionControlActive(),
              !waitingForOtherPeeks || peekModuleID == nil,
              modules.contains(where: { $0 === module }), module.peekView(layout: layout) != nil,
              automaticPeeksAvailable, prepareAutomaticPeek?(revealOverFullScreen) != false else { return false }
        peekGeneration += 1
        cancelPeekTimeout()
        peekModuleID = module.moduleID
        let grows = !layout.isPeeking
        if grows {
            var target = layout
            target.isPeeking = true
            earsAsleep = false
            withAnimation(Self.animation(opening: true, reducesMotion: motion.reducesMotion)) {
                layout = target
                if state == .closed { state = .compact }
            }
        }
        schedulePeekTimeout(after: duration)
        // Grow the window right away; the outline animates inside it.
        if grows { fitWindow?(.compact) }
        return true
    }

    /// The pointer can leave the strip for an ear without leaving the notch outline.
    func updatePeekHover() {
        let onStrip = layout.isPeeking && peekStripContains(pointerLocation())
        defer { pointerWasOnPeekStrip = onStrip }
        guard layout.isPeeking else { return }
        if onStrip {
            hoverTask?.cancel()
            hoverTask = nil
            guard isPeekHeld else { return }
            peekTask?.cancel()
            peekTask = nil
        } else {
            if isPeekHeld, peekTask == nil {
                schedulePeekTimeout(after: behavior.closeDelay)
            }
            // Leaving the strip for an ear or the band counts as arriving there: no outline
            // enter fires inside the outline, so schedule the hover-open it would have.
            guard pointerWasOnPeekStrip, hoverTask == nil, !isPinned,
                  !behavior.openOnClickOnly, state != .expanded, !waitsForPointerToLeave,
                  layout.outline(for: .compact, contains: pointerLocation()) else { return }
            scheduleHoverOpen()
        }
    }

    private func schedulePeekTimeout(after delay: Duration) {
        peekTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            self.peekTask = nil
            if self.peekStripContains(self.pointerLocation()) {
                self.isPeekHeld = true
            } else {
                self.endPeek(animated: true)
            }
        }
    }

    private func cancelPeekTimeout() {
        peekTask?.cancel()
        peekTask = nil
        isPeekHeld = false
        pointerWasOnPeekStrip = false
    }

    /// The hover-open `hoverChanged(true)` schedules. The strip itself doesn't open on hover.
    private func scheduleHoverOpen() {
        schedule(after: behavior.openDelay) { model in
            guard !model.peekStripContains(model.pointerLocation()) else { return }
            if model.pointerOverEarOverflow() {
                model.open(fromHover: true, preferringHome: true)
            } else {
                model.open(focusing: model.moduleUnderPointer(), fromHover: true)
            }
            if model.state == .expanded, model.behavior.hapticOnOpen {
                NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
            }
        }
    }

    /// Cancels only this module's strip (e.g. its notification preference was switched off).
    public func cancelPeek(for module: any NotchModule) {
        guard peekModuleID == module.moduleID else { return }
        endPeek(animated: true)
    }

    /// Shows `module`'s peek strip without timing it out (off-screen snapshots).
    public func peekForSnapshot(_ module: any NotchModule) {
        peekGeneration += 1
        cancelPeekTimeout()
        peekModuleID = module.moduleID
        layout.isPeeking = true
    }

    /// Ends `module`'s peek strip early: what it told is no longer true (a finished timer was stopped
    /// in the app window).
    public func endPeek(of module: any NotchModule) {
        guard peekModuleID == module.moduleID else { return }
        endPeek(animated: true)
    }

    private func endPeek(animated: Bool) {
        peekGeneration += 1
        let generation = peekGeneration
        cancelPeekTimeout()
        guard layout.isPeeking else {
            peekModuleID = nil
            return
        }
        guard animated else {
            layout.isPeeking = false
            peekModuleID = nil
            return
        }
        transitionID += 1
        withAnimation(Self.animation(opening: false, reducesMotion: motion.reducesMotion)) {
            layout.isPeeking = false
            if state == .compact { state = restingTarget }
        } completion: { [weak self] in
            // A new peek may have started while this one slid away: it keeps its strip.
            // An unrelated ear/state transition mustn't leave the strip permanently busy.
            guard let self, self.peekGeneration == generation, !self.layout.isPeeking else { return }
            self.peekModuleID = nil
            self.fitWindow?(self.state)
            if self.state == .closed { self.earsAsleep = true }
        }
    }

    private func schedule(after delay: Duration, _ action: @escaping @MainActor (NotchViewModel) -> Void) {
        hoverTask?.cancel()
        hoverTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            action(self)
        }
    }

    /// Moves to `newState` with the matching animation. Opening springs slightly; closing doesn't.
    public func transition(to newState: NotchState) {
        guard newState != state else { return }
        lastChangeWasClick = isHandlingClick
        Self.logger.debug("State \(self.state.rawValue, privacy: .public) → \(newState.rawValue, privacy: .public)")
        let opening = newState == .expanded
        let closing = state == .expanded
        transitionID += 1
        let id = transitionID
        fitWindow?(max(state, newState))
        earsAsleep = false
        withAnimation(Self.animation(opening: opening, reducesMotion: motion.reducesMotion)) {
            state = newState
            // A taller panel shrinks along with the close.
            if closing { layout.panelHeight = .regular }
        } completion: { [weak self] in
            // Shrink only after the latest animation, so an earlier one can't clip a newer one.
            guard let self, self.transitionID == id else { return }
            self.fitWindow?(self.state)
            if self.state == .closed { self.earsAsleep = true }
            // Resizing the hover area can swallow an exit while the notch opens. Check once it
            // settles; clicks, shortcuts and drags keep their own rules for closing.
            if opening, self.wasOpenedByHover { self.pointerMayHaveLeft() }
        }
        if opening {
            onOpen?()
            if showsModule, let selected = selectedModule {
                selected.notchDidOpen()
                moduleShown(selected.moduleID)
            }
        }
        if closing { leftExpanded() }
    }

    private func leftExpanded() {
        endHomeEditing()
        releaseKeyFocus?()
        if showsModule { selectedModule?.notchDidClose() }
        showsHome = false
        showsLibrary = false
        resetHub()
        swipe.reset()
    }

    /// Returns to the resting state without animating (e.g. the display went away).
    public func reset() {
        peekGeneration += 1
        hoverTask?.cancel()
        cancelAttentionClose()
        briefTask?.cancel()
        cancelPeekTimeout()
        isShowingBriefly = false
        briefModuleID = nil
        briefCompactOnClose = nil
        peekModuleID = nil
        transitionID += 1
        staysCompact = false
        waitsForPointerToLeave = false
        wasOpenedByHover = false
        modules.forEach { $0.dragEnded() }
        let wasExpanded = state == .expanded
        state = restingState
        earsAsleep = state == .closed
        layout.panelHeight = .regular
        layout.isPeeking = false
        fitWindow?(state)
        if wasExpanded { leftExpanded() }
    }

    /// Growing to a taller panel and back: quicker than opening, it follows a click.
    static var tallAnimation: Animation { tallAnimation(reducesMotion: MotionSettings.shared.reducesMotion) }

    /// Switching modules or showing Home: a quick slide, or a cross-fade with Reduce Motion.
    static var switchAnimation: Animation { switchAnimation(reducesMotion: MotionSettings.shared.reducesMotion) }

    static func animation(opening: Bool) -> Animation {
        animation(opening: opening, reducesMotion: MotionSettings.shared.reducesMotion)
    }

    static func tallAnimation(reducesMotion: Bool) -> Animation {
        reducesMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.28, dampingFraction: 0.88)
    }

    static func switchAnimation(reducesMotion: Bool) -> Animation {
        reducesMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.32, dampingFraction: 0.86)
    }

    static func animation(opening: Bool, reducesMotion: Bool) -> Animation {
        if reducesMotion { return .easeInOut(duration: 0.2) }
        return opening
            ? .spring(response: 0.42, dampingFraction: 0.8)
            : .spring(response: 0.45, dampingFraction: 1.0)
    }
}
