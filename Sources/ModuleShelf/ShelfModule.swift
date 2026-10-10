import AppKit
import NotchCore
import Observation
import os
import SwiftUI

/// The Shelf: a drop zone in the notch for files, images, text and links (ADR-0013).
@MainActor
@Observable
public final class ShelfModule: NotchModule {
    public let store: ShelfStore
    public let settings: ShelfSettings
    let thumbnails = ShelfThumbnails()
    @ObservationIgnored let sharing = ShelfSharing()
    @ObservationIgnored let quickLook = ShelfQuickLook()

    @ObservationIgnored private(set) weak var notch: NotchViewModel?
    @ObservationIgnored private let logger = Logger(subsystem: "io.github.sickpancake.PancakeNotch", category: "shelf")
    @ObservationIgnored private let promiseQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.qualityOfService = .userInitiated
        queue.name = "Shelf file promises"
        return queue
    }()

    // MARK: UI state

    enum DropZone: Equatable { case shelf, airDrop }

    enum Prompt: Equatable {
        /// Some dropped content is already on the shelf.
        case duplicates(inputs: [ShelfInput], count: Int)
        /// The shelf is full; `pending` waits for room.
        case full(pending: [ShelfInput])
        /// Picking items to remove to make room for `pending`.
        case choosing(pending: [ShelfInput])
    }

    var selection: Set<UUID> = []
    @ObservationIgnored private var selectionAnchor: UUID?
    var dropZone: DropZone?
    /// The drag over the notch can be AirDropped (shows the AirDrop zone).
    var dragCanAirDrop = false
    var prompt: Prompt? { didSet { holdChanged(from: oldValue != nil || otherHolds) } }
    var confirmingClear = false
    /// The text/link item just copied, for a brief "Copied" flash.
    var copiedID: UUID?

    /// Rendering off-screen: no scroll view or AppKit overlays, which `ImageRenderer` can't draw.
    @ObservationIgnored var isSnapshot = false
    @ObservationIgnored private var isRefilling = false
    @ObservationIgnored private var isDraggingOut = false
    @ObservationIgnored private var isMenuOpen = false
    @ObservationIgnored private var isSharing = false
    @ObservationIgnored private var isQuickLooking = false
    private var otherHolds: Bool { isDraggingOut || isMenuOpen || isSharing || isQuickLooking }

    public init(store: ShelfStore, settings: ShelfSettings) {
        self.store = store
        self.settings = settings
        sharing.onFinish = { [weak self] in self?.setHold { $0.isSharing = false } }
        quickLook.onEnd = { [weak self] in self?.setHold { $0.isQuickLooking = false } }
    }

    // MARK: NotchModule

    public func attach(to notch: NotchViewModel?) {
        if notch == nil {
            self.notch?.restingState = .closed
            store.onChange = nil
        }
        self.notch = notch
        guard notch != nil else { return }
        store.onChange = { [weak self] in self?.storeChanged() }
        updateRestingState()
    }

    public func expandedView(layout: NotchLayout) -> AnyView {
        AnyView(ShelfView(module: self, layout: ShelfLayout(layout)))
    }

    public func compactView(layout: NotchLayout) -> AnyView? {
        store.isFull ? AnyView(ShelfFullEars(layout: layout)) : nil
    }

    public var holdsOpen: Bool { prompt != nil || otherHolds }

    public func notchDidOpen() {
        thumbnails.load(store.items, scale: 2)
        Task {
            await store.prune(maxAge: settings.autoClear.maxAge)
        }
    }

    public func notchDidClose() {
        thumbnails.clear()
        selection = []
        confirmingClear = false
        dropZone = nil
        if prompt != nil { dismissPrompt() }
    }

    public func dragUpdated(_ info: any NSDraggingInfo, at point: CGPoint) -> NSDragOperation {
        let pasteboard = info.draggingPasteboard
        guard ShelfDropReader.canRead(pasteboard), let layout = notch?.layout else {
            dropZone = nil
            return []
        }
        if dropZone == nil {
            dragCanAirDrop = settings.showsAirDropZone && ShelfSharing.canAirDrop(pasteboard)
        }
        let zone: DropZone = dragCanAirDrop && ShelfLayout(layout).airDropZone.contains(point) ? .airDrop : .shelf
        if dropZone != zone { dropZone = zone }
        return .copy
    }

    public func performDrop(_ info: any NSDraggingInfo, at point: CGPoint) -> Bool {
        let zone = dropZone ?? .shelf
        dropZone = nil
        let pasteboard = info.draggingPasteboard
        logger.info("Drop types: \(pasteboard.types?.map(\.rawValue) ?? [], privacy: .public)")

        if zone == .airDrop {
            let drop = ShelfDropReader.read(pasteboard) { try ShelfSharing.makeTemporaryFolder() }
            guard !drop.isEmpty else { return false }
            setHold { $0.isSharing = true }
            receiveForAirDrop(drop)
            return true
        }

        let drop = ShelfDropReader.read(pasteboard) { try store.newFilesFolder() }
        guard !drop.isEmpty else { return false }
        offer(drop.inputs)
        receive(drop.promises)
        return true
    }

    public func dragEnded() {
        dropZone = nil
    }

    public func handleKey(_ event: NSEvent) -> Bool {
        let command = event.modifierFlags.contains(.command)
        switch event.keyCode {
        case 49: // Space
            quickLookSelection()
            return true
        case 51, 117: // Delete, Forward Delete
            guard prompt == nil else { return false }
            remove(Array(selection))
            return true
        case 36, 76: // Return, Enter
            for id in orderedSelection { activate(id) }
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

    func setMenuOpen(_ open: Bool) { setHold { $0.isMenuOpen = open } }
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
            prompt = .full(pending: pending + inputs)
        case .choosing(let pending):
            prompt = .choosing(pending: pending + inputs)
        case nil:
            apply(store.add(inputs, duplicates: settings.duplicatePolicy), inputs: inputs)
        }
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

    func clearForPending() {
        selection = []
        store.clear()
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
            prompt = .full(pending: rest)
        default:
            prompt = nil
        }
    }

    /// Promised files arrive later on a background queue; each is moved into its own folder and offered.
    private func receive(_ promises: [NSFilePromiseReceiver]) {
        guard !promises.isEmpty else { return }
        // Received into a temporary folder first: all promises of one drop share a destination.
        guard let destination = try? ShelfSharing.makeTemporaryFolder() else { return }
        for promise in promises {
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
            logger.error("Couldn't keep a promised file: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Content dropped on the AirDrop zone; promised files are received first, then everything is sent at once.
    private func receiveForAirDrop(_ drop: ShelfDrop) {
        let batch = AirDropBatch(items: drop.inputs.map(\.shareable), waiting: ShelfDropReader.expectedFileCount(drop.promises))
        guard batch.waiting > 0, let destination = try? ShelfSharing.makeTemporaryFolder() else {
            sharing.airDrop(batch.items)
            return
        }
        for promise in drop.promises {
            ShelfDropReader.receive(promise, into: destination, queue: promiseQueue) { [weak self] url in
                Task { @MainActor in
                    if let url { batch.items.append(url) }
                    batch.waiting -= 1
                    if batch.waiting == 0 { self?.sharing.airDrop(batch.items) }
                }
            }
        }
    }

    // MARK: Store changes

    private func storeChanged() {
        let ids = Set(store.items.map(\.id))
        selection.formIntersection(ids)
        thumbnails.keepOnly(ids)
        if notch?.state == .expanded { thumbnails.load(store.items, scale: 2) }
        if store.items.isEmpty { confirmingClear = false }
        refill()
        updateRestingState()
    }

    /// The notch rests with small "Full" ears while the shelf is full, invisible otherwise.
    private func updateRestingState() {
        let resting: NotchState = store.isFull ? .compact : .closed
        if notch?.restingState != resting { notch?.restingState = resting }
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
    }

    func backgroundClicked() {
        confirmingClear = false
        if case .choosing = prompt { return }
        selection = []
    }

    /// The items an action on `id` applies to: the whole selection if `id` is part of it.
    func targets(for id: UUID?) -> [ShelfItem] {
        guard let id else { return store.items }
        let ids = selection.contains(id) ? selection : [id]
        return store.items.filter { ids.contains($0.id) }
    }

    // MARK: Actions

    /// Double-click or Return: open a file, copy a text or link item.
    func activate(_ id: UUID) {
        guard let item = store.items.first(where: { $0.id == id }) else { return }
        if item.isFile {
            open([item])
        } else {
            copy([item])
        }
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
        } else {
            confirmingClear = true
        }
    }

    func quickLookSelection() {
        let items = store.items.filter { selection.contains($0.id) && $0.isFile }
        quickLook(items.isEmpty ? Array(store.items.filter(\.isFile).prefix(1)) : items)
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
                guard let url = store.resolvedURL(for: item) else { return nil }
                return (item, url as NSURL)
            case .text(let text):
                return (item, text as NSString)
            case .link(let url):
                return (item, url as NSURL)
            }
        }
    }

    /// Outside our app: copy only, unless the user chose Finder-like moves. Never inside our app.
    func dragOperations(outside: Bool) -> NSDragOperation {
        guard outside else { return [] }
        return settings.dragOutMode == .move ? [.copy, .move, .generic] : .copy
    }

    func dragOutEnded(_ ids: [UUID], operation: NSDragOperation) {
        if settings.removeAfterDragOut, !operation.isEmpty {
            store.remove(ids)
        }
        setDraggingOut(false)
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
    /// The value handed to AirDrop/Share.
    var shareable: Any {
        switch self {
        case .file(let url, _): url
        case .text(let text): text
        case .link(let url): url
        }
    }
}
