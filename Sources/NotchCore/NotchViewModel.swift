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
    /// Which way the last module switch went, for the slide (forward = towards later modules).
    public private(set) var switchedForward = true
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

    public init(
        layout: NotchLayout,
        state: NotchState = .closed,
        behavior: NotchBehavior = NotchBehavior(),
        arrangement: ModuleArrangement? = nil,
        home: HomeSettings? = nil,
        pointerLocation: @escaping @MainActor () -> CGPoint = { NSEvent.mouseLocation },
        isMissionControlActive: @escaping @MainActor () -> Bool = { MissionControlDetector.isActive }
    ) {
        self.layout = layout
        self.state = state
        self.earsAsleep = state == .closed
        self.behavior = behavior
        self.arrangement = arrangement ?? ModuleArrangement()
        self.home = home ?? HomeSettings()
        self.pointerLocation = pointerLocation
        self.isMissionControlActive = isMissionControlActive
        watchNavigation()
    }

    // MARK: Modules

    private func modulesChanged(from oldModules: [any NotchModule]) {
        let removed = oldModules.filter { old in !modules.contains { $0 === old } }
        let added = modules.filter { new in !oldModules.contains { $0 === new } }
        let selectedBefore = oldModules.first { $0.moduleID == selectedID } ?? arrangement.sorted(oldModules) { $0.moduleID }.first
        let wasMenu = showsHome
        for module in removed {
            if state == .expanded, module === selectedBefore, !showsHome { module.notchDidClose() }
            module.attach(to: nil)
        }
        if selectedID == nil || !modules.contains(where: { $0.moduleID == selectedID }) {
            selectedID = rankedModules.first?.moduleID
        }
        if !homeIsAvailable { showsHome = false }
        // The last module went away while it showed: Home takes its place.
        if modules.isEmpty, state == .expanded, homeIsAvailable, !showsHome {
            chosenHomePage = 0 // Home always comes up on its first page.
            showsHome = true
        }
        for module in added { module.attach(to: self) }
        // Attached while already open (e.g. pinned with PANCAKENOTCH_DEBUG_STATE=expanded), or Home
        // went away with the module before last.
        if state == .expanded, !showsHome, let selected = selectedModule,
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

    /// Shows a module in the open notch (a tab, Home, a swipe). Only the user switches; opening
    /// picks the module itself (`open`).
    public func select(_ moduleID: String) {
        endHomeEditing()
        guard let target = modules.first(where: { $0.moduleID == moduleID }) else { return }
        cancelAttentionClose()
        let previous = selectedModule
        let wasMenu = showsHome
        if let previous, previous !== target {
            switchedForward = arrangement.rank(of: moduleID) >= arrangement.rank(of: previous.moduleID)
        }
        withAnimation(Self.switchAnimation) {
            showsHome = false
            selectedID = moduleID
        }
        guard previous !== target || wasMenu else { return }
        if state == .expanded {
            if !wasMenu { previous?.notchDidClose() }
            target.notchDidOpen()
            onModuleShown?(moduleID)
        }
        if previous !== target { previous?.userSwitchedAway() }
    }

    /// Opens or closes Home in the open notch. With no module to go back to, Home stays.
    public func toggleHome() {
        // While editing, the Home button finishes editing and stays on Home.
        if isEditingHome {
            endHomeEditing()
            return
        }
        guard state == .expanded, homeIsAvailable, !isHeld else { return }
        let opening = !showsHome
        guard opening || selectedModule != nil else { return }
        cancelAttentionClose()
        withAnimation(Self.switchAnimation) {
            showsHome = opening
            if opening { chosenHomePage = 0 }
        }
        if opening { selectedModule?.notchDidClose() } else { selectedModule?.notchDidOpen() }
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
        withAnimation(Self.switchAnimation) { showsHome = false }
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

    public func endHomeEditing() {
        guard isEditingHome else { return }
        let shownPage = homePages.indices.contains(homePage) ? homePages[homePage] : 0
        isEditingHome = false
        chosenHomePage = homePages.firstIndex(of: shownPage) ?? 0
        showsHomePicker = false
        if let monitor = homeOutsideLocal { NSEvent.removeMonitor(monitor) }
        if let monitor = homeOutsideGlobal { NSEvent.removeMonitor(monitor) }
        homeOutsideLocal = nil
        homeOutsideGlobal = nil
        releaseKeyFocus?()
        holdReleased()
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
        if isEditingHome || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion || snapshotClock != nil {
            resetHomeMotion()
            withAnimation(Self.switchAnimation) { chosenHomePage = index }
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

    /// The modules the tabs show: favorites (or all, with tabs only), plus the current one.
    public var tabModules: [any NotchModule] {
        let ranked = rankedModules
        guard arrangement.navigation == .tabsAndMenu else { return ranked }
        return ranked.filter { arrangement.isFavorite($0.moduleID) || $0.moduleID == selectedModule?.moduleID }
    }

    /// Whether the tabs and Home button show: several modules or Home to go to, and nothing holding the
    /// current module open.
    public var showsModuleBar: Bool {
        (modules.count > 1 || homeIsAvailable) && (isEditingHome || !isHeld)
    }

    /// Moves to the next or previous module by ranking (two-finger swipe).
    public func showAdjacentModule(forward: Bool) {
        let ranked = rankedModules
        guard ranked.count > 1, !isHeld,
              let index = ranked.firstIndex(where: { $0.moduleID == selectedModule?.moduleID }) else { return }
        let next = index + (forward ? 1 : -1)
        guard ranked.indices.contains(next) else { return }
        select(ranked[next].moduleID)
    }

    /// A scroll in the open notch: a sideways two-finger swipe switches modules, unless it scrolls
    /// something inside the module. `point` is in notch-body coordinates. Returns whether it was used.
    @discardableResult
    public func handleScroll(_ event: NSEvent, at point: CGPoint) -> Bool {
        if state == .expanded, showsHome {
            swipe.ignoreCurrentGesture()
            return scrollHome(event)
        }
        guard state == .expanded, modules.count > 1 else {
            // A gesture that started before the notch opened scrolls something else, not the modules.
            swipe.ignoreCurrentGesture()
            return false
        }
        if event.phase == .began, selectedModule?.scrollsHorizontally(at: point) == true || showsHome {
            swipe.ignoreCurrentGesture()
            return false
        }
        // Follow the fingers whatever the "natural scrolling" setting: positive = fingers moving right.
        let fingersX = event.isDirectionInvertedFromDevice ? event.scrollingDeltaX : -event.scrollingDeltaX
        guard let forward = swipe.handle(
            phase: NotchSwipeTracker.Phase(event),
            deltaX: fingersX,
            deltaY: event.scrollingDeltaY,
            isPrecise: event.hasPreciseScrollingDeltas
        ) else { return false }
        showAdjacentModule(forward: forward)
        return true
    }

    /// Picks what to open on: the module asked for (its ear or strip was pointed at, a drag), else the
    /// first by ranking that waits for you (an agent's question, a finished timer), else Home when the
    /// person chose it in Settings, else the first module that wants it (music playing), otherwise the one
    /// used last, or Home if that module is idle and Home is available. Home also opens when there are
    /// no modules (ADR-0010, ADR-0011 amendment 2026-11-03, ADR-0042).
    private func chooseModuleForOpening(_ moduleID: String?) {
        resetHomeMotion()
        showsHome = false
        chosenHomePage = 0
        let ranked = rankedModules
        if let moduleID, modules.contains(where: { $0.moduleID == moduleID }) {
            selectedID = moduleID
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

    /// Scrolling up or down on Home moves one whole page per gesture (or per wheel step).
    private func scrollHome(_ event: NSEvent) -> Bool {
        let phase = NotchSwipeTracker.Phase(event)
        if isEditingHome || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion || !event.hasPreciseScrollingDeltas {
            guard let step = homeScroll.handle(phase: phase, deltaY: event.scrollingDeltaY,
                deltaX: event.scrollingDeltaX, isPrecise: event.hasPreciseScrollingDeltas,
                time: event.timestamp) else { return false }
            showHomePage(homePage + step)
            return true
        }
        return handleHomePreciseScroll(phase: phase, deltaY: event.scrollingDeltaY,
            deltaX: event.scrollingDeltaX, time: event.timestamp, momentum: !event.momentumPhase.isEmpty)
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
        let height = HomeWidgetMetrics.gridArea(in: layout).height
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
        let target = homeMotion.target(height: HomeWidgetMetrics.gridArea(in: layout).height,
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
    }

    /// What the compact ears show: the top two active modules by ranking, #1's main view on the left
    /// and #2's on the right (or swapped). Modules that wait for you (an agent's question, a finished
    /// timer) get a spot before the others, which then wait; the spots still follow the ranking. A module
    /// that asks for the second ear (the Timer), or one shown briefly (the Shelf's after-drop count),
    /// takes #2 and leaves #1 to the best other one. A module that asks for the first ear (Keep Awake)
    /// takes #1, unless #2 is taken and something else waits for you: then that gets #1. A module alone
    /// fills both ears if it has an extra view. With nothing active, the current module shows for the
    /// short shrink after a click only, not for a peek strip.
    public func ears(layout: NotchLayout) -> (left: EarSlot?, right: EarSlot?) {
        var shown = rankedModules.filter { $0.isActive || $0.moduleID == briefModuleID }
        // Not while a strip is up (peekModuleID lasts until its exit animation ends, so no ear flashes in).
        if shown.isEmpty, peekModuleID == nil || staysCompact, let selected = selectedModule { shown = [selected] }
        // Only modules that have ears take a side.
        let withEars = shown.compactMap { module in module.compactEars(layout: layout).map { (module, $0) } }
        // Waiting alerts choose first, including among competing second-spot claims.
        let waiting = withEars.filter { $0.0.waitsForYou }
        let byPriority = waiting + withEars.filter { !$0.0.waitsForYou }
        var firstClaim = withEars.first { $0.0.prefersFirstEar }
        let secondClaim = byPriority.first { $0.0 !== firstClaim?.0 && takesSecondEar($0.0) }
        // Both claimed while something else waits for you: what needs you comes first.
        if let claimed = firstClaim, let second = secondClaim,
           withEars.contains(where: { $0.0.waitsForYou && $0.0 !== claimed.0 && $0.0 !== second.0 }) {
            firstClaim = nil
        }
        // Set spots reserve remaining room ahead of ordinary activity, never ahead of waiting alerts.
        let ordinarySecond = withEars.first {
            !$0.0.waitsForYou && $0.0 !== firstClaim?.0 && takesSecondEar($0.0)
        }
        let reserved = [firstClaim, ordinarySecond].compactMap { $0 }.filter { !$0.0.waitsForYou }
        let candidates = waiting + reserved + withEars.filter { candidate in
            !candidate.0.waitsForYou && !reserved.contains { $0.0 === candidate.0 }
        }
        let chosen = candidates.prefix(2).map(\.0.moduleID)
        var picked = withEars.filter { chosen.contains($0.0.moduleID) }
        // Place only the chosen modules. A waiting timer keeps #2 ahead of a brief Shelf badge.
        let selectedFirst = picked.first { $0.0.prefersFirstEar }
        let secondCandidates = picked.filter { $0.0.waitsForYou } + picked.filter { !$0.0.waitsForYou }
        let selectedSecond = secondCandidates.first { $0.0 !== selectedFirst?.0 && takesSecondEar($0.0) }
        if picked.count > 1,
           let first = selectedFirst ?? picked.first(where: { $0.0 !== selectedSecond?.0 }),
           let second = selectedSecond ?? picked.first(where: { $0.0 !== first.0 }) {
            picked = [first, second]
        }
        var slots: [EarSlot?] = []
        if picked.count == 1, let (module, ears) = picked.first {
            let main = EarSlot(id: module.moduleID + ".main", moduleID: module.moduleID, view: ears.main)
            let extra = ears.extra.map { EarSlot(id: module.moduleID + ".extra", moduleID: module.moduleID, view: $0) }
            slots = module.prefersSecondEar ? [extra, main] : [main, extra]
        } else {
            slots = picked.map { module, ears in EarSlot(id: module.moduleID + ".main", moduleID: module.moduleID, view: ears.main) }
        }
        let first = slots.first ?? nil
        let second = slots.count > 1 ? slots[1] : nil
        return arrangement.swapsEarSides ? (second, first) : (first, second)
    }

    /// Asks for #2: the Timer while it runs, or a module shown briefly that isn't active on its own.
    private func takesSecondEar(_ module: any NotchModule) -> Bool {
        module.prefersSecondEar || (module.moduleID == briefModuleID && !module.isActive)
    }

    /// The module the pointer is on in the compact notch: the strip's module anywhere on the strip, else the
    /// module whose ear it's over. Hovering or clicking there opens the notch on it. `nil` in the middle,
    /// over the hardware notch, where opening picks the module itself.
    func moduleUnderPointer() -> String? {
        guard state == .compact else { return nil }
        let point = pointerLocation()
        let geometry = layout.geometry
        let notch = geometry.notchRect
        guard layout.outline(for: .compact, contains: point) else { return nil }
        // The strip hangs below the ears (y grows upwards on screen).
        if point.y < notch.maxY - geometry.compactHeight {
            guard layout.isPeeking, let peekModuleID, modules.contains(where: { $0.moduleID == peekModuleID }) else { return nil }
            return peekModuleID
        }
        guard point.x < notch.minX || point.x >= notch.maxX else { return nil }
        let ears = ears(layout: layout)
        return (point.x < notch.minX ? ears.left : ears.right)?.moduleID
    }

    /// The peek strip's view while a module is peeking.
    var peekView: AnyView? {
        guard layout.isPeeking, let peekModuleID else { return nil }
        return modules.first { $0.moduleID == peekModuleID }?.peekView(layout: layout)
    }

    // MARK: Hover, clicks and drags

    /// Called when the pointer enters or leaves the notch outline.
    public func hoverChanged(_ isHovering: Bool) {
        // When the window shrinks (e.g. after a click shrinks the panel), AppKit reports the pointer
        // leaving and coming straight back. A "left" while it's still on the notch isn't real: ignoring it
        // keeps the click's "don't reopen" in place.
        if !isHovering, layout.outline(for: state, contains: pointerLocation()) { return }
        hoverTask?.cancel()
        cancelAttentionClose()
        guard !isPinned else { return }
        if isHovering {
            guard !behavior.openOnClickOnly, state != .expanded, !waitsForPointerToLeave else { return }
            schedule(after: behavior.openDelay) { model in
                model.open(focusing: model.moduleUnderPointer(), fromHover: true)
                if model.state == .expanded, model.behavior.hapticOnOpen {
                    NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
                }
            }
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
        } else if let moduleID, moduleID != selectedModule?.moduleID || showsHome, !isHeld {
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
        withAnimation(Self.tallAnimation) {
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
    }

    /// The module stopped holding the notch open (menu dismissed, drag-out ended, prompt answered).
    public func holdReleased() {
        closeIfPointerOutside()
    }

    /// Something may have moved the pointer away without a hover exit, e.g. a swipe to another Space
    /// (macOS hides the notch during it). Closes like a hover exit if the pointer isn't on the notch.
    public func pointerMayHaveLeft() {
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
        if !showsHome, selectedModule?.handleKey(event) == true { return true }
        if showsHome, event.keyCode == 125 || event.keyCode == 126 { // Down and Up arrows: Home's pages
            showHomePage(homePage + (event.keyCode == 125 ? 1 : -1))
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

    /// True while any module needs the notch to stay open.
    var isHeld: Bool { isEditingHome || modules.contains { $0.holdsOpen } }

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
            open(focusing: moduleUnderPointer())
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
    public func open(focusing moduleID: String? = nil, fromHover: Bool = false) {
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
        if state != .expanded { chooseModuleForOpening(moduleID) }
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
    /// while Mission Control is up (the ear tells instead). Hovering or clicking the strip opens the notch.
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

    /// Shows `module`'s peek strip under the compact notch for `duration` (the new song's title), then
    /// goes back. Ignored while the notch is open.
    @discardableResult
    public func peek(_ module: any NotchModule, for duration: Duration,
                     revealOverFullScreen: Bool = false, waitingForOtherPeeks: Bool = false) -> Bool {
        guard state != .expanded, !isPinned, !isMissionControlActive(),
              !waitingForOtherPeeks || peekModuleID == nil,
              modules.contains(where: { $0 === module }), module.peekView(layout: layout) != nil,
              automaticPeeksAvailable, prepareAutomaticPeek?(revealOverFullScreen) != false else { return false }
        peekGeneration += 1
        peekTask?.cancel()
        peekModuleID = module.moduleID
        if !layout.isPeeking {
            var target = layout
            target.isPeeking = true
            earsAsleep = false
            withAnimation(Self.animation(opening: true)) {
                layout = target
                if state == .closed { state = .compact }
            }
            // Grow the window right away; the outline animates inside it.
            fitWindow?(.compact)
        }
        peekTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self?.endPeek(animated: true)
        }
        return true
    }

    /// Cancels only this module's strip (e.g. its notification preference was switched off).
    public func cancelPeek(for module: any NotchModule) {
        guard peekModuleID == module.moduleID else { return }
        endPeek(animated: true)
    }

    /// Shows `module`'s peek strip without timing it out (off-screen snapshots).
    public func peekForSnapshot(_ module: any NotchModule) {
        peekGeneration += 1
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
        peekTask?.cancel()
        peekTask = nil
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
        withAnimation(Self.animation(opening: false)) {
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
        withAnimation(Self.animation(opening: opening)) {
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
            if !showsHome, let selected = selectedModule {
                selected.notchDidOpen()
                onModuleShown?(selected.moduleID)
            }
        }
        if closing { leftExpanded() }
    }

    private func leftExpanded() {
        endHomeEditing()
        releaseKeyFocus?()
        if !showsHome { selectedModule?.notchDidClose() }
        showsHome = false
        swipe.reset()
    }

    /// Returns to the resting state without animating (e.g. the display went away).
    public func reset() {
        peekGeneration += 1
        hoverTask?.cancel()
        cancelAttentionClose()
        briefTask?.cancel()
        peekTask?.cancel()
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
    static var tallAnimation: Animation {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            ? .easeInOut(duration: 0.15)
            : .spring(response: 0.28, dampingFraction: 0.88)
    }

    /// Switching modules or showing Home: a quick slide, or a cross-fade with Reduce Motion.
    static var switchAnimation: Animation {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            ? .easeInOut(duration: 0.15)
            : .spring(response: 0.32, dampingFraction: 0.86)
    }

    static func animation(opening: Bool) -> Animation {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            return .easeInOut(duration: 0.2)
        }
        return opening
            ? .spring(response: 0.42, dampingFraction: 0.8)
            : .spring(response: 0.45, dampingFraction: 1.0)
    }
}
