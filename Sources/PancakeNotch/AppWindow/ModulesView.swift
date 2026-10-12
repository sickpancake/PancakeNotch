import Learn
import ModuleNowPlaying
import ModuleShelf
import NotchCore
import NowPlayingCore
import SwiftUI

/// The modules that live in the notch (ADR-0010): your list (ranking, favorites, on/off), then one
/// card per module with a working practice notch, what it does, and its settings while it's on.
struct ModulesView: View {
    let context: AppContext
    /// Opens a module's lesson on Learn.
    let openLesson: (LessonID) -> Void

    var body: some View {
        AppPage(
            title: String(localized: "Modules"),
            subtitle: String(localized: "Small tools that live inside the notch.")
        ) {
            YourModulesCard(context: context)
            NowPlayingModuleCard(context: context) { openLesson(.nowPlaying) }
            ShelfModuleCard(
                preferences: context.preferences,
                arrangement: context.arrangement,
                settings: context.shelfSettings,
                store: context.shelfStore
            ) { openLesson(.shelf) }
        }
    }
}

// MARK: Your modules

/// Every module in ranking order: drag to reorder (the top two get the spots beside the notch), star
/// the ones you want as tabs, switch them on or off. Ear sides can be swapped.
private struct YourModulesCard: View {
    let context: AppContext
    @State private var dragging: String?
    /// The row a reorder drag is over right now (nil once it leaves, is dropped or is cancelled).
    @State private var dropTarget: String?

    var body: some View {
        let arrangement = context.arrangement
        SettingsCard(
            header: String(localized: "Your modules"),
            footer: String(localized: "Drag to change the order: the first two that are active get the small spots beside the notch. Starred modules are tabs in the open notch.")
        ) {
            ForEach(arrangement.order, id: \.self) { moduleID in
                ModuleListRow(context: context, moduleID: moduleID, dragging: $dragging, dropTarget: $dropTarget)
            }
            SettingsRow(
                title: String(localized: "Swap sides"),
                subtitle: String(localized: "Put the first module on the right of the notch instead of the left.")
            ) {
                HStack(spacing: 14) {
                    EarsDiagram(context: context)
                    Toggle(String(localized: "Swap sides"), isOn: Bindable(arrangement).swapsEarSides)
                        .labelsHidden()
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: arrangement.order)
        .onDisappear { dragging = nil; dropTarget = nil }
    }
}

/// One module in the list: its rank, name and what it's doing, a star and its switch.
private struct ModuleListRow: View {
    let context: AppContext
    let moduleID: String
    @Binding var dragging: String?
    @Binding var dropTarget: String?
    @State private var isHovered = false

    var body: some View {
        let arrangement = context.arrangement
        let info = AppContext.moduleInfo(moduleID)
        let rank = arrangement.rank(of: moduleID)
        let isOn = context.isEnabled(moduleID)
        HStack(spacing: 12) {
            Image(systemName: "line.3.horizontal")
                .font(.app(size: 12, weight: .semibold))
                .foregroundStyle(isHovered ? AppPalette.primaryText : AppPalette.tertiaryText)
                .frame(width: 16)
                .help(Text("Drag to change the order"))
                .accessibilityHidden(true)
            Text((rank + 1).formatted())
                .font(.app(size: 11.5, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(rank < 2 ? Color.black : AppPalette.secondaryText)
                .frame(width: 20, height: 20)
                .background(Circle().fill(rank < 2 ? Color.white : Color.clear))
                .overlay { if rank >= 2 { Circle().strokeBorder(AppPalette.hairlineStrong) } }
                .accessibilityHidden(true)
            Image(systemName: info.symbol)
                .font(.app(size: 13, weight: .semibold))
                .frame(width: 30, height: 30)
                .background(AppPalette.selection, in: .rect(cornerRadius: 8, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(info.title)
                    .font(.app(size: 13.5, weight: .semibold))
                Text(status(isOn: isOn))
                    .font(.app(size: 12))
                    .foregroundStyle(AppPalette.secondaryText)
            }
            Spacer(minLength: 8)
            Button {
                withAnimation(.snappy(duration: 0.2)) { arrangement.toggleFavorite(moduleID) }
            } label: {
                Image(systemName: arrangement.isFavorite(moduleID) ? "star.fill" : "star")
                    .font(.app(size: 13, weight: .semibold))
                    .foregroundStyle(arrangement.isFavorite(moduleID) ? AppPalette.primaryText : AppPalette.tertiaryText)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(Text(arrangement.isFavorite(moduleID) ? String(localized: "Remove from favorites") : String(localized: "Add to favorites")))
            .accessibilityLabel(Text(arrangement.isFavorite(moduleID)
                ? String(localized: "Remove \(info.title) from favorites")
                : String(localized: "Add \(info.title) to favorites")))
            Toggle(info.title, isOn: Binding(
                get: { context.isEnabled(moduleID) },
                set: { enabled in withAnimation(.easeInOut(duration: 0.25)) { context.setEnabled(moduleID, enabled) } }
            ))
            .labelsHidden()
        }
        .padding(.horizontal, AppMetrics.cardInset)
        .padding(.vertical, 12)
        .background(dragging == moduleID && dropTarget != nil ? AppPalette.hover : .clear)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
            // No hover events arrive during a drag: one now means a reorder drag ended without a drop.
            if hovering, dropTarget == nil { dragging = nil }
        }
        .onDrag {
            dragging = moduleID
            return NSItemProvider(object: moduleID as NSString)
        }
        .onDrop(of: [.text], delegate: ModuleReorderDrop(target: moduleID, arrangement: arrangement, dragging: $dragging, dropTarget: $dropTarget))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("\(info.title), number \(rank + 1)"))
        .accessibilityActions {
            if rank > 0 {
                Button(String(localized: "Move up")) { move(by: -1) }
            }
            if rank < arrangement.order.count - 1 {
                Button(String(localized: "Move down")) { move(by: 1) }
            }
        }
        .contextMenu {
            Button(String(localized: "Move Up")) { move(by: -1) }
                .disabled(rank == 0)
            Button(String(localized: "Move Down")) { move(by: 1) }
                .disabled(rank >= arrangement.order.count - 1)
        }
    }

    /// Moves the module one place and tells VoiceOver where it is now.
    private func move(by step: Int) {
        withAnimation(.snappy(duration: 0.2)) { context.arrangement.move(moduleID, by: step) }
        let title = AppContext.moduleInfo(moduleID).title
        let rank = context.arrangement.rank(of: moduleID)
        AccessibilityNotification.Announcement(String(localized: "\(title), now number \(rank + 1)")).post()
    }

    /// Where its ear goes. Ears go to the first two active modules (switched on and with something to
    /// show) in this order, the first on the left; a module alone takes the left.
    private func status(isOn: Bool) -> String {
        guard isOn else { return String(localized: "Off") }
        let arrangement = context.arrangement
        let place = arrangement.order.filter { context.isEnabled($0) }.firstIndex(of: moduleID) ?? 0
        switch (place, arrangement.swapsEarSides) {
        case (0, false): return String(localized: "Left of the notch when active")
        case (0, true): return String(localized: "Right of the notch when active")
        case (1, false): return String(localized: "Right of the notch when active, or left when it's the only one")
        case (1, true): return String(localized: "Left of the notch when active, or right when it's the only one")
        default: return String(localized: "In the open notch, and beside it when one above is idle")
        }
    }
}

/// Live reordering: a row moves to where it's dragged over.
private struct ModuleReorderDrop: DropDelegate {
    let target: String
    let arrangement: ModuleArrangement
    @Binding var dragging: String?
    @Binding var dropTarget: String?

    func validateDrop(info: DropInfo) -> Bool {
        // Only a row of this list being dragged (not text from elsewhere).
        dragging.map(arrangement.order.contains) ?? false
    }

    func dropEntered(info: DropInfo) {
        guard let dragging, arrangement.order.contains(dragging) else { return }
        dropTarget = target
        guard dragging != target else { return }
        let index = arrangement.rank(of: target)
        Task { @MainActor in
            withAnimation(.snappy(duration: 0.2)) { arrangement.move(dragging, to: index) }
        }
    }

    func dropExited(info: DropInfo) {
        if dropTarget == target { dropTarget = nil }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        dropTarget = nil
        return true
    }
}

/// A tiny notch with the first two modules' symbols where their ears go.
private struct EarsDiagram: View {
    let context: AppContext

    var body: some View {
        let ranked = context.arrangement.order.filter { context.isEnabled($0) }.prefix(2).map { AppContext.moduleInfo($0).symbol }
        let first = ranked.first
        let second = ranked.count > 1 ? ranked[1] : nil
        let left = context.arrangement.swapsEarSides ? second : first
        let right = context.arrangement.swapsEarSides ? first : second
        HStack(spacing: 0) {
            ear(left)
            Color.black.frame(width: 34)
            ear(right)
        }
        .frame(height: 20)
        .background(Color.black, in: UnevenRoundedRectangle(bottomLeadingRadius: 7, bottomTrailingRadius: 7, style: .continuous))
        .overlay {
            UnevenRoundedRectangle(bottomLeadingRadius: 7, bottomTrailingRadius: 7, style: .continuous)
                .strokeBorder(AppPalette.hairlineStrong)
        }
        .animation(.snappy(duration: 0.25), value: [left, right])
        .accessibilityHidden(true)
    }

    private func ear(_ symbol: String?) -> some View {
        ZStack {
            if let symbol {
                Image(systemName: symbol)
                    .font(.app(size: 9, weight: .semibold))
                    .foregroundStyle(.white)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(width: 22)
    }
}

// MARK: Now Playing

/// Now Playing in one container: a practice notch playing a pretend song, what it does with its switch,
/// and its settings while it's on.
private struct NowPlayingModuleCard: View {
    let context: AppContext
    let learn: () -> Void
    @State private var showsSettings = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var settings: NowPlayingSettings { context.nowPlayingSettings }

    private let points = [
        String(localized: "Works with Music, Spotify, podcasts and videos in your browser"),
        String(localized: "Pause, skip and drag through a song without switching apps"),
        String(localized: "Click the album art to jump to the app that's playing"),
        String(localized: "A paused song stays beside the notch until you move on"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            NotchStage(
                behavior: context.preferences.notchBehavior,
                arrangement: context.arrangement,
                isActive: settings.isEnabled,
                // The pretend song plays only while Now Playing is on: nothing animates under the dimmed stage.
                practice: settings.isEnabled ? [.nowPlaying] : [],
                inactiveHint: String(localized: "Turn on Now Playing to try it here."),
                activeHint: String(localized: "A pretend song is playing. Hover the notch and try the buttons.")
            )
            .background(Color.black)
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 16, topTrailingRadius: 16, style: .continuous))

            AppPalette.hairline.frame(height: 1)

            ModuleAbout(
                symbol: "music.note",
                title: String(localized: "Now Playing"),
                summary: String(localized: "Whatever's playing on your Mac, right in the notch: album art and sound bars beside it, the controls when you open it."),
                points: points,
                learnTitle: String(localized: "Learn Now Playing"),
                learnHint: String(localized: "Opens a hands-on Now Playing lesson on the Learn page."),
                isOn: Binding(get: { settings.isEnabled }, set: { value in withAnimation(animation) { settings.isEnabled = value } }),
                learn: learn
            )
            .padding(AppMetrics.cardInset)

            if settings.isEnabled {
                AppPalette.hairline.frame(height: 1)
                SettingsDisclosure(isOpen: showsSettings, label: String(localized: "Now Playing settings")) {
                    withAnimation(animation) { showsSettings.toggle() }
                }
                if showsSettings {
                    AppPalette.hairline.frame(height: 1)
                    NowPlayingSettingsRows(settings: settings, center: context.nowPlaying)
                        .transition(.opacity)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .glassPanel()
    }

    private var animation: Animation {
        .easeInOut(duration: reduceMotion ? 0.15 : 0.25)
    }
}

/// Now Playing's settings, as rows with hairlines between them.
private struct NowPlayingSettingsRows: View {
    @Bindable var settings: NowPlayingSettings
    let center: NowPlayingCenter

    var body: some View {
        VStack(spacing: 0) {
            Group(subviews: rows) { rows in
                ForEach(rows) { row in
                    if row.id != rows.first?.id {
                        AppPalette.hairline
                            .frame(height: 1)
                            .padding(.horizontal, AppMetrics.cardInset)
                    }
                    row
                }
            }
        }
    }

    @ViewBuilder
    private var rows: some View {
        SettingsRow(title: String(localized: "Connection"), subtitle: connectionText) {
            HStack(spacing: 8) {
                if center.needsAutomationPermission {
                    Button(String(localized: "Allow Control…")) {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
                if case .connected = center.connection {
                    ConnectionBadge(isGood: true)
                } else {
                    Button(String(localized: "Try Again")) { center.retryConnection() }
                }
            }
        }
        SettingsRow(
            title: String(localized: "Show album art and sound bars beside the notch"),
            subtitle: String(localized: "While a song plays or is paused. Off keeps the notch closed until you open it.")
        ) {
            Toggle(String(localized: "Show album art and sound bars beside the notch"), isOn: $settings.showsInEars)
                .labelsHidden()
        }
        SettingsRow(
            title: String(localized: "Show each new song for a moment"),
            subtitle: String(localized: "When the song changes, its title and artist slide out under the notch for 3 seconds.")
        ) {
            Toggle(String(localized: "Show each new song for a moment"), isOn: $settings.peeksOnSongChange)
                .labelsHidden()
        }
        SettingsRow(
            title: String(localized: "Time on the right"),
            subtitle: String(localized: "You can also click the time in the notch to switch.")
        ) {
            MonochromeSegmented(
                title: String(localized: "Time on the right"),
                options: [(true, String(localized: "Time left")), (false, String(localized: "Song length"))],
                selection: $settings.showsRemainingTime
            )
        }
        IgnoredAppsRow(settings: settings, center: center)
    }

    private var connectionText: String {
        switch center.connection {
        case .connected:
            String(localized: "Connected: shows music and videos from every app.")
        case .limited:
            String(localized: "Limited: macOS isn't sharing what's playing, so only Music and Spotify show (Spotify without album art).")
        case .unavailable(let reason):
            String(localized: "\(reason). PancakeNotch can't see what's playing right now.")
        case .starting:
            String(localized: "Connecting…")
        case .practice:
            String(localized: "Practice player.")
        }
    }
}

private struct ConnectionBadge: View {
    let isGood: Bool

    var body: some View {
        Label(String(localized: "Working"), systemImage: "checkmark")
            .font(.app(size: 12, weight: .semibold))
            .foregroundStyle(AppPalette.primaryText)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(AppPalette.hover, in: Capsule())
            .overlay(PillOutline(color: AppPalette.hairline))
    }
}

/// Apps whose music never shows: the list with remove buttons, and a menu of apps seen playing to add.
private struct IgnoredAppsRow: View {
    @Bindable var settings: NowPlayingSettings
    let center: NowPlayingCenter

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 24) {
                SettingsRowLabel(
                    title: String(localized: "Ignored apps"),
                    subtitle: String(localized: "Their music and videos never show in the notch. Handy for a browser.")
                )
                Menu {
                    let candidates = center.seenApps.filter { !settings.isIgnored($0) }
                    if candidates.isEmpty {
                        Text("Apps show up here once they've played something")
                    } else {
                        ForEach(candidates, id: \.self) { bundleID in
                            Button(PlayerName.name(for: bundleID)) { settings.ignore(bundleID) }
                        }
                    }
                } label: {
                    Text("Ignore an App")
                }
                .menuStyle(.button)
                .buttonStyle(PillButtonStyle())
                .fixedSize()
            }
            if !settings.ignoredApps.isEmpty {
                VStack(spacing: 6) {
                    ForEach(settings.ignoredApps, id: \.self) { bundleID in
                        HStack(spacing: 10) {
                            if let icon = PlayerName.icon(for: bundleID) {
                                Image(nsImage: icon)
                                    .resizable()
                                    .frame(width: 20, height: 20)
                                    .accessibilityHidden(true)
                            }
                            Text(PlayerName.name(for: bundleID))
                                .font(.app(size: 13, weight: .medium))
                            Spacer(minLength: 8)
                            Button(String(localized: "Show Again")) { settings.unignore(bundleID) }
                                .accessibilityLabel(Text("Show \(PlayerName.name(for: bundleID)) again"))
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 38)
                        .background(AppPalette.hover, in: .rect(cornerRadius: 10, style: .continuous))
                    }
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: settings.ignoredApps)
        .settingsRowPadding()
    }
}

/// An app's name and icon from its bundle ID.
enum PlayerName {
    static func name(for bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    static func icon(for bundleID: String) -> NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}

// MARK: Shared parts

/// A module's name with its switch, what it does, and its "Learn" button.
private struct ModuleAbout: View {
    let symbol: String
    let title: String
    let summary: String
    let points: [String]
    let learnTitle: String
    let learnHint: String
    @Binding var isOn: Bool
    let learn: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.app(size: 13, weight: .semibold))
                    .frame(width: 30, height: 30)
                    .background(AppPalette.selection, in: .rect(cornerRadius: 8, style: .continuous))
                    .accessibilityHidden(true)
                Text(title)
                    .font(.app(size: 18, weight: .bold))
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                Toggle(title, isOn: $isOn)
                    .toggleStyle(MonochromeSwitchStyle())
                    .labelsHidden()
            }
            Text(summary)
                .font(.app(size: 13.5))
                .foregroundStyle(AppPalette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 18, alignment: .topLeading), GridItem(.flexible(), alignment: .topLeading)], alignment: .leading, spacing: 8) {
                ForEach(points, id: \.self) { point in
                    HStack(alignment: .firstTextBaseline, spacing: 9) {
                        Circle()
                            .fill(AppPalette.secondaryText)
                            .frame(width: 4, height: 4)
                            .alignmentGuide(.firstTextBaseline) { $0[.bottom] + 3 }
                        Text(point)
                            .font(.app(size: 12.5, weight: .medium))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.top, 14)
            Button(action: learn) {
                Label(learnTitle, systemImage: "graduationcap")
            }
            .padding(.top, 18)
            .accessibilityHint(Text(learnHint))
        }
    }
}

/// A card's "Settings" dropdown header, with a chevron that turns when open.
struct SettingsDisclosure: View {
    let isOpen: Bool
    let label: String
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack {
                Text("Settings")
                    .font(.app(size: 13.5, weight: .semibold))
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.app(size: 12, weight: .semibold))
                    .foregroundStyle(AppPalette.secondaryText)
                    .rotationEffect(.degrees(isOpen ? 90 : 0))
            }
            .padding(.horizontal, AppMetrics.cardInset)
            .frame(height: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text(isOpen ? String(localized: "Shown") : String(localized: "Hidden")))
        .accessibilityHint(Text("Shows or hides the settings."))
    }
}

// MARK: Shelf

/// The Shelf in one container: a working notch with example items to try, what the Shelf does with
/// its on/off switch, and a "Settings" dropdown that's there only while the Shelf is on.
private struct ShelfModuleCard: View {
    let preferences: Preferences
    let arrangement: ModuleArrangement
    @Bindable var settings: ShelfSettings
    let store: ShelfStore
    let learn: () -> Void
    @State private var showsSettings = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let points = [
        String(localized: "Drop files, images, text and links on the notch"),
        String(localized: "Click an item for a big preview, or to edit a note or link"),
        String(localized: "Right-click to copy, share or AirDrop"),
        String(localized: "A small tray in the notch shows the count when it's nearly full"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            NotchStage(
                behavior: preferences.notchBehavior,
                arrangement: arrangement,
                isActive: settings.isEnabled,
                practice: [.shelf],
                inactiveHint: String(localized: "Turn on the Shelf to try it here."),
                activeHint: String(localized: "Hover the notch, then click an item to open it. These are example items.")
            )
            .background(Color.black)
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 16, topTrailingRadius: 16, style: .continuous))

            AppPalette.hairline.frame(height: 1)

            about
                .padding(AppMetrics.cardInset)

            if settings.isEnabled {
                AppPalette.hairline.frame(height: 1)
                settingsToggle
                if showsSettings {
                    AppPalette.hairline.frame(height: 1)
                    ShelfSettingsRows(settings: settings, store: store)
                        .transition(.opacity)
                }
            }
        }
        // While the dropdown closes, the card shrinks over the rows instead of them spilling out.
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .glassPanel()
    }

    /// Opening or closing animates the whole page, so the card below moves along with this one.
    /// Reduce Motion keeps it short, so it reads as a fade rather than a slide.
    private var animation: Animation {
        .easeInOut(duration: reduceMotion ? 0.15 : 0.25)
    }

    private var about: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "tray")
                    .font(.app(size: 13, weight: .semibold))
                    .frame(width: 30, height: 30)
                    .background(AppPalette.selection, in: .rect(cornerRadius: 8, style: .continuous))
                    .accessibilityHidden(true)
                Text("Shelf")
                    .font(.app(size: 18, weight: .bold))
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                Toggle(String(localized: "Shelf"), isOn: $settings.isEnabled.animation(animation))
                    .toggleStyle(MonochromeSwitchStyle())
                    .labelsHidden()
            }
            Text("A place in the notch for things you're about to use: drop them on, drag them out later.")
                .font(.app(size: 13.5))
                .foregroundStyle(AppPalette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 18, alignment: .topLeading), GridItem(.flexible(), alignment: .topLeading)], alignment: .leading, spacing: 8) {
                ForEach(points, id: \.self) { point in
                    HStack(alignment: .firstTextBaseline, spacing: 9) {
                        Circle()
                            .fill(AppPalette.secondaryText)
                            .frame(width: 4, height: 4)
                            .alignmentGuide(.firstTextBaseline) { $0[.bottom] + 3 }
                        Text(point)
                            .font(.app(size: 12.5, weight: .medium))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.top, 14)
            Button(action: learn) {
                Label(String(localized: "Learn the Shelf"), systemImage: "graduationcap")
            }
            .padding(.top, 18)
            .accessibilityHint(Text("Opens a hands-on Shelf lesson on the Learn page."))
        }
    }

    private var settingsToggle: some View {
        SettingsDisclosure(isOpen: showsSettings, label: String(localized: "Shelf settings")) {
            withAnimation(animation) { showsSettings.toggle() }
        }
    }
}

/// The Shelf's settings (ADR-0013), as rows with hairlines between them.
private struct ShelfSettingsRows: View {
    @Bindable var settings: ShelfSettings
    let store: ShelfStore
    @State private var confirmingClear = false

    var body: some View {
        VStack(spacing: 0) {
            Group(subviews: rows) { rows in
                ForEach(rows) { row in
                    if row.id != rows.first?.id {
                        AppPalette.hairline
                            .frame(height: 1)
                            .padding(.horizontal, AppMetrics.cardInset)
                    }
                    row
                }
            }
        }
    }

    @ViewBuilder
    private var rows: some View {
        SettingsRow(
            title: String(localized: "On the Shelf now"),
            subtitle: String(localized: "\(store.items.count) of \(ShelfStore.capacity) items. Files stay where they are: the Shelf only remembers where to find them.")
        ) {
            // Two clicks, like Clear all in the notch.
            Button(!confirmingClear ? String(localized: "Clear Shelf")
                   : store.items.count == 1 ? String(localized: "Clear 1 item?")
                   : String(localized: "Clear \(store.items.count) items?")) {
                if confirmingClear { store.clear() }
                confirmingClear.toggle()
            }
            .disabled(store.items.isEmpty)
            // The question is about the items it names: ask again if they change.
            .onChange(of: store.items.count) { confirmingClear = false }
        }
        SettingsRow(
            title: String(localized: "Dragging files out"),
            subtitle: String(localized: "Copy leaves the original where it is. Move works like Finder: same disk moves, another disk copies.")
        ) {
            MonochromeSegmented(
                title: String(localized: "Dragging files out"),
                options: [(.copy, String(localized: "Copy")), (.move, String(localized: "Move"))],
                selection: $settings.dragOutMode
            )
        }
        SettingsRow(
            title: String(localized: "Remove items after dragging them out"),
            subtitle: String(localized: "Off keeps them on the Shelf so you can drop them again.")
        ) {
            Toggle(String(localized: "Remove items after dragging them out"), isOn: $settings.removeAfterDragOut)
                .labelsHidden()
        }
        SettingsRow(
            title: String(localized: "Adding something already there"),
            subtitle: String(localized: "What happens when you drop an item that's already on the Shelf.")
        ) {
            MonochromeSegmented(
                title: String(localized: "Adding something already there"),
                options: [
                    (.ask, String(localized: "Ask")),
                    (.moveToFront, String(localized: "Move to front")),
                    (.addAgain, String(localized: "Add again")),
                ],
                selection: $settings.duplicatePolicy
            )
        }
        SettingsRow(
            title: String(localized: "Clear the Shelf after"),
            subtitle: String(localized: "Older items are removed the next time the notch opens.")
        ) {
            MonochromeSegmented(
                title: String(localized: "Clear the Shelf after"),
                options: [
                    (.never, String(localized: "Never")),
                    (.day, String(localized: "1 day")),
                    (.week, String(localized: "1 week")),
                    (.month, String(localized: "1 month")),
                ],
                selection: $settings.autoClear
            )
        }
        SettingsRow(
            title: String(localized: "Show AirDrop while dragging"),
            subtitle: String(localized: "Drop on it to send right away, without keeping the item.")
        ) {
            Toggle(String(localized: "Show AirDrop while dragging"), isOn: $settings.showsAirDropZone)
                .labelsHidden()
        }
        SettingsRow(
            title: String(localized: "Show in the notch when nearly full and after drops"),
            subtitle: String(localized: "From \(ShelfStore.nearlyFullCount) items the notch shows a small tray with the count, and it shows the new count for a moment after you drop something.")
        ) {
            Toggle(String(localized: "Show in the notch when nearly full and after drops"), isOn: $settings.showsInEars)
                .labelsHidden()
        }
        SettingsRow(
            title: String(localized: "Mission Control opens when dropping?"),
            subtitle: String(localized: "macOS opens Mission Control when you drag to the very top of the screen. The notch opens before that, so drop a little lower, or turn off \"Drag windows to top of screen to enter Mission Control\" in Desktop & Dock.")
        ) {
            Button(String(localized: "Open Desktop & Dock")) {
                if let url = URL(string: "x-apple.systempreferences:com.apple.Desktop-Settings.extension") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }
}
