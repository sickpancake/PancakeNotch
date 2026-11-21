import AppKit
import NotchCore
import SwiftUI

extension ShelfModule {
    /// The Shelf on Home (ADR-0042). Files dropped on the notch still go to the Shelf as before: drops are
    /// handled by the notch window, never by this widget.
    public func homeWidget(_ kind: HomeWidgetKind, size: HomeWidgetSize, context: HomeWidgetContext) -> AnyView? {
        guard kind == .shelf else { return nil }
        return AnyView(ShelfWidget(module: self, size: size))
    }
}

/// Small: how many items. Medium: the first few as icons. Large: a grid of them. Empty: "Drop files here".
struct ShelfWidget: View {
    let module: ShelfModule
    let size: HomeWidgetSize

    var body: some View {
        let items = module.store.items
        switch size {
        case .small:
            HomeWidgetTile(symbol: "tray", title: module.title,
                           line: items.isEmpty ? String(localized: "Drop files here") : module.menuStatus)
        case .medium, .large:
            VStack(alignment: .leading, spacing: 6) {
                HomeWidgetHeader(symbol: "tray", title: module.title) {
                    if !items.isEmpty, let status = module.menuStatus {
                        Text(status)
                            .font(.system(size: 10, weight: .medium).monospacedDigit())
                            .foregroundStyle(.white.opacity(0.55))
                            .contentTransition(.numericText(value: Double(items.count)))
                    }
                }
                if items.isEmpty {
                    Text("Drop files here")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .strokeBorder(.white.opacity(0.14), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        }
                } else {
                    let columns = 5
                    let shown = Array(items.prefix(size == .medium ? columns : columns * 2))
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: columns), alignment: .leading, spacing: 4) {
                        ForEach(shown) { item in
                            ShelfWidgetIcon(item: item)
                                .transition(.opacity)
                        }
                    }
                    .animation(.easeInOut(duration: 0.2), value: shown.map(\.id))
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .animation(.easeInOut(duration: 0.2), value: items.isEmpty)
        }
    }
}

/// A file's Finder icon, or a symbol for text and links.
private struct ShelfWidgetIcon: View {
    let item: ShelfItem
    @Environment(\.displayScale) private var displayScale
    @State private var presentation = ShelfWidgetFilePresentation()

    var body: some View {
        let file = presentation.file(for: item, scale: displayScale)
        let name = file?.name ?? item.displayName
        Group {
            if let file {
                Image(nsImage: file.icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: Self.symbol(item))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.white.opacity(0.08), in: .rect(cornerRadius: 6, style: .continuous))
            }
        }
        .frame(width: ShelfWidgetFilePresentation.side, height: ShelfWidgetFilePresentation.side)
        .help(Text(name))
        .accessibilityLabel(Text(name))
    }

    private static func symbol(_ item: ShelfItem) -> String {
        if case .link = item.kind { return "link" }
        return "text.alignleft"
    }
}

/// One file icon per mounted tile. SwiftUI releases it with the tile's state.
@MainActor
final class ShelfWidgetFilePresentation {
    static let side: CGFloat = 26

    private struct Key: Equatable {
        let path: String
        let identifier: NSObject?
        let modified: Date?
        let attributesModified: Date?
        let scale: CGFloat
    }

    private var cached: (key: Key, name: String, icon: NSImage)?

    func file(for item: ShelfItem, scale: CGFloat) -> (name: String, icon: NSImage)? {
        guard let url = item.fileURL else {
            cached = nil
            return nil
        }
        let values = try? url.resourceValues(forKeys: [
            .fileResourceIdentifierKey, .contentModificationDateKey, .attributeModificationDateKey,
        ])
        let key = Key(path: url.path, identifier: values?.fileResourceIdentifier as? NSObject,
                      modified: values?.contentModificationDate, attributesModified: values?.attributeModificationDate,
                      scale: scale)
        if let cached, cached.key == key { return (cached.name, cached.icon) }
        let name = item.displayName
        let icon = Self.icon(path: key.path, scale: scale)
        cached = (key, name, icon)
        return (name, icon)
    }

    private static func icon(path: String, scale: CGFloat) -> NSImage {
        let points = CGSize(width: side, height: side)
        let pixels = max(1, Int((side * scale).rounded(.up)))
        let icon = NSWorkspace.shared.icon(forFile: path)
        let bounds = CGRect(x: 0, y: 0, width: pixels, height: pixels)
        var proposed = bounds
        guard let source = icon.cgImage(forProposedRect: &proposed, context: nil, hints: nil) else {
            return NSImage(size: points)
        }
        // Finder can supply a larger representation than requested.
        guard source.width > pixels || source.height > pixels,
              let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return NSImage(cgImage: source, size: points) }
        context.interpolationQuality = .high
        context.draw(source, in: bounds)
        return NSImage(cgImage: context.makeImage() ?? source, size: points)
    }
}
