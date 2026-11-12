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
                HStack {
                    Label(module.title, systemImage: "tray")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                    Spacer(minLength: 0)
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

    var body: some View {
        Group {
            if let url = item.fileURL {
                Image(nsImage: ShelfThumbnails.smallIcon(forFile: url.path))
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
        .frame(width: 26, height: 26)
        .help(Text(item.displayName))
        .accessibilityLabel(Text(item.displayName))
    }

    private static func symbol(_ item: ShelfItem) -> String {
        if case .link = item.kind { return "link" }
        return "text.alignleft"
    }
}
