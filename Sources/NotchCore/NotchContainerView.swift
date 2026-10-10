import AppKit

/// Window content that keeps the notch view at a fixed size, pinned to the top center.
///
/// The window shrinks and grows with the notch so it never blocks clicks, but SwiftUI must not see
/// those resizes: it would animate the notch from where it sat in the old window (the left edge of
/// the new one) to the center. The hosted view stays at its largest size and the window clips it.
///
/// It's also the notch's only drop target: drags are handled here in AppKit (file promises need
/// `NSDraggingInfo`), so nothing in the SwiftUI tree may use `.onDrop` or `.dropDestination`,
/// or the hosting view would claim the drag first.
final class NotchContainerView: NSView {
    let content: NSView

    /// Size of the hosted view: the largest window the notch ever needs.
    var contentSize: CGSize {
        didSet { needsLayout = true }
    }

    /// Receives drags from other apps. Set by `NotchWindowController`.
    weak var dropDelegate: NotchDropDelegate?

    init(content: NSView, contentSize: CGSize) {
        self.content = content
        self.contentSize = contentSize
        super.init(frame: CGRect(origin: .zero, size: contentSize))
        content.autoresizingMask = []
        addSubview(content)
        registerForDraggedTypes(Self.draggedTypes)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Files, promised files (Photos, Mail, Safari images), images, links and text.
    static var draggedTypes: [NSPasteboard.PasteboardType] {
        [.fileURL, .URL, .string, .png, .tiff]
            + NSFilePromiseReceiver.readableDraggedTypes.map(NSPasteboard.PasteboardType.init(rawValue:))
    }

    override func layout() {
        super.layout()
        content.frame = Self.contentFrame(in: bounds, contentSize: contentSize)
    }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        content.frame = Self.contentFrame(in: bounds, contentSize: contentSize)
    }

    /// Centered horizontally, flush with the top edge (AppKit's y axis points up).
    nonisolated static func contentFrame(in bounds: CGRect, contentSize: CGSize) -> CGRect {
        CGRect(
            x: bounds.midX - contentSize.width / 2,
            y: bounds.maxY - contentSize.height,
            width: contentSize.width,
            height: contentSize.height
        )
    }

    /// A drag location in the hosted content's coordinates: origin top-left, y down.
    private func contentPoint(_ info: any NSDraggingInfo) -> CGPoint {
        let point = convert(info.draggingLocation, from: nil)
        return CGPoint(x: point.x - content.frame.minX, y: content.frame.maxY - point.y)
    }

    // MARK: NSDraggingDestination

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        dropDelegate?.dragEntered(sender, at: contentPoint(sender)) ?? []
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        dropDelegate?.dragUpdated(sender, at: contentPoint(sender)) ?? []
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        dropDelegate?.dragExited()
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        dropDelegate?.performDrop(sender, at: contentPoint(sender)) ?? false
    }

    override func draggingEnded(_ sender: any NSDraggingInfo) {
        dropDelegate?.dragConcluded()
    }
}

/// Receives the drags that reach the notch window.
@MainActor
protocol NotchDropDelegate: AnyObject {
    func dragEntered(_ info: any NSDraggingInfo, at contentPoint: CGPoint) -> NSDragOperation
    func dragUpdated(_ info: any NSDraggingInfo, at contentPoint: CGPoint) -> NSDragOperation
    func dragExited()
    func performDrop(_ info: any NSDraggingInfo, at contentPoint: CGPoint) -> Bool
    func dragConcluded()
}
