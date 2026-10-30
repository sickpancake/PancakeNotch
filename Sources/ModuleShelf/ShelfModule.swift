import AppKit
import ConvertKit
import NotchCore
import Observation
import os
import SwiftUI

/// What the user just did on this Shelf, for the app window's lessons.
public enum ShelfEvent: Equatable, Sendable {
    /// The items changed (added, removed, edited); `count` is the new number of items.
    case itemsChanged(count: Int)
    /// An item opened in the tall notch (text editor, link editor or file preview).
    case detailOpened
    /// Back to the tiles from the tall notch.
    case detailClosed
    /// The number of selected items changed.
    case selectionChanged(count: Int)
    /// The right-click menu opened.
    case menuOpened
    case menuClosed
    /// Clear all was confirmed.
    case cleared
    /// A drag out of the Shelf ended; `accepted` is whether something took it.
    case dragOutEnded(accepted: Bool)
    /// Items were handed to AirDrop (from the drop zone or the menu), for statistics.
    case airDropped(count: Int)
}

/// The Shelf: a drop zone in the notch for files, images, text and links (ADR-0013).
@MainActor
@Observable
public final class ShelfModule: NotchModule {
    public let store: ShelfStore
    public let settings: ShelfSettings
    let thumbnails = ShelfThumbnails()
    let largePreview = ShelfLargePreview()
    @ObservationIgnored let sharing = ShelfSharing()
    @ObservationIgnored let quickLook = ShelfQuickLook()

    @ObservationIgnored private(set) weak var notch: NotchViewModel?
    @ObservationIgnored private let logger = Logger(subsystem: "io.github.sickpancake.PancakeNotch", category: "shelf")
    @ObservationIgnored let promiseQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.qualityOfService = .userInitiated
        queue.name = "Shelf file promises"
        return queue
    }()

    // MARK: UI state

    enum DropZone: Equatable { case shelf, convert, airDrop }

    /// The Convert zone during a drag: ready, or dimmed with "Can't convert" when the files' kinds are
    /// known and nothing fits. Nil hides it (text and links aren't converted).
    enum ConvertZone: Equatable { case ready, cantConvert }

    enum Prompt: Equatable {
        /// Some dropped content is already on the shelf.
        case duplicates(inputs: [ShelfInput], count: Int)
        /// The shelf is full; `pending` waits for room.
        case full(pending: [ShelfInput])
        /// Picking items to remove to make room for `pending`.
        case choosing(pending: [ShelfInput])
    }

    var selection: Set<UUID> = [] {
        didSet { if selection.count != oldValue.count { onEvent?(.selectionChanged(count: selection.count)) } }
    }
    @ObservationIgnored private var selectionAnchor: UUID?
    /// The far end of a keyboard-extended selection.
    @ObservationIgnored private var selectionCursor: UUID?
    var dropZone: DropZone?
    /// The drag over the notch can be AirDropped (shows the AirDrop zone).
    var dragCanAirDrop = false
    /// The Convert zone for the drag over the notch.
    var convertZone: ConvertZone?
    /// `convertZone` came from the files' names (or there are none to wait for).
    @ObservationIgnored var convertZoneIsFinal = false
    /// The Convert session (ADR-0038): the format row, progress, then the result. Holds the notch open
    /// while it shows.
    var conversion: ShelfConversion?
    /// Runs conversions: the helper in the app, a fake in tests. Nil hides Convert.
    @ObservationIgnored var convertRunner: (any ShelfConvertRunning)? = ShelfConvertHelper.bundled
    /// What the strip under the notch says when a conversion finished out of sight.
    var convertPeekText: String?
    var convertPeekFailed = false
    @ObservationIgnored var convertClickMonitor: Any?
    @ObservationIgnored var convertAppObserver: (any NSObjectProtocol)?
    var prompt: Prompt? {
        didSet {
            // A card (e.g. a late promised file made the Shelf full) shows on the tiles: leave the item view.
            if prompt != nil, detailID != nil { detailID = nil }
            holdChanged(from: oldValue != nil || otherHolds)
            // A late promised file can raise a card after the notch closed: show it.
            if oldValue == nil, prompt != nil, let notch, notch.state != .expanded { notch.open() }
        }
    }

    var isChoosing: Bool {
        if case .choosing = prompt { return true }
        return false
    }
    var confirmingClear = false
    /// The item count before the last drop: the compact ear counts up from it once, then clears it.
    var countBeforeDrop: Int?
    /// The text/link item just copied, for a brief "Copied" flash.
    var copiedID: UUID?
    /// The item shown in the tall notch (text editor, link editor or file preview). Holds the notch open.
    var detailID: UUID? {
        didSet {
            guard detailID != oldValue else { return }
            detailChanged(from: oldValue)
            if oldValue == nil { onEvent?(.detailOpened) } else if detailID == nil { onEvent?(.detailClosed) }
        }
    }
    var detailInfo: ShelfDetailInfo?
    @ObservationIgnored var saveTask: Task<Void, Never>?
    @ObservationIgnored var clickAwayMonitor: Any?
    @ObservationIgnored var appSwitchObserver: (any NSObjectProtocol)?
    @ObservationIgnored private var menu: ShelfMenuPanel?

    /// Rendering off-screen: no scroll view or AppKit overlays, which `ImageRenderer` can't draw.
    @ObservationIgnored var isSnapshot = false
    @ObservationIgnored private var isRefilling = false
    @ObservationIgnored private var isDraggingOut = false
    /// Items are being dragged out of this Shelf right now (a drop target can refuse its own items).
    public var isDraggingOutItems: Bool { isDraggingOut }
    @ObservationIgnored private var isMenuOpen = false
    @ObservationIgnored private var isSharing = false
    @ObservationIgnored private var isQuickLooking = false
    private var otherHolds: Bool { isDraggingOut || isMenuOpen || isSharing || isQuickLooking }

    /// Told about what the user does (opening an item, the menu, dragging out…), for the app
    /// window's lessons. Called from the existing state changes only: nothing is polled.
    @ObservationIgnored public var onEvent: (@MainActor (ShelfEvent) -> Void)?

    /// Whether a drag's source (`NSDraggingInfo.draggingSource`) is a Shelf tile or the
    /// "drag all" handle, so a drop target can refuse the Shelf's own items.
    /// Items may be dragged to places inside the app (the practice Shelf, for the lesson's box).
    @ObservationIgnored var dragsOutWithinApp = false
    /// Converted files stay in the Shelf's own storage instead of beside the original (the practice Shelf).
    @ObservationIgnored var keepsConvertedFiles = false

    public nonisolated static func isOwnDragSource(_ source: Any?) -> Bool {
        source is ShelfTileNSView
    }

    public init(store: ShelfStore, settings: ShelfSettings) {
        self.store = store
        self.settings = settings
        sharing.onFinish = { [weak self] in self?.setHold { $0.isSharing = false } }
        quickLook.onEnd = { [weak self] in self?.setHold { $0.isQuickLooking = false } }
    }

    /// Clears temporary drop files left from an earlier run. Call at launch.
    public static func removeTemporaryFiles() {
        ShelfSharing.removeTemporaryFiles()
    }

    // MARK: NotchModule

    public var moduleID: String { "shelf" }
    public var title: String { String(localized: "Shelf", comment: "Module name") }
    public var symbol: String { "tray" }

    public var menuStatus: String? {
        let count = store.items.count
        if count == 0 { return String(localized: "Empty", comment: "Shelf status in the Module Menu") }
        return count == 1 ? String(localized: "1 item") : String(localized: "\(count) items", comment: "Shelf item count in the notch header")
    }

    /// The Shelf wants an ear while it's nearly full (and the setting is on).
    public var isActive: Bool { showsNearlyFull }

    /// A long tile row (or Convert's format row) scrolls sideways, so a swipe over it mustn't switch modules.
    public func scrollsHorizontally(at point: CGPoint) -> Bool {
        guard let layout = notch?.layout, detailID == nil, dropZone == nil else { return false }
        let shelf = ShelfLayout(layout)
        if visibleConversion != nil { return shelf.content.contains(point) }
        guard prompt == nil else { return false }
        let rowWidth = CGFloat(store.items.count) * (ShelfLayout.tileSize.width + ShelfLayout.tileSpacing)
        return rowWidth > shelf.content.width && shelf.content.contains(point)
    }

    public func attach(to notch: NotchViewModel?) {
        if notch == nil {
            // Switched off: answer any open card (waiting files are discarded) and let go of the notch.
            if prompt != nil { dismissPrompt() }
            menu?.close()
            detailID = nil
            endConversion()
            self.notch?.setTall(false)
            self.notch?.releaseKeyFocus?()
            store.stopObserving(by: self)
            quickLook.closeIfShowing()
        }
        self.notch = notch
        guard notch != nil else { return }
        // Several Shelves can show one store (the real notch and Home's live preview): each listens.
        store.observe(by: self) { [weak self] in self?.storeChanged() }
        updateRestingState()
        observeSettings()
    }

    /// Re-checks the resting state when "Show in the notch" is switched.
    private func observeSettings() {
        withObservationTracking {
            _ = settings.showsInEars
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, self.notch != nil else { return }
                self.updateRestingState()
                self.observeSettings()
            }
        }
    }

    public func expandedView(layout: NotchLayout) -> AnyView {
        AnyView(ShelfView(module: self, layout: ShelfLayout(layout)))
    }

    /// The Shelf's tray with its count, in the ear its ranking gives it (ADR-0011): from 15 items,
    /// after a drop, and in the short shrink after a click while it's the current module.
    public func compactEars(layout: NotchLayout) -> CompactEars? {
        CompactEars(main: AnyView(ShelfEar(module: self)))
    }

    public var holdsOpen: Bool { prompt != nil || detailID != nil || visibleConversion != nil || otherHolds }

    public var accessibilityStatus: String? {
        showsNearlyFull ? Self.earLabel(count: store.items.count) : nil
    }

    /// The Shelf rests in the compact ear: nearly full and the setting is on.
    var showsNearlyFull: Bool {
        settings.showsInEars && store.items.count >= ShelfStore.nearlyFullCount
    }

    static func earLabel(count: Int) -> String {
        if count >= ShelfStore.capacity { return String(localized: "Shelf is full, \(count) items") }
        if count == 0 { return String(localized: "Shelf is empty") }
        return String(localized: "Shelf, \(count) items", comment: "Compact notch; item count")
    }

    public func notchDidOpen() {
        returnToConversion()
        thumbnails.load(store.items.prefix(ShelfThumbnails.firstVisible), scale: 2)
        Task {
            await store.prune(maxAge: settings.autoClear.maxAge)
        }
    }

    public func notchDidClose() {
        menu?.close()
        detailID = nil
        leaveConversion()
        thumbnails.clear()
        selection = []
        confirmingClear = false
        dropZone = nil
        convertZone = nil
        if prompt != nil { dismissPrompt() }
    }

    public func canAcceptDrag(_ pasteboard: NSPasteboard) -> Bool {
        ShelfDropReader.canRead(pasteboard)
    }

    public var keepsDragsBelowMenuBar: Bool { settings.dragToTop == .openShelf }

    /// "✓ Converted Report.pdf" under the notch when a conversion finished while it was closed.
    public func peekView(layout: NotchLayout) -> AnyView? {
        guard let convertPeekText else { return nil }
        return AnyView(ShelfConvertPeek(text: convertPeekText, failed: convertPeekFailed))
    }

    public func dragUpdated(_ info: any NSDraggingInfo, at point: CGPoint) -> NSDragOperation {
        showDropZones(for: info.draggingPasteboard, at: point) ? .copy : []
    }

    /// The notch opened early for a drag: show the drop zones (and AirDrop) straight away.
    public func dragApproaching(_ pasteboard: NSPasteboard, at point: CGPoint) {
        showDropZones(for: pasteboard, at: point)
    }

    /// Shows the Shelf, Convert and AirDrop drop zones, highlighting the one under `point`. Returns
    /// whether the zone under `point` takes the drag.
    @discardableResult
    private func showDropZones(for pasteboard: NSPasteboard, at point: CGPoint) -> Bool {
        guard ShelfDropReader.canRead(pasteboard), let layout = notch?.layout else {
            dropZone = nil
            return false
        }
        if dropZone == nil {
            dragCanAirDrop = settings.showsAirDropZone && ShelfSharing.canAirDrop(pasteboard)
        }
        // The early opening may only know "files" (the Dock's drags): look again once their names show.
        if dropZone == nil || !convertZoneIsFinal {
            let reading = convertZoneReading(pasteboard)
            if convertZone != reading.zone { convertZone = reading.zone }
            convertZoneIsFinal = reading.isFinal
        }
        let shelf = ShelfLayout(layout)
        let zone: DropZone = if dragCanAirDrop, shelf.airDropZone.contains(point) {
            .airDrop
        } else if convertZone != nil, shelf.convertZone(withAirDrop: dragCanAirDrop).contains(point) {
            .convert
        } else {
            .shelf
        }
        if dropZone != zone { dropZone = zone }
        return zone != .convert || convertZone == .ready
    }

    /// Whether the drag's files can be converted, from their names (no disk access mid-drag). Promised
    /// files and picture data aren't known until they arrive: the zone takes them and says after.
    func convertZone(for pasteboard: NSPasteboard) -> ConvertZone? {
        convertZoneReading(pasteboard).zone
    }

    /// The Convert zone for a drag, and whether that's final. Not final: the pasteboard says "files" but
    /// their names can't be read yet (the Dock's drags until they reach the notch's window, where AppKit
    /// hands over the real pasteboard). The zone shows meanwhile; dimming waits for the names.
    private func convertZoneReading(_ pasteboard: NSPasteboard) -> (zone: ConvertZone?, isFinal: Bool) {
        guard canConvert else { return (nil, true) }
        let files = (pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        if !files.isEmpty { return (convertFormats(for: files).isEmpty ? .cantConvert : .ready, true) }
        let types = pasteboard.types ?? []
        if types.contains(.fileURL) { return (.ready, false) }
        let promises = Set(NSFilePromiseReceiver.readableDraggedTypes)
        let comesLater = types.contains { promises.contains($0.rawValue) || $0 == .png || $0 == .tiff }
        return (comesLater ? .ready : nil, true)
    }

    public func performDrop(_ info: any NSDraggingInfo, at point: CGPoint) -> Bool {
        let zone = dropZone ?? .shelf
        let convertible = convertZone == .ready
        dropZone = nil
        convertZone = nil
        let pasteboard = info.draggingPasteboard
        logger.info("Drop types: \(pasteboard.types?.map(\.rawValue) ?? [], privacy: .public)")

        if zone == .convert {
            guard convertible else { return false }
            // Picture data and long text are written to a temporary folder, gone when Convert ends.
            let drop = ShelfDropReader.read(pasteboard) { try ShelfSharing.makeTemporaryFolder() }
            let files = drop.inputs.compactMap { input -> URL? in
                if case .file(let url, _) = input { return url }
                return nil
            }
            guard !files.isEmpty || !drop.promises.isEmpty else { return false }
            closeDetail()
            startConversion(files, promises: drop.promises, temporaryFolders: drop.inputs.compactMap(\.temporaryFolder))
            return true
        }

        if zone == .airDrop {
            let drop = ShelfDropReader.read(pasteboard) { try ShelfSharing.makeTemporaryFolder() }
            guard !drop.isEmpty else { return false }
            setHold { $0.isSharing = true }
            receiveForAirDrop(drop, folders: drop.inputs.compactMap(\.temporaryFolder))
            return true
        }

        let drop = ShelfDropReader.read(pasteboard) { try store.newFilesFolder() }
        guard !drop.isEmpty else { return false }
        // When the notch closes, it shows the new count in the ear for a moment.
        if settings.showsInEars {
            countBeforeDrop = store.items.count
            notch?.closeThroughCompact(for: .seconds(1.5), showing: self)
        }
        // Show the new items on the tiles (and any card about them).
        closeDetail()
        offer(drop.inputs)
        receive(drop.promises)
        return true
    }

    public func dragEnded() {
        dropZone = nil
        convertZone = nil
    }

    /// A click elsewhere in the app window closes an open item in a practice Shelf, the way a click in
    /// another app closes one in the real notch.
    public func clickedOutsidePreview() {
        closeDetail()
        // The format row goes too; a conversion that's running keeps its progress on screen.
        if conversion?.isConverting == false { endConversion() }
    }

    public func handleKey(_ event: NSEvent) -> Bool {
        // An open menu takes every key, like a system menu.
        if let menu, menu.isOpen {
            // ⌘ shortcuts (⌘Q…) still go through.
            return menu.handleKey(event) || !event.modifierFlags.contains(.command)
        }
        if visibleConversion != nil { return handleConvertKey(event) }
        // The tall view: Esc goes back to the tiles (Space too, for a file); other keys belong to the editor.
        if let item = detailItem {
            // The app usually isn't active, so the Edit menu may not see ⌘Z/⌘C/…: pass them to the editor.
            if let action = Self.editAction(for: event) { return NSApp.sendAction(action, to: nil, from: nil) }
            let closes = event.keyCode == 53 || (event.keyCode == 49 && item.isFile)
            if closes { closeDetail() }
            return closes
        }
        let command = event.modifierFlags.contains(.command)
        switch event.keyCode {
        case 49: // Space, like a click: show the item in the tall notch
            guard prompt == nil else { return false }
            if let id = orderedSelection.first ?? store.items.first?.id { openDetail(id) }
            return true
        case 51, 117: // Delete, Forward Delete
            guard prompt == nil else { return false }
            remove(Array(selection))
            return true
        case 36, 76: // Return, Enter: same as Space
            guard prompt == nil else { return false }
            if let id = orderedSelection.first { openDetail(id) }
            return true
        case 123, 124: // ← →: move the selection along the row
            guard prompt == nil || isChoosing else { return false }
            moveSelection(by: event.keyCode == 123 ? -1 : 1, extending: event.modifierFlags.contains(.shift))
            return true
        case 0 where command: // ⌘A
            selection = Set(store.items.map(\.id))
            return true
        case 53: // Escape: answer the open card first, then let the notch close.
            if case .choosing(let pending) = prompt {
                prompt = .full(pending: pending)
                selection = []
                return true
            }
            if prompt != nil {
                dismissPrompt()
                return true
            }
            return false
        default:
            return false
        }
    }

    /// ⌘Z, ⇧⌘Z, ⌘X, ⌘C, ⌘V, ⌘A as the standard edit actions.
    static func editAction(for event: NSEvent) -> Selector? {
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        guard modifiers == .command || modifiers == [.command, .shift] else { return nil }
        let shift = modifiers.contains(.shift)
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "z": return shift ? Selector(("redo:")) : Selector(("undo:"))
        case "x" where !shift: return #selector(NSText.cut(_:))
        case "c" where !shift: return #selector(NSText.copy(_:))
        case "v" where !shift: return #selector(NSText.paste(_:))
        case "a" where !shift: return #selector(NSText.selectAll(_:))
        default: return nil
        }
    }

    // MARK: Holding the notch open

    /// Changes a hold and tells the notch if it was the last one.
    func setHold(_ change: (ShelfModule) -> Void) {
        let before = holdsOpen
        change(self)
        if before && !holdsOpen { notch?.holdReleased() }
    }

    private func holdChanged(from wasHeld: Bool) {
        if wasHeld && !holdsOpen { notch?.holdReleased() }
    }

    func setMenuOpen(_ open: Bool) {
        let changed = isMenuOpen != open
        setHold { $0.isMenuOpen = open }
        if changed { onEvent?(open ? .menuOpened : .menuClosed) }
    }

    /// Shows the Shelf's own pop-up menu at the pointer; it holds the notch open while it's up.
    func showMenu(_ entries: [ShelfMenuEntry]) {
        menu?.close()
        guard !entries.isEmpty else { return }
        setMenuOpen(true)
        menu = ShelfMenuPanel(entries: entries, at: NSEvent.mouseLocation) { [weak self] in
            self?.menu = nil
            self?.setMenuOpen(false)
        }
    }
    func setDraggingOut(_ dragging: Bool) { setHold { $0.isDraggingOut = dragging } }

    /// Takes keyboard focus after a click, so Space, Delete and ⌘A work.
    func requestFocus() {
        notch?.requestKeyFocus?()
    }

    // MARK: Adding

    /// Offers dropped content to the store, asking about duplicates or holding what doesn't fit.
    func offer(_ inputs: [ShelfInput]) {
        guard !inputs.isEmpty else { return }
        switch prompt {
        case .duplicates(let waiting, _):
            let all = waiting + inputs
            prompt = .duplicates(inputs: all, count: all.filter(store.contains).count)
        case .full(let pending):
            prompt = .full(pending: pending + waitingInputs(inputs, after: pending))
        case .choosing(let pending):
            prompt = .choosing(pending: pending + waitingInputs(inputs, after: pending))
        case nil:
            apply(store.add(inputs, duplicates: settings.duplicatePolicy), inputs: inputs)
        }
    }

    /// Content dropped while the shelf is full joins the waiting items. Unless duplicates are always
    /// added again, anything already on the shelf or already waiting is left out (it's there already).
    private func waitingInputs(_ inputs: [ShelfInput], after pending: [ShelfInput]) -> [ShelfInput] {
        guard settings.duplicatePolicy != .addAgain else { return inputs }
        let waiting = Set(pending.map(\.key))
        let fresh = inputs.filter { !store.contains($0) && !waiting.contains($0.key) }
        store.discard(inputs.filter { input in !fresh.contains(input) })
        return fresh
    }

    private func apply(_ result: ShelfStore.AddResult, inputs: [ShelfInput]) {
        switch result {
        case .done:
            prompt = nil
        case .duplicates(let count):
            prompt = .duplicates(inputs: inputs, count: count)
        case .overflow(_, let pending):
            prompt = .full(pending: pending)
        }
    }

    /// The duplicate card was answered.
    func answerDuplicates(_ policy: ShelfSettings.DuplicatePolicy, remember: Bool) {
        guard case .duplicates(let inputs, _) = prompt else { return }
        if remember { settings.duplicatePolicy = policy }
        apply(store.add(inputs, duplicates: policy), inputs: inputs)
    }

    /// Closing a card: duplicates are skipped (they're already there), held items are discarded.
    func dismissPrompt() {
        switch prompt {
        case .duplicates(let inputs, _):
            apply(store.add(inputs.filter { !store.contains($0) }, duplicates: .addAgain), inputs: inputs)
            if case .full(let pending) = prompt {
                store.discard(pending)
                prompt = nil
            }
        case .full(let pending), .choosing(let pending):
            store.discard(pending)
            prompt = nil
        case nil:
            break
        }
    }

    func startChoosing() {
        guard case .full(let pending) = prompt else { return }
        selection = []
        prompt = .choosing(pending: pending)
    }

    func removeChosen() {
        let chosen = selection
        selection = []
        store.remove(chosen)
    }

    /// The full card's Clear all: asks first, like the header's, since it removes everything.
    func clearForPending() {
        guard confirmingClear else {
            confirmingClear = true
            return
        }
        confirmingClear = false
        selection = []
        store.clear()
        onEvent?(.cleared)
    }

    /// Room was made while items were waiting: add as many as now fit.
    private func refill() {
        // Adding changes the store, which calls back into here: don't add the same items twice.
        guard !isRefilling else { return }
        let pending: [ShelfInput]
        switch prompt {
        case .full(let waiting), .choosing(let waiting): pending = waiting
        default: return
        }
        guard !store.isFull else { return }
        isRefilling = true
        defer { isRefilling = false }
        switch store.add(pending, duplicates: .addAgain) {
        case .overflow(_, let rest):
            prompt = isChoosing ? .choosing(pending: rest) : .full(pending: rest)
        default:
            prompt = nil
        }
    }

    /// Promised files arrive later on a background queue; each is moved into its own folder and offered.
    private func receive(_ promises: [NSFilePromiseReceiver]) {
        guard !promises.isEmpty else { return }
        // Each into its own temporary folder first. They stay (empty) until the next launch clears
        // them: a promise can deliver several files, and deleting the folder once it looked empty
        // could pull it from under a slower app still writing one.
        for promise in promises {
            guard let destination = try? ShelfSharing.makeTemporaryFolder() else { return }
            logger.info("Receiving promised file \(promise.fileNames, privacy: .private)")
            ShelfDropReader.receive(promise, into: destination, queue: promiseQueue) { [weak self] url in
                Task { @MainActor in self?.promisedFileArrived(url) }
            }
        }
    }

    private func promisedFileArrived(_ url: URL?) {
        guard let url else {
            logger.error("A promised file didn't arrive")
            return
        }
        do {
            let target = try store.newFilesFolder().appending(path: url.lastPathComponent)
            try FileManager.default.moveItem(at: url, to: target)
            logger.info("Promised file arrived")
            offer([.file(target, owned: true)])
        } catch {
            logger.error("Couldn't keep a promised file: \(error.localizedDescription, privacy: .private)")
        }
    }

    /// Content dropped on the AirDrop zone; promised files are received first, then everything is sent at once.
    private func receiveForAirDrop(_ drop: ShelfDrop, folders: [URL]) {
        sharing.deleteWhenFinished(folders)
        let batch = AirDropBatch(items: drop.inputs.map(\.shareable), waiting: 0)
        onEvent?(.airDropped(count: drop.inputs.count + drop.promises.count))
        guard !drop.promises.isEmpty, let destination = try? ShelfSharing.makeTemporaryFolder() else {
            sharing.airDrop(batch.items)
            return
        }
        sharing.deleteWhenFinished([destination])
        for promise in drop.promises {
            ShelfDropReader.receive(promise, into: destination, queue: promiseQueue) { [weak self] url in
                Task { @MainActor in
                    if let url { batch.items.append(url) }
                    batch.waiting -= 1
                    if batch.waiting == 0 { self?.sharing.airDrop(batch.items) }
                }
            }
        }
        // File names are known only once receiving has started; arrivals run on a later main-actor turn.
        batch.waiting = ShelfDropReader.expectedFileCount(drop.promises)
    }

    // MARK: Store changes

    private func storeChanged() {
        let ids = Set(store.items.map(\.id))
        selection.formIntersection(ids)
        if let detailID, !ids.contains(detailID) { setHold { $0.detailID = nil } }
        thumbnails.keepOnly(ids)
        if notch?.state == .expanded { thumbnails.load(store.items.prefix(ShelfThumbnails.firstVisible), scale: 2) }
        if store.items.isEmpty { confirmingClear = false }
        refill()
        updateRestingState()
        onEvent?(.itemsChanged(count: store.items.count))
    }

    /// The notch rests in Compact, with the Shelf in its ear, from 15 items; invisible otherwise.
    /// Nearly full or not: the notch rests in Compact while any module is active.
    private func updateRestingState() {
        notch?.activityChanged()
    }

    // MARK: Selection

    var orderedSelection: [UUID] {
        store.items.map(\.id).filter(selection.contains)
    }

    /// A click on a tile: plain click selects it, ⌘ toggles, ⇧ extends; while choosing, every click toggles.
    func click(_ id: UUID, modifiers: NSEvent.ModifierFlags) {
        confirmingClear = false
        if case .choosing = prompt {
            selection.formSymmetricDifference([id])
            return
        }
        if modifiers.contains(.command) {
            selection.formSymmetricDifference([id])
            selectionAnchor = id
        } else if modifiers.contains(.shift), let anchor = selectionAnchor,
                  let from = store.items.firstIndex(where: { $0.id == anchor }),
                  let to = store.items.firstIndex(where: { $0.id == id }) {
            selection = Set(store.items[min(from, to)...max(from, to)].map(\.id))
        } else {
            selection = [id]
            selectionAnchor = id
        }
        selectionCursor = id
    }

    /// Arrow keys: select the neighbouring item (⇧ extends the selection).
    func moveSelection(by step: Int, extending: Bool) {
        let ids = store.items.map(\.id)
        guard !ids.isEmpty else { return }
        let current = (selectionCursor ?? selectionAnchor).flatMap { ids.firstIndex(of: $0) }
        let next = current.map { min(max($0 + step, 0), ids.count - 1) } ?? (step > 0 ? 0 : ids.count - 1)
        selectionCursor = ids[next]
        if isChoosing {
            return // While choosing, a click (or VoiceOver's default action) toggles; arrows don't.
        }
        if extending, let anchor = selectionAnchor.flatMap({ ids.firstIndex(of: $0) }) {
            selection = Set(ids[min(anchor, next)...max(anchor, next)])
        } else {
            selection = [ids[next]]
            selectionAnchor = ids[next]
        }
    }

    /// A click on empty space: clears the selection (or the "Clear all?" question) if there is one,
    /// otherwise shrinks the notch to Compact like a click on any open panel (ADR-0011).
    func backgroundClicked() {
        if case .choosing = prompt { return }
        guard selection.isEmpty, !confirmingClear else {
            confirmingClear = false
            selection = []
            return
        }
        notch?.tap()
    }

    /// The items an action on `id` applies to: the whole selection if `id` is part of it.
    func targets(for id: UUID?) -> [ShelfItem] {
        guard let id else { return store.items }
        let ids = selection.contains(id) ? selection : [id]
        return store.items.filter { ids.contains($0.id) }
    }

    // MARK: Actions

    /// VoiceOver's default action: toggle while choosing, otherwise show the item in the tall notch.
    func activate(_ id: UUID) {
        if case .choosing = prompt {
            click(id, modifiers: [])
            return
        }
        openDetail(id)
    }

    func open(_ items: [ShelfItem]) {
        for item in items {
            switch item.kind {
            case .file:
                if let url = store.resolvedURL(for: item) { NSWorkspace.shared.open(url) }
            case .link(let url):
                NSWorkspace.shared.open(url)
            case .text:
                copy([item])
            }
        }
    }

    func copy(_ items: [ShelfItem]) {
        let objects = items.map { item -> any NSPasteboardWriting in
            switch item.kind {
            case .text(let text): text as NSString
            case .link(let url): url as NSURL
            case .file: (store.resolvedURL(for: item) ?? item.fileURL ?? URL(fileURLWithPath: "/")) as NSURL
            }
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects(objects)
        AccessibilityNotification.Announcement(String(localized: "Copied")).post()
        if items.count == 1, let id = items.first?.id {
            copiedID = id
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(1.2))
                if self?.copiedID == id { self?.copiedID = nil }
            }
        }
    }

    func copyPaths(_ items: [ShelfItem]) {
        let paths = items.compactMap { store.resolvedURL(for: $0)?.path }
        guard !paths.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(paths.joined(separator: "\n"), forType: .string)
    }

    func reveal(_ items: [ShelfItem]) {
        let urls = items.compactMap(store.resolvedURL(for:))
        if !urls.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(urls) }
    }

    func remove(_ ids: [UUID]) {
        store.remove(ids)
    }

    func clearAll() {
        if confirmingClear {
            confirmingClear = false
            store.clear()
            onEvent?(.cleared)
        } else {
            confirmingClear = true
        }
    }

    func quickLook(_ items: [ShelfItem]) {
        let urls = items.compactMap(store.resolvedURL(for:))
        guard !urls.isEmpty else { return }
        setHold { $0.isQuickLooking = true }
        quickLook.show(urls)
    }

    func airDrop(_ items: [ShelfItem]) {
        setHold { $0.isSharing = true }
        sharing.airDrop(shareables(items))
        onEvent?(.airDropped(count: items.count))
    }

    func share(_ items: [ShelfItem], from view: NSView) {
        setHold { $0.isSharing = true }
        sharing.share(shareables(items), from: view)
    }

    private func shareables(_ items: [ShelfItem]) -> [Any] {
        items.compactMap { item -> Any? in
            switch item.kind {
            case .file: store.resolvedURL(for: item)
            case .text(let text): text
            case .link(let url): url
            }
        }
    }

    // MARK: Dragging out

    /// What a drag starting on `id` carries (the whole selection if `id` is selected; everything for `nil`).
    func dragPayload(for id: UUID?) -> [(item: ShelfItem, writer: any NSPasteboardWriting)] {
        targets(for: id).compactMap { item in
            switch item.kind {
            case .file:
                // Where the file is now (a quick bookmark lookup), not where it was when the notch opened:
                // a moved file must never drag whatever took its old place, and a deleted one drags nothing.
                guard let url = store.resolvedURL(for: item) else { return nil }
                return (item, url as NSURL)
            case .text(let text):
                return (item, text as NSString)
            case .link(let url):
                return (item, url as NSURL)
            }
        }
    }

    /// Outside our app: copy only, unless the user chose Finder-like moves. Inside our app only the
    /// practice Shelf's items go out (to the lesson's box), as copies; the notches refuse them.
    func dragOperations(outside: Bool) -> NSDragOperation {
        guard outside else { return dragsOutWithinApp ? .copy : [] }
        return settings.dragOutMode == .move ? [.copy, .move, .generic] : .copy
    }

    func dragOutEnded(_ ids: [UUID], operation: NSDragOperation) {
        if settings.removeAfterDragOut, !operation.isEmpty {
            // The other app may still be copying (or moving) the file: its folder goes at next launch.
            store.remove(ids, keepingFiles: true)
        }
        setDraggingOut(false)
        notch?.dragOutEnded()
        onEvent?(.dragOutEnded(accepted: !operation.isEmpty))
    }
}

/// Collects an AirDrop zone drop while its promised files arrive.
@MainActor
private final class AirDropBatch {
    var items: [Any]
    var waiting: Int

    init(items: [Any], waiting: Int) {
        self.items = items
        self.waiting = waiting
    }
}

extension ShelfStore {
    /// Whether this content is already on the shelf.
    func contains(_ input: ShelfInput) -> Bool {
        items.contains { $0.key == input.key }
    }
}

extension ShelfInput {
    /// The temporary folder of a file read from the AirDrop zone (deleted after sending).
    var temporaryFolder: URL? {
        guard case .file(let url, true) = self else { return nil }
        return url.deletingLastPathComponent()
    }

    /// The value handed to AirDrop/Share.
    var shareable: Any {
        switch self {
        case .file(let url, _): url
        case .text(let text): text
        case .link(let url): url
        }
    }
}
