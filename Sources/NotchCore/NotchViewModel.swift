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
    /// The open notch shows the Module Menu instead of a module.
    public private(set) var showsMenu = false
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
    /// The Menu's gear: opens the app window. `nil` hides the gear (previews).
    @ObservationIgnored public var openSettings: (() -> Void)?

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
    @ObservationIgnored private var transitionID = 0
    /// Settled in Closed: the ears (faded out under the notch) aren't built, about 1 MiB less while the
    /// notch rests (measured). Every way out of Closed wakes them before it animates.
    public private(set) var earsAsleep = false
    @ObservationIgnored private var swipe = NotchSwipeTracker()

    public init(
        layout: NotchLayout,
        state: NotchState = .closed,
        behavior: NotchBehavior = NotchBehavior(),
        arrangement: ModuleArrangement? = nil,
        pointerLocation: @escaping @MainActor () -> CGPoint = { NSEvent.mouseLocation },
        isMissionControlActive: @escaping @MainActor () -> Bool = { MissionControlDetector.isActive }
    ) {
        self.layout = layout
        self.state = state
        self.earsAsleep = state == .closed
        self.behavior = behavior
        self.arrangement = arrangement ?? ModuleArrangement()
        self.pointerLocation = pointerLocation
        self.isMissionControlActive = isMissionControlActive
    }

    // MARK: Modules

    private func modulesChanged(from oldModules: [any NotchModule]) {
        let removed = oldModules.filter { old in !modules.contains { $0 === old } }
        let added = modules.filter { new in !oldModules.contains { $0 === new } }
        let selectedBefore = oldModules.first { $0.moduleID == selectedID } ?? arrangement.sorted(oldModules) { $0.moduleID }.first
        let wasMenu = showsMenu
        for module in removed {
            if state == .expanded, module === selectedBefore, !showsMenu { module.notchDidClose() }
            module.attach(to: nil)
        }
        if selectedID == nil || !modules.contains(where: { $0.moduleID == selectedID }) {
            selectedID = rankedModules.first?.moduleID
        }
        if modules.count < 2 { showsMenu = false }
        for module in added { module.attach(to: self) }
        // Attached while already open (e.g. pinned with PANCAKENOTCH_DEBUG_STATE=expanded), or the Menu
        // went away with the module before last.
        if state == .expanded, !showsMenu, let selected = selectedModule,
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

    /// Shows a module in the open notch (a tab, the Menu, a swipe). Only the user switches; opening
    /// picks the module itself (`open`).
    public func select(_ moduleID: String) {
        guard let target = modules.first(where: { $0.moduleID == moduleID }) else { return }
        let previous = selectedModule
        let wasMenu = showsMenu
        if let previous, previous !== target {
            switchedForward = arrangement.rank(of: moduleID) >= arrangement.rank(of: previous.moduleID)
        }
        withAnimation(Self.switchAnimation) {
            showsMenu = false
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

    /// Opens or closes the Module Menu in the open notch.
    public func toggleMenu() {
        guard state == .expanded, modules.count > 1, !isHeld else { return }
        let opening = !showsMenu
        withAnimation(Self.switchAnimation) { showsMenu = opening }
        if opening { selectedModule?.notchDidClose() } else { selectedModule?.notchDidOpen() }
    }

    /// The modules the tabs show: favorites (or all, without a Menu), plus the current one.
    public var tabModules: [any NotchModule] {
        let ranked = rankedModules
        guard arrangement.navigation == .tabsAndMenu else { return ranked }
        return ranked.filter { arrangement.isFavorite($0.moduleID) || $0.moduleID == selectedModule?.moduleID }
    }

    /// Whether the tabs/Menu bar shows: several modules, and nothing holding the current one open.
    public var showsModuleBar: Bool {
        modules.count > 1 && !isHeld
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
        guard state == .expanded, modules.count > 1 else {
            // A gesture that started before the notch opened scrolls something else, not the modules.
            swipe.ignoreCurrentGesture()
            return false
        }
        if event.phase == .began, selectedModule?.scrollsHorizontally(at: point) == true || showsMenu {
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

    /// Picks the module to open on: the first by ranking that wants it (music playing), otherwise
    /// the one used last (ADR-0010).
    private func chooseModuleForOpening(_ moduleID: String?) {
        showsMenu = false
        if let moduleID, modules.contains(where: { $0.moduleID == moduleID }) {
            selectedID = moduleID
        } else if let focused = rankedModules.first(where: { $0.wantsFocus }) {
            selectedID = focused.moduleID
        }
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
        public let view: AnyView
    }

    /// What the compact ears show: the top two active modules by ranking, #1's main view on the left
    /// and #2's on the right (or swapped). A module alone fills both ears if it has an extra view. With
    /// nothing active (the short shrink after a click), the current module shows.
    public func ears(layout: NotchLayout) -> (left: EarSlot?, right: EarSlot?) {
        var shown = rankedModules.filter { $0.isActive || $0.moduleID == briefModuleID }
        if shown.isEmpty, let selected = selectedModule { shown = [selected] }
        // Only modules that have ears take a side.
        let withEars = Array(shown.lazy.compactMap { module in module.compactEars(layout: layout).map { (module, $0) } }.prefix(2))
        var slots: [EarSlot?] = []
        for (module, ears) in withEars {
            slots.append(EarSlot(id: module.moduleID + ".main", view: ears.main))
            if withEars.count == 1, let extra = ears.extra {
                slots.append(EarSlot(id: module.moduleID + ".extra", view: extra))
            }
        }
        let first = slots.first ?? nil
        let second = slots.count > 1 ? slots[1] : nil
        return arrangement.swapsEarSides ? (second, first) : (first, second)
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
        guard !isPinned else { return }
        if isHovering {
            guard !behavior.openOnClickOnly, state != .expanded, !waitsForPointerToLeave else { return }
            schedule(after: behavior.openDelay) { model in
                model.open(fromHover: true)
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
        } else if let moduleID, moduleID != selectedModule?.moduleID || showsMenu, !isHeld {
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

    /// A key press while the notch has keyboard focus: the module first, then Escape leaves the Menu
    /// or closes.
    public func handleKey(_ event: NSEvent) -> Bool {
        if !showsMenu, selectedModule?.handleKey(event) == true { return true }
        if event.keyCode == 53 { // Escape: leave the Menu, else close all the way
            if showsMenu {
                toggleMenu()
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
    var isHeld: Bool { modules.contains { $0.holdsOpen } }

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
        guard state == .expanded else {
            open()
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
        waitsForPointerToLeave = false
        if let brief = briefCompactOnClose {
            briefCompactOnClose = nil
            showBriefly(for: brief.duration, moduleID: brief.moduleID)
        }
        transition(to: restingTarget)
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
            if !showsMenu, let selected = selectedModule {
                selected.notchDidOpen()
                onModuleShown?(selected.moduleID)
            }
        }
        if closing { leftExpanded() }
    }

    private func leftExpanded() {
        releaseKeyFocus?()
        if !showsMenu { selectedModule?.notchDidClose() }
        showsMenu = false
        swipe.reset()
    }

    /// Returns to the resting state without animating (e.g. the display went away).
    public func reset() {
        peekGeneration += 1
        hoverTask?.cancel()
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

    /// Switching modules or showing the Menu: a quick slide, or a cross-fade with Reduce Motion.
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
