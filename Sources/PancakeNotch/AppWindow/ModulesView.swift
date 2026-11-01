import AgentsCore
import ConvertKit
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
    /// Modules whose "Settings" dropdown is open.
    @State private var openSettings: Set<String>
    /// The AI tools found on this Mac, for the offer to switch on Agents and AI Usage.
    @State private var foundTools: [AgentTool] = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(context: AppContext, openLesson: @escaping (LessonID) -> Void, openSettings: Set<String> = []) {
        self.context = context
        self.openLesson = openLesson
        _openSettings = State(initialValue: openSettings)
    }

    var body: some View {
        ScrollViewReader { proxy in
            AppPage(
                title: String(localized: "Modules"),
                subtitle: String(localized: "Small tools that live inside the notch.")
            ) {
                if let offer = AgentsOffer(found: foundTools, settings: context.agentsSettings) {
                    AgentsOfferCard(context: context, offer: offer)
                        .transition(.opacity)
                }
                YourModulesCard(context: context) { moduleID in showSettings(moduleID, proxy: proxy) }
                NowPlayingModuleCard(context: context, showsSettings: settingsBinding("nowPlaying")) { openLesson(.nowPlaying) }
                ShelfModuleCard(
                    preferences: context.preferences,
                    arrangement: context.arrangement,
                    settings: context.shelfSettings,
                    store: context.shelfStore,
                    showsSettings: settingsBinding("shelf")
                ) { openLesson(.shelf) }
                AgentsModuleCard(context: context, showsSettings: settingsBinding("agents")) { openLesson(.agents) }
                AIUsageModuleCard(context: context, showsSettings: settingsBinding("aiUsage")) { openLesson(.aiUsage) }
                TimerModuleCard(context: context, showsSettings: settingsBinding("timer")) { openLesson(.timer) }
            }
            .onAppear { foundTools = context.detectTools() }
        }
    }

    /// The scroll target for a module's "Settings" dropdown.
    static func settingsAnchor(_ moduleID: String) -> String { "settings-\(moduleID)" }

    private var animation: Animation {
        .easeInOut(duration: reduceMotion ? 0.15 : 0.25)
    }

    private func settingsBinding(_ moduleID: String) -> Binding<Bool> {
        Binding(
            get: { openSettings.contains(moduleID) },
            set: { isOpen in
                if isOpen { openSettings.insert(moduleID) } else { openSettings.remove(moduleID) }
            }
        )
    }

    /// Opens a module's settings and scrolls them into view, past its preview.
    private func showSettings(_ moduleID: String, proxy: ScrollViewProxy) {
        withAnimation(animation) { _ = openSettings.insert(moduleID) }
        // Once the rows are in the layout, so the scroll lands on them.
        Task { @MainActor in
            withAnimation(animation) { proxy.scrollTo(Self.settingsAnchor(moduleID), anchor: .top) }
        }
    }
}

// MARK: Your modules

/// Every module in ranking order: drag to reorder (the top two get the spots beside the notch), star
/// the ones you want as tabs, switch them on or off. Ear sides can be swapped.
private struct YourModulesCard: View {
    let context: AppContext
    /// Opens a module's settings further down the page.
    let showSettings: (String) -> Void
    @State private var dragging: String?
    /// The row a reorder drag is over right now (nil once it leaves, is dropped or is cancelled).
    @State private var dropTarget: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let arrangement = context.arrangement
        SettingsCard(
            header: String(localized: "Your modules"),
            footer: footer(arrangement.navigation)
        ) {
            ForEach(arrangement.order, id: \.self) { moduleID in
                ModuleListRow(context: context, moduleID: moduleID, dragging: $dragging, dropTarget: $dropTarget) {
                    showSettings(moduleID)
                }
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
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: arrangement.order)
        .onDisappear { dragging = nil; dropTarget = nil }
    }

    /// The order, then what a star does with the way the open notch is set to move between modules.
    private func footer(_ navigation: NotchNavigation) -> String {
        let order = String(localized: "Drag a module or use its arrows to reorder. The first two that are active get the spots beside the notch.")
        let favorites = switch navigation {
        case .tabsAndMenu:
            String(localized: "Favorites (★) get a tab in the open notch and a big tile in the Module Menu.")
        case .menu:
            String(localized: "Favorites (★) get a big tile at the top of the Module Menu.")
        case .tabs:
            String(localized: "Every module has a tab right now, so favorites only matter with a Module Menu (Notch settings).")
        }
        return "\(order) \(favorites)"
    }
}

/// One module in the list: its rank, name and what it's doing, a star and its switch.
private struct ModuleListRow: View {
    let context: AppContext
    let moduleID: String
    @Binding var dragging: String?
    @Binding var dropTarget: String?
    let showSettings: () -> Void
    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let arrangement = context.arrangement
        let info = AppContext.moduleInfo(moduleID)
        let rank = arrangement.rank(of: moduleID)
        let isOn = context.isEnabled(moduleID)
        // Without a Module Menu every module is a tab: a star would change nothing.
        let favoritesMatter = arrangement.navigation != .tabs
        HStack(spacing: 12) {
            // Up and down arrows, so the order can change without dragging (keyboard, Full Keyboard Access).
            VStack(spacing: 0) {
                moveButton(up: true, title: info.title, isEnabled: rank > 0)
                moveButton(up: false, title: info.title, isEnabled: rank < arrangement.order.count - 1)
            }
            .help(Text("Drag the row or use the arrows to change the order"))
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
            // Straight to the module's settings, past its preview. Only while it's on (they show only then);
            // the space stays so the star and switch don't shift.
            Button(action: showSettings) {
                Image(systemName: "gearshape")
                    .font(.app(size: 13, weight: .semibold))
                    .foregroundStyle(isHovered ? AppPalette.primaryText : AppPalette.secondaryText)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(isOn ? 1 : 0)
            .disabled(!isOn)
            .accessibilityHidden(!isOn)
            .help(Text("\(info.title) settings"))
            .accessibilityLabel(Text("\(info.title) settings"))
            .accessibilityHint(Text("Opens the settings further down this page."))
            Button {
                withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) { arrangement.toggleFavorite(moduleID) }
            } label: {
                Image(systemName: arrangement.isFavorite(moduleID) ? "star.fill" : "star")
                    .font(.app(size: 13, weight: .semibold))
                    .foregroundStyle(arrangement.isFavorite(moduleID) ? AppPalette.primaryText : AppPalette.tertiaryText)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!favoritesMatter)
            .opacity(favoritesMatter ? 1 : 0.35)
            .help(Text(arrangement.isFavorite(moduleID) ? String(localized: "Remove from favorites") : String(localized: "Add to favorites")))
            .accessibilityLabel(Text(arrangement.isFavorite(moduleID)
                ? String(localized: "Remove \(info.title) from favorites")
                : String(localized: "Add \(info.title) to favorites")))
            Toggle(info.title, isOn: Binding(
                get: { context.isEnabled(moduleID) },
                set: { enabled in withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : .easeInOut(duration: 0.25)) { context.setEnabled(moduleID, enabled) } }
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
        .onDrop(of: [.text], delegate: ModuleReorderDrop(target: moduleID, arrangement: arrangement, reduceMotion: reduceMotion,
                                                         dragging: $dragging, dropTarget: $dropTarget))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("\(info.title), number \(rank + 1)"))
        .accessibilityActions {
            if rank > 0 {
                Button(String(localized: "Move Up")) { move(by: -1) }
            }
            if rank < arrangement.order.count - 1 {
                Button(String(localized: "Move Down")) { move(by: 1) }
            }
        }
        .contextMenu {
            Button(String(localized: "Move Up")) { move(by: -1) }
                .disabled(rank == 0)
            Button(String(localized: "Move Down")) { move(by: 1) }
                .disabled(rank >= arrangement.order.count - 1)
        }
    }

    private func moveButton(up: Bool, title: String, isEnabled: Bool) -> some View {
        Button { move(by: up ? -1 : 1) } label: {
            Image(systemName: up ? "chevron.up" : "chevron.down")
                .font(.app(size: 9.5, weight: .bold))
                .foregroundStyle(isHovered ? AppPalette.primaryText : AppPalette.tertiaryText)
                .frame(width: 18, height: 14)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.3)
        .accessibilityLabel(Text(up ? String(localized: "Move \(title) up") : String(localized: "Move \(title) down")))
    }

    /// Moves the module one place and tells VoiceOver where it is now.
    private func move(by step: Int) {
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) { context.arrangement.move(moduleID, by: step) }
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
        default: return String(localized: "In the open notch. Beside it too when a module above has nothing to show")
        }
    }
}

/// Live reordering: a row moves to where it's dragged over.
private struct ModuleReorderDrop: DropDelegate {
    let target: String
    let arrangement: ModuleArrangement
    let reduceMotion: Bool
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
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) { arrangement.move(dragging, to: index) }
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        .animation(reduceMotion ? .easeInOut(duration: 0.15) : .snappy(duration: 0.25), value: [left, right])
        .accessibilityHidden(true)
    }

    private func ear(_ symbol: String?) -> some View {
        ZStack {
            if let symbol {
                Image(systemName: symbol)
                    .font(.app(size: 9, weight: .semibold))
                    .foregroundStyle(.white)
                    .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
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
    @Binding var showsSettings: Bool
    let learn: () -> Void
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
                activeHint: String(localized: "A pretend song is playing. Hover or click the notch and try the buttons."),
                badge: .practice
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
                .id(ModulesView.settingsAnchor("nowPlaying"))
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
struct NowPlayingSettingsRows: View {
    @Bindable var settings: NowPlayingSettings
    let center: NowPlayingCenter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                switch center.connection {
                case .connected:
                    ConnectionBadge(isGood: true)
                case .limited, .unavailable:
                    // Only when something is wrong: starting up (or the practice player) has nothing to retry.
                    Button(String(localized: "Try Again")) { center.retryConnection() }
                case .starting, .practice:
                    EmptyView()
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
        soundBarsRows
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
            String(localized: "Limited: macOS isn't sharing what's playing, so only Music and Spotify show (Spotify without album art). Trying again often fixes it.")
        case .unavailable:
            String(localized: "PancakeNotch can't see what's playing right now. Trying again often fixes it.")
        case .starting:
            String(localized: "Connecting…")
        case .practice:
            String(localized: "Practice player.")
        }
    }
}

// MARK: Sound bars

extension NowPlayingSettingsRows {
    /// How the bars move; with "Follow the music", what they show and whether macOS allows listening.
    @ViewBuilder
    var soundBarsRows: some View {
        SettingsRow(title: String(localized: "Sound bars"), subtitle: soundBarsText) {
            MonochromeSegmented(
                title: String(localized: "Sound bars"),
                options: [
                    (.followMusic, String(localized: "Follow the music")),
                    (.gentle, String(localized: "Gentle motion")),
                    (.still, String(localized: "Still")),
                ],
                selection: $settings.soundBars
            )
        }
        // Without the ears there are no bars: say so instead of offering choices that do nothing.
        .disabled(!settings.showsInEars)
        .onChange(of: settings.soundBars) { _, style in
            if style == .followMusic, settings.soundBarsAccess != .denied {
                // Ask right away, while the user is looking at the setting.
                SoundBarsAudio.shared.checkAccess(track: center.track, isPractice: isPractice, settings: settings)
            } else {
                SoundBarsAudio.shared.endCheck()
            }
        }
        if settings.soundBars == .followMusic, settings.showsInEars {
            SettingsRow(
                title: String(localized: "Bars show"),
                subtitle: String(localized: "Bass to treble: each bar is a slice of the sound, low notes on the left, high notes on the right. Loudness: every bar follows how loud it is.")
            ) {
                MonochromeSegmented(
                    title: String(localized: "Bars show"),
                    options: [(.bands, String(localized: "Bass to treble")), (.loudness, String(localized: "Loudness"))],
                    selection: $settings.soundBarsShow
                )
            }
            SoundBarsAccessRow(settings: settings, center: center, isPractice: isPractice, audio: SoundBarsAudio.shared)
        }
    }

    private var isPractice: Bool { center.connection == .practice }

    private var soundBarsText: String {
        guard settings.showsInEars else {
            return String(localized: "Turn on album art and sound bars beside the notch to choose how the bars move.")
        }
        let text = switch settings.soundBars {
        case .followMusic:
            String(localized: "The bars follow the real sound of the app that's playing, beat by beat.")
        case .gentle:
            String(localized: "A calm made-up animation while the playing app makes sound; the bars rest when it's quiet. No permission needed.")
        case .still:
            String(localized: "The bars stand still.")
        }
        guard reduceMotion, settings.soundBars != .still else { return text }
        return text + " " + String(localized: "Reduce Motion is on, so the bars stay still.")
    }
}

/// "Follow the music" needs macOS's System Audio Recording permission: what that means, whether it's
/// allowed, and what to do when it isn't.
private struct SoundBarsAccessRow: View {
    @Bindable var settings: NowPlayingSettings
    let center: NowPlayingCenter
    let isPractice: Bool
    let audio: SoundBarsAudio

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 24) {
                SettingsRowLabel(
                    title: String(localized: "System Audio Recording"),
                    subtitle: String(localized: "To follow the music, macOS asks for System Audio Recording and shows a purple dot in the menu bar while the bars listen. PancakeNotch listens only to the app that's playing, only while the bars are showing, and never records or saves sound.")
                )
                controls
                    .fixedSize()
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: statusSymbol)
                    .font(.app(size: 11, weight: .bold))
                    .accessibilityHidden(true)
                Text(statusText)
                    .font(.app(size: 12.5, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(AppPalette.primaryText)
            .accessibilityElement(children: .combine)
        }
        .settingsRowPadding()
    }

    /// Something real is playing, so there's something to listen to right now.
    private var canListenNow: Bool {
        !isPractice && center.track?.isPlaying == true
    }

    @ViewBuilder
    private var controls: some View {
        HStack(spacing: 8) {
            switch settings.soundBarsAccess {
            case .denied:
                Button(String(localized: "Open Privacy Settings")) { Self.openPrivacySettings() }
                Button(String(localized: "Try Again")) { tryAgain() }
                    .accessibilityHint(Text("Clears the remembered answer and listens again"))
            case .allowed:
                AllowedBadge()
            case .unknown:
                if !audio.isChecking, canListenNow {
                    Button(String(localized: "Ask Now")) { tryAgain() }
                        .accessibilityHint(Text("Listens to the playing app for a moment so macOS asks for the permission"))
                }
            }
        }
    }

    private var statusSymbol: String {
        if audio.isChecking { return "ellipsis" }
        return switch settings.soundBarsAccess {
        case .allowed: "checkmark"
        case .denied: "xmark"
        case .unknown: audio.checkCouldNotListen ? "exclamationmark" : "info.circle"
        }
    }

    private var statusText: String {
        if audio.isChecking {
            return String(localized: "Listening for a moment… If macOS asks, click Allow.")
        }
        switch settings.soundBarsAccess {
        case .allowed:
            return String(localized: "The bars follow the music.")
        case .denied:
            return String(localized: "Not allowed — the bars use Gentle motion instead. Turn on PancakeNotch under System Audio Recording, then click Try Again.")
        case .unknown:
            if audio.checkCouldNotListen {
                return String(localized: "PancakeNotch couldn't listen to the app that's playing, so its bars use Gentle motion. Another app may work.")
            }
            return canListenNow
                ? String(localized: "Not checked yet. macOS asks the first time the bars listen, or click Ask Now.")
                : String(localized: "macOS will ask the first time music plays while the bars are showing.")
        }
    }

    private func tryAgain() {
        settings.soundBarsAccess = .unknown
        audio.checkAccess(track: center.track, isPractice: isPractice, settings: settings)
    }

    /// Privacy & Security, on the System Audio Recording list (its own anchor on newer macOS; on
    /// macOS 15 it's part of Screen & System Audio Recording).
    private static func openPrivacySettings() {
        var anchor = "Privacy_ScreenCapture"
        if #available(macOS 26, *) { anchor = "Privacy_AudioCapture" }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }
}

private struct AllowedBadge: View {
    var body: some View {
        Label(String(localized: "Allowed"), systemImage: "checkmark")
            .font(.app(size: 12, weight: .semibold))
            .foregroundStyle(AppPalette.primaryText)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(AppPalette.hover, in: Capsule())
            .overlay(PillOutline(color: AppPalette.hairline))
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
struct ModuleAbout: View {
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
    @Binding var showsSettings: Bool
    let learn: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let points = [
        String(localized: "Drop files, images, text and links on the notch"),
        String(localized: "Click an item for a big preview, or to edit a note or link"),
        String(localized: "Right-click to copy, share or AirDrop"),
        String(localized: "Drop files on Convert to turn them into another format"),
        String(localized: "A small tray in the notch shows the count when it's nearly full"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            NotchStage(
                behavior: preferences.notchBehavior,
                arrangement: arrangement,
                isActive: settings.isEnabled,
                // The example Shelf (files written to a temporary folder) only while the Shelf is on.
                practice: settings.isEnabled ? [.shelf] : [],
                inactiveHint: String(localized: "Turn on the Shelf to try it here."),
                activeHint: String(localized: "Hover or click the notch, then click an item to open it. These are example items."),
                badge: .practice
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
        .id(ModulesView.settingsAnchor("shelf"))
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
        if MissionControlDragGuard.isNeeded {
            SettingsRow(
                title: String(localized: "Dragging a file to the top"),
                subtitle: String(localized: "Open the Shelf stops the pointer just below the menu bar near the notch, so Mission Control doesn't start.")
            ) {
                MonochromeSegmented(
                    title: String(localized: "Dragging a file to the top"),
                    options: [
                        (.openShelf, String(localized: "Open the Shelf")),
                        (.allowMissionControl, String(localized: "Allow Mission Control")),
                    ],
                    selection: $settings.dragToTop
                )
            }
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
            title: String(localized: "Show the Shelf's count beside the notch"),
            subtitle: String(localized: "When it holds \(ShelfStore.nearlyFullCount) items or more, and for a moment after you drop something.")
        ) {
            Toggle(String(localized: "Show the Shelf's count beside the notch"), isOn: $settings.showsInEars)
                .labelsHidden()
        }
        ShelfConvertSettingsRows(settings: settings)
    }
}

/// Convert's settings (ADR-0038): the switch, then where files go, quality and Word → PDF while it's on.
private struct ShelfConvertSettingsRows: View {
    @Bindable var settings: ShelfSettings

    var body: some View {
        SettingsRow(
            title: String(localized: "Convert files"),
            subtitle: String(localized: "While you drag files to the notch, drop them on Convert to make a PDF, a JPEG, an MP4 and more. Or right-click an item on the Shelf.")
        ) {
            Toggle(String(localized: "Convert files"), isOn: $settings.convertEnabled)
                .labelsHidden()
        }
        if settings.convertEnabled {
            SettingsRow(
                title: String(localized: "Save converted files"),
                subtitle: destinationSubtitle
            ) {
                HStack(spacing: 8) {
                    if settings.convertDestination == .folder {
                        Button(String(localized: "Choose…", comment: "Picks the folder converted files go to")) { _ = chooseFolder() }
                    }
                    MonochromeSegmented(
                        title: String(localized: "Save converted files"),
                        options: [
                            (.nextToOriginal, String(localized: "Next to the original")),
                            (.folder, String(localized: "In a folder")),
                        ],
                        selection: destination
                    )
                }
            }
            SettingsRow(
                title: String(localized: "Quality"),
                subtitle: String(localized: "Smaller file shrinks big pictures to 2000 pixels and compresses more, so large photos can convert too.")
            ) {
                MonochromeSegmented(
                    title: String(localized: "Quality"),
                    options: ConvertQuality.allCases.map { ($0, $0.title) },
                    selection: $settings.convertQuality
                )
            }
            SettingsRow(
                title: String(localized: "Word to PDF (experimental)"),
                subtitle: String(localized: "Word documents can become PDFs too. The text and its styles are kept; pictures are left out.")
            ) {
                Toggle(String(localized: "Word to PDF (experimental)"), isOn: $settings.convertWordToPDF)
                    .labelsHidden()
            }
        }
    }

    private var destinationSubtitle: String {
        if settings.convertDestination == .folder, let folder = settings.convertFolder {
            return String(localized: "In \((folder.path as NSString).abbreviatingWithTildeInPath). They're added to the Shelf too.", comment: "Convert settings; a folder's path")
        }
        return String(localized: "They're added to the Shelf too. If the folder can't be written to, the Shelf keeps them.")
    }

    /// Choosing "In a folder" asks for the folder; cancelling keeps "Next to the original".
    private var destination: Binding<ShelfSettings.ConvertDestination> {
        Binding {
            settings.convertDestination
        } set: { value in
            guard value == .folder, settings.convertFolder == nil else {
                settings.convertDestination = value
                return
            }
            if chooseFolder() { settings.convertDestination = .folder }
        }
    }

    /// The folder picker; true when a folder was chosen.
    private func chooseFolder() -> Bool {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = settings.convertFolder ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        panel.prompt = String(localized: "Choose")
        panel.message = String(localized: "Choose where converted files go.")
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        settings.convertFolder = url
        settings.convertDestination = .folder
        return true
    }
}
