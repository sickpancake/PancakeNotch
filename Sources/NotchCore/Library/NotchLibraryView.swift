import SwiftUI

/// Sizes for the Library page, from the notch's layout (never per Mac model).
enum LibraryMetrics {
    /// The left column: the search and Recently used.
    static let sidebarWidth: CGFloat = 160
    /// Space either side of the hairline between the two columns.
    static let dividerMargin: CGFloat = 14
    static let gap: CGFloat = 8
    static let minTileWidth: CGFloat = 80
    static let minTileHeight: CGFloat = 54
    static let cornerRadius: CGFloat = 10

    /// The tiles' side of the page.
    static func gridSize(in layout: NotchLayout) -> CGSize {
        let area = HomeWidgetMetrics.gridArea(in: layout)
        return CGSize(width: max(0, area.width - sidebarWidth - 2 * dividerMargin - 1), height: area.height)
    }

    /// How many tiles fit across.
    static func columns(in layout: NotchLayout) -> Int {
        max(1, Int((gridSize(in: layout).width + gap) / (minTileWidth + gap)))
    }

    /// Two rows fill the page; more scroll.
    static func tileSize(in layout: NotchLayout) -> CGSize {
        let grid = gridSize(in: layout)
        let columns = CGFloat(columns(in: layout))
        return CGSize(width: max(0, floor((grid.width - (columns - 1) * gap) / columns)),
                      height: max(minTileHeight, floor((grid.height - gap) / 2)))
    }
}

/// The Library in the open notch (ADR-0045): the search and Recently used on the left, a tile for every
/// module on the right, in ranking order. A click opens a module (it grows out of its tile), the star adds
/// or removes a favorite, a right-click has the module's menu. The bar sits in the band, drawn by NotchView.
struct NotchLibraryView: View {
    let model: NotchViewModel
    let layout: NotchLayout

    /// The panel's own coordinates, so a tile can say where it sits for the module growing out of it.
    nonisolated static let space = "NotchLibrary"

    var body: some View {
        let size = layout.bodySize(for: .expanded)
        let notch = layout.geometry.notchRect.size
        let area = HomeWidgetMetrics.gridArea(in: layout)
        let grid = LibraryMetrics.gridSize(in: layout)
        VStack(spacing: 0) {
            band(size: size, notch: notch)
            HStack(alignment: .top, spacing: 0) {
                LibrarySidebar(model: model)
                    .frame(width: LibraryMetrics.sidebarWidth, height: area.height, alignment: .topLeading)
                Rectangle()
                    .fill(.white.opacity(0.1))
                    .frame(width: 1, height: area.height)
                    .padding(.horizontal, LibraryMetrics.dividerMargin)
                    .accessibilityHidden(true)
                LibraryGrid(model: model, size: grid, tile: LibraryMetrics.tileSize(in: layout),
                            columns: LibraryMetrics.columns(in: layout), panel: size)
                    .frame(width: grid.width, height: grid.height, alignment: .topLeading)
            }
            .frame(width: area.width, height: area.height, alignment: .topLeading)
            .padding(.top, HomeWidgetMetrics.topPadding)
            .frame(width: size.width, height: size.height - notch.height, alignment: .top)
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .coordinateSpace(.named(Self.space))
        .foregroundStyle(.white)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Library"))
    }

    /// Beside the camera: the bar on the left (drawn by NotchView); Edit (the Modules page) and the gear on
    /// the right, as on Home.
    private func band(size: CGSize, notch: CGSize) -> some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            Color.clear.frame(width: notch.width)
            HStack(spacing: 6) {
                Spacer(minLength: 0)
                if let open = model.openAppPage {
                    HomeGearButton(symbol: "slider.horizontal.3", title: String(localized: "Edit")) { open(.modules) }
                        .help(Text("Turn modules on or off, and rank them, on the Modules page."))
                }
                if let openSettings = model.openSettings {
                    HomeGearButton(action: openSettings)
                }
            }
            .frame(maxWidth: (size.width - notch.width) / 2 - HomeWidgetMetrics.sidePadding)
        }
        .frame(height: notch.height)
        .padding(.horizontal, HomeWidgetMetrics.sidePadding)
    }
}

/// The search, and the modules opened lately (or, while typing, how many match and what the keys do).
private struct LibrarySidebar: View {
    let model: NotchViewModel

    var body: some View {
        let library = model.library
        let isSearching = !SearchWords.words(in: library.query).isEmpty
        VStack(alignment: .leading, spacing: 10) {
            NotchSearchBox(
                text: Binding(get: { library.query }, set: { model.setLibraryQuery($0) }),
                isActive: library.isTyping,
                focusRequest: library.focusRequest,
                placeholder: String(localized: "Search modules", comment: "Library: placeholder in the search field"),
                label: String(localized: "Search modules"),
                help: String(localized: "Type a module's name, or a word like music, files or AI. The arrow keys move through the modules, Return opens one, Esc clears the search."),
                clearHelp: String(localized: "Clear Search (Esc)"),
                isSnapshot: model.snapshotClock != nil,
                start: { model.libraryFieldClicked() },
                clear: { model.setLibraryQuery("") }
            )
            if isSearching {
                searchSummary(count: model.libraryResults.count)
                    .transition(.opacity)
            } else {
                recents
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: isSearching)
    }

    private var recents: some View {
        let recents = model.libraryRecents
        return VStack(alignment: .leading, spacing: 2) {
            Text("Recently used", comment: "Library: heading over the modules opened lately")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.4))
                .padding(.leading, 2)
                .padding(.bottom, 2)
                .accessibilityAddTraits(.isHeader)
            if recents.isEmpty {
                Text("Modules you open show up here.", comment: "Library: Recently used before anything was opened")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.white.opacity(0.35))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 2)
            } else {
                ForEach(recents) { entry in
                    LibraryRecentRow(model: model, entry: entry)
                }
            }
        }
    }

    private func searchSummary(count: Int) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(count == 0 ? String(localized: "No matches", comment: "Library: a search found nothing")
                 : count == 1 ? String(localized: "1 module", comment: "Library: one module matches")
                 : String(localized: "\(count) modules", comment: "Library: how many modules match a search"))
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.55))
                .monospacedDigit()
            if count > 0 {
                Text("Return opens · Esc clears", comment: "Library: the keys while searching")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.35))
            }
        }
        .padding(.leading, 2)
        .accessibilityElement(children: .combine)
    }
}

/// One module opened lately: its icon and name; a click opens it.
private struct LibraryRecentRow: View {
    let model: NotchViewModel
    let entry: LibraryEntry
    @State private var isHovered = false

    var body: some View {
        Button { model.openFromLibrary(entry.id) } label: {
            HStack(spacing: 7) {
                Image(systemName: entry.symbol)
                    .font(.system(size: 9.5, weight: .semibold))
                    .frame(width: 18, height: 18)
                    .background(.white.opacity(0.09), in: .rect(cornerRadius: 5, style: .continuous))
                Text(entry.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(isHovered ? 1 : 0.8))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 3)
            .frame(height: 22)
            .background(.white.opacity(isHovered ? 0.07 : 0), in: .rect(cornerRadius: 6, style: .continuous))
            .contentShape(.rect(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .moduleMenu(model: model, moduleID: entry.id, open: { model.openFromLibrary(entry.id) })
        .help(Text(entry.title))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(entry.title))
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(Text("Shows \(entry.title) in the notch."))
        .accessibilityAction { model.openFromLibrary(entry.id) }
        .moduleMenuAccessibilityActions(model: model, moduleID: entry.id)
    }
}

/// Every module's tile, by ranking (a search puts name matches first). Two rows fill the page; more scroll,
/// and the arrow keys keep the highlighted tile in view.
private struct LibraryGrid: View {
    let model: NotchViewModel
    let size: CGSize
    let tile: CGSize
    let columns: Int
    /// The whole panel, to turn a tile's place into the point a module grows from.
    let panel: CGSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let library = model.library
        let results = model.libraryResults
        ZStack(alignment: .bottom) {
            if results.isEmpty {
                noMatch(library.query)
                    .transition(.opacity)
            } else if model.snapshotClock != nil {
                // Off-screen pictures don't draw scroll views.
                tiles(results, highlight: library.highlight)
                    .frame(width: size.width, height: size.height, alignment: .topLeading)
                    .clipped()
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.vertical) {
                        tiles(results, highlight: library.highlight)
                    }
                    .scrollIndicators(.never)
                    .scrollBounceBehavior(.basedOnSize)
                    .onChange(of: library.highlight) { _, id in
                        guard let id else { return }
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { proxy.scrollTo(id) }
                    }
                }
                .transition(.opacity)
            }
            if let note = library.note {
                Text(LibraryText.note(note))
                    .font(.system(size: 10.5, weight: .medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(.black, in: Capsule())
                    .overlay { Capsule().strokeBorder(.white.opacity(0.12)) }
                    .padding(.bottom, 2)
                    .allowsHitTesting(false)
                    .transition(.opacity)
                    .accessibilityHidden(true)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .animation(reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.3, dampingFraction: 0.86), value: results.map(\.id))
    }

    private func tiles(_ results: [LibraryEntry], highlight: String?) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(tile.width), spacing: LibraryMetrics.gap, alignment: .top),
                                 count: columns),
                  alignment: .leading, spacing: LibraryMetrics.gap) {
            ForEach(results) { entry in
                LibraryTile(model: model, entry: entry, size: tile, isHighlighted: highlight == entry.id)
                    .id(entry.id)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(NotchLibraryView.space)) } action: { frame in
                        guard panel.width > 0, panel.height > 0 else { return }
                        model.libraryTileAnchors[entry.id] = UnitPoint(x: frame.midX / panel.width,
                                                                         y: frame.midY / panel.height)
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
            }
        }
    }

    /// A search that finds nothing: says so where the tiles would be.
    private func noMatch(_ query: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.white.opacity(0.45))
                .accessibilityHidden(true)
            Text("No modules match “\(query)”", comment: "Library: a search found nothing")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(2)
                .multilineTextAlignment(.center)
            Text("Try a module's name, or a word like music or files.", comment: "Library: what to search for")
                .font(.system(size: 10.5))
                .foregroundStyle(.white.opacity(0.4))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 12)
        .frame(width: size.width, height: size.height)
        .accessibilityElement(children: .combine)
    }
}

/// One module: its icon, name and a short status. Switched-off modules are dimmed with a dashed edge and
/// open the Modules page. The star shows on favorites, and on the others under the pointer.
private struct LibraryTile: View {
    let model: NotchViewModel
    let entry: LibraryEntry
    let size: CGSize
    let isHighlighted: Bool
    @State private var isHovered = false

    var body: some View {
        Button { model.openFromLibrary(entry.id) } label: {
            VStack(spacing: 3) {
                icon
                Text(entry.title)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(entry.isOn ? 0.92 : 0.5))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(statusLine)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.white.opacity(entry.isOn ? 0.45 : 0.35))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .padding(.horizontal, 6)
            .frame(width: size.width, height: size.height)
            .background {
                if entry.isOn {
                    RoundedRectangle(cornerRadius: LibraryMetrics.cornerRadius, style: .continuous)
                        .fill(.white.opacity(isHighlighted ? 0.13 : isHovered ? 0.1 : 0.06))
                }
            }
            .overlay { edge }
            .contentShape(.rect(cornerRadius: LibraryMetrics.cornerRadius))
        }
        .buttonStyle(PressableStyle())
        .overlay(alignment: .topTrailing) { star }
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .animation(.easeOut(duration: 0.15), value: isHighlighted)
        .moduleMenu(model: model, moduleID: entry.id, open: { model.openFromLibrary(entry.id) })
        .help(Text(help))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityLabel))
        .accessibilityAddTraits(isHighlighted ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint(entry.isOn ? Text("Shows \(entry.title) in the notch.") : Text("Opens Modules, where you can turn it on."))
        .accessibilityAction { model.openFromLibrary(entry.id) }
        .moduleMenuAccessibilityActions(model: model, moduleID: entry.id)
    }

    private var icon: some View {
        Image(systemName: entry.symbol)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white.opacity(entry.isOn ? 1 : 0.35))
            .frame(width: 26, height: 26)
            .background(.white.opacity(entry.isOn ? 0.09 : 0.04), in: .rect(cornerRadius: 8, style: .continuous))
            .overlay(alignment: .topTrailing) {
                // Something here waits for the person (an agent's question, a finished timer).
                if entry.waitsForYou {
                    Circle()
                        .fill(.white)
                        .frame(width: 6, height: 6)
                        .overlay { Circle().strokeBorder(.black, lineWidth: 1.5) }
                        .offset(x: 2, y: -2)
                        .accessibilityHidden(true)
                }
            }
    }

    @ViewBuilder
    private var edge: some View {
        let shape = RoundedRectangle(cornerRadius: LibraryMetrics.cornerRadius, style: .continuous)
        if !entry.isOn {
            shape.strokeBorder(.white.opacity(isHighlighted ? 0.5 : isHovered ? 0.3 : 0.18),
                               style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        } else if isHighlighted {
            shape.strokeBorder(.white.opacity(0.5), lineWidth: 1.5)
        } else {
            shape.strokeBorder(.white.opacity(0.06))
        }
    }

    private var statusLine: String {
        if entry.isFavoriteWithoutRoom { return LibraryText.noRoom }
        return entry.status ?? " "
    }

    /// The star: on every favorite, and on the others under the pointer or the arrow keys. With the bar
    /// full it still shows, dimmed, and a click says why nothing changed.
    @ViewBuilder
    private var star: some View {
        if entry.isOn, model.editsFavorites, entry.isFavorite || isHovered || isHighlighted {
            let canAdd = model.canAddFavorite
            Button { model.toggleFavorite(entry.id) } label: {
                Image(systemName: entry.isFavorite ? "star.fill" : "star")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(entry.isFavorite ? (entry.isFavoriteWithoutRoom ? 0.45 : 0.85) : canAdd ? 0.6 : 0.25))
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .padding(2)
            .help(Text(entry.isFavorite ? LibraryText.removeFavorite : canAdd ? LibraryText.addFavorite : LibraryText.barFull))
            .accessibilityHidden(true)
            .transition(.opacity)
        }
    }

    private var help: String {
        if !entry.isOn { return String(localized: "\(entry.title) is turned off. Click to turn it on in Modules.") }
        if entry.isFavoriteWithoutRoom { return String(localized: "\(entry.title) · \(LibraryText.noRoom)") }
        return [entry.title, entry.status].compactMap { $0 }.joined(separator: " · ")
    }

    private var accessibilityLabel: String {
        var parts = [entry.title]
        if let status = entry.status { parts.append(status) }
        if entry.isFavorite { parts.append(entry.isFavoriteWithoutRoom ? LibraryText.noRoom : String(localized: "Favorite")) }
        if entry.waitsForYou { parts.append(String(localized: "Waiting for you")) }
        return parts.joined(separator: ", ")
    }
}
