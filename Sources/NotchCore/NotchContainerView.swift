import AppKit

/// Window content that keeps the notch view at a fixed size, pinned to the top center.
///
/// The window shrinks and grows with the notch so it never blocks clicks, but SwiftUI must not see
/// those resizes: it would animate the notch from where it sat in the old window (the left edge of
/// the new one) to the center. The hosted view stays at its largest size and the window clips it.
final class NotchContainerView: NSView {
    let content: NSView

    /// Size of the hosted view: the largest window the notch ever needs.
    var contentSize: CGSize {
        didSet { needsLayout = true }
    }

    init(content: NSView, contentSize: CGSize) {
        self.content = content
        self.contentSize = contentSize
        super.init(frame: CGRect(origin: .zero, size: contentSize))
        content.autoresizingMask = []
        addSubview(content)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

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
}
