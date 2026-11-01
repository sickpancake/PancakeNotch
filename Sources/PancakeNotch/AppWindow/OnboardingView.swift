import Learn
import NotchCore
import NowPlayingCore
import SwiftUI

/// The first-run welcome (ADR-0020): fills the window, without the sidebar, and covers only the
/// notch basics. Welcome → the basics lesson → try the real notch → play a song → your setup
/// (launch at login, updates) → where the lessons live. Opens by itself once; closing the window
/// pauses it at the current step. "Show Welcome Again" in About or Help brings it back.
struct OnboardingView: View {
    enum Step: Int, CaseIterable {
        case welcome, basics, realNotch, music, setup, learn
    }

    let context: AppContext
    @State private var step: Step
    /// Real notch opens counted when the "try the real one" step appeared.
    @State private var opensAtStart: Int?
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var needsApproval = LaunchAtLogin.needsApproval
    @State private var launchError: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Environment(\.openURL) private var openURL

    /// Starts at `step`, or where the welcome was paused.
    init(context: AppContext, step: Step? = nil) {
        self.context = context
        _step = State(initialValue: step ?? Step(rawValue: context.progress.onboardingStep) ?? .welcome)
    }

    private var preferences: Preferences { context.preferences }
    private var progress: LearnProgress { context.progress }
    private var stats: UsageStats { context.stats }
    private var nowPlaying: NowPlayingCenter { context.nowPlaying }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView {
                page
                    .id(step)
                    .transition(.opacity)
                    .frame(maxWidth: 680)
                    .padding(.horizontal, 40)
                    .padding(.vertical, 24)
                    .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            bottomBar
        }
        .background(AppPalette.background)
        .onAppear { progress.onboardingShown = true }
        .onChange(of: step) { _, step in progress.onboardingStep = step.rawValue }
    }

    // MARK: Chrome

    /// Room for the traffic lights, the step dots and a way out.
    private var topBar: some View {
        HStack {
            Spacer()
            HStack(spacing: 7) {
                ForEach(Step.allCases, id: \.self) { item in
                    Capsule()
                        .fill(item == step ? Color.white : item.rawValue < step.rawValue ? AppPalette.secondaryText : AppPalette.rail)
                        .frame(width: item == step ? 18 : 6, height: 6)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Step \(step.rawValue + 1) of \(Step.allCases.count)"))
            Spacer()
        }
        .overlay(alignment: .trailing) {
            if step != .learn {
                Button(String(localized: "Skip Welcome"), action: finish)
                    .buttonStyle(.plain)
                    .font(.app(size: 12.5, weight: .medium))
                    .foregroundStyle(AppPalette.secondaryText)
                    .accessibilityHint(Text("Goes straight to the app. You can see the welcome again from About or Help."))
            }
        }
        .padding(.horizontal, 24)
        .frame(height: 52)
        .padding(.top, 8)
    }

    private var bottomBar: some View {
        HStack {
            if step != .welcome {
                Button(String(localized: "Back")) { go(to: Step(rawValue: step.rawValue - 1)) }
            }
            Spacer()
            if step == .learn {
                Button(String(localized: "Open Learn"), action: openLearn)
                    .accessibilityHint(Text("Ends the welcome and opens the next lesson on the Learn page."))
                Button(String(localized: "Done"), action: finish)
                    .buttonStyle(ProminentPillButtonStyle())
                    .keyboardShortcut(.defaultAction)
            } else {
                Button(continueTitle) { go(to: Step(rawValue: step.rawValue + 1)) }
                    .buttonStyle(ProminentPillButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 18)
        .overlay(alignment: .top) { AppPalette.hairline.frame(height: 1) }
    }

    private var continueTitle: String {
        switch step {
        case .welcome: String(localized: "Get Started")
        case .basics: progress.isDone(.basics) ? String(localized: "Continue") : String(localized: "Skip for Now")
        case .realNotch: realNotchOpened ? String(localized: "Continue") : String(localized: "Skip for Now")
        case .music: songFound ? String(localized: "Continue") : String(localized: "Skip for Now")
        default: String(localized: "Continue")
        }
    }

    private func go(to next: Step?) {
        guard let next else { return }
        withAnimation(.easeInOut(duration: reduceMotion ? 0.15 : 0.25)) { step = next }
    }

    private func finish() {
        progress.finishWelcome()
    }

    /// Ends the welcome on Learn, at the first lesson not done yet.
    private func openLearn() {
        let navigation = context.navigation
        navigation.lesson = LessonID.allCases.first { !progress.isDone($0) } ?? .basics
        navigation.sectionAfterWelcome = .learn
        finish()
    }

    // MARK: Pages

    @ViewBuilder
    private var page: some View {
        switch step {
        case .welcome: welcome
        case .basics: basics
        case .realNotch: realNotch
        case .music: music
        case .setup: setup
        case .learn: learn
        }
    }

    private var welcome: some View {
        VStack(spacing: 0) {
            NotchStage(behavior: preferences.notchBehavior, practice: [.shelf], activeHint: preferences.openOnClickOnly ? String(localized: "Go on, click it.") : String(localized: "Go on, hover it."))
                .background(Color.black)
                .clipShape(.rect(cornerRadius: 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(AppPalette.hairline)
                }
            NotchGlyph(size: 40)
                .padding(.top, 32)
            heading(
                String(localized: "Welcome to PancakeNotch"),
                String(localized: "Your MacBook's notch, put to work. Let's spend a minute on the basics: you'll try each thing yourself.")
            )
        }
    }

    private var basics: some View {
        VStack(alignment: .leading, spacing: 20) {
            heading(
                String(localized: "The notch basics"),
                String(localized: "This is a practice notch. Do each step and it ticks itself off.")
            )
            LessonPlayer(
                lesson: .basics,
                behavior: preferences.notchBehavior,
                shortcuts: context.shortcuts,
                onFinish: { progress.markDone(.basics) }
            )
        }
    }

    private var realNotchOpened: Bool {
        guard let opensAtStart else { return false }
        return stats.opensTotal > opensAtStart
    }

    private var realNotch: some View {
        VStack(spacing: 0) {
            heading(
                String(localized: "Now try the real one"),
                String(localized: "Move the pointer up to the notch at the top of your screen and rest it there.")
            )
            VStack(spacing: 14) {
                Image(systemName: realNotchOpened ? "checkmark" : "cursorarrow.rays")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(realNotchOpened ? Color.black : AppPalette.primaryText)
                    .frame(width: 58, height: 58)
                    .background(realNotchOpened ? Color.white : AppPalette.selection, in: .rect(cornerRadius: 15, style: .continuous))
                    .contentTransition(.symbolEffect(.replace))
                    .accessibilityHidden(true)
                Text(realNotchOpened ? String(localized: "It works. Nicely done!") : String(localized: "Waiting for the notch to open…"))
                    .font(.app(size: 15, weight: .semibold))
                if !preferences.notchEnabled {
                    Text(String(localized: "The notch is switched off."))
                        .font(.app(size: 12.5))
                        .foregroundStyle(AppPalette.secondaryText)
                    Button(String(localized: "Turn It On")) { preferences.notchEnabled = true }
                } else if !realNotchOpened {
                    Text(String(localized: "Nothing happening? The notch is on your MacBook's own screen. If the pointer is on another display, move it across first."))
                        .font(.app(size: 12.5))
                        .foregroundStyle(AppPalette.secondaryText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity)
            .glassPanel()
            .padding(.top, 28)
            .animation(.easeInOut(duration: reduceMotion ? 0.15 : 0.25), value: realNotchOpened)
            .accessibilityElement(children: .combine)
        }
        .onAppear { if opensAtStart == nil { opensAtStart = stats.opensTotal } }
        .onChange(of: realNotchOpened) { _, opened in
            if opened { AccessibilityNotification.Announcement(String(localized: "The notch opened. It works.")).post() }
        }
    }

    // MARK: Play a song

    /// Something is playing (or paused) in an app Now Playing can see.
    private var songFound: Bool {
        context.nowPlayingSettings.isEnabled && nowPlaying.track != nil
    }

    private var music: some View {
        VStack(spacing: 0) {
            heading(
                String(localized: "Play a song"),
                String(localized: "Play something in Music, Spotify or your browser. It shows up beside the notch, and in it when you open it.")
            )
            VStack(spacing: 14) {
                if songFound, let track = nowPlaying.track {
                    FoundSong(track: track, artwork: nowPlaying.artwork)
                    Text(String(localized: "Found it. Now Playing works."))
                        .font(.app(size: 15, weight: .semibold))
                } else {
                    Image(systemName: "music.note")
                        .font(.system(size: 22, weight: .bold))
                        .frame(width: 58, height: 58)
                        .background(AppPalette.selection, in: .rect(cornerRadius: 15, style: .continuous))
                        .accessibilityHidden(true)
                    musicStatus
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity)
            .glassPanel()
            .padding(.top, 28)
            .animation(.easeInOut(duration: reduceMotion ? 0.15 : 0.25), value: songFound)
            .accessibilityElement(children: .contain)
        }
        .onChange(of: songFound) { _, found in
            if found { AccessibilityNotification.Announcement(String(localized: "Found the song. Now Playing works.")).post() }
        }
    }

    /// Waiting for a song, or why one can't show, with the fix that applies.
    @ViewBuilder
    private var musicStatus: some View {
        if !context.nowPlayingSettings.isEnabled {
            Text(String(localized: "Now Playing is switched off."))
                .font(.app(size: 15, weight: .semibold))
            Button(String(localized: "Turn It On")) { context.nowPlayingSettings.isEnabled = true }
        } else {
            switch nowPlaying.connection {
            case .limited:
                Text(String(localized: "Only Music and Spotify can show right now."))
                    .font(.app(size: 15, weight: .semibold))
                hint(String(localized: "macOS isn't sharing what other apps play. Trying again often fixes it."))
                HStack(spacing: 8) {
                    Button(String(localized: "Try Again")) { nowPlaying.retryConnection() }
                    helpButton(.musicNotDetected)
                }
            case .unavailable:
                Text(String(localized: "PancakeNotch can't see what's playing."))
                    .font(.app(size: 15, weight: .semibold))
                hint(String(localized: "Trying again often fixes it. You can also skip this for now."))
                HStack(spacing: 8) {
                    Button(String(localized: "Try Again")) { nowPlaying.retryConnection() }
                    helpButton(.musicNotDetected)
                }
            case .starting, .connected, .practice:
                Text(String(localized: "Waiting for a song…"))
                    .font(.app(size: 15, weight: .semibold))
                hint(String(localized: "Nothing showing up? Make sure it's playing on this Mac, then give it a second."))
                if nowPlaying.needsAutomationPermission {
                    Button(String(localized: "Allow Control…")) { HelpLinks.openAutomationSettings() }
                }
                helpButton(.musicNotDetected)
            }
        }
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.app(size: 12.5))
            .foregroundStyle(AppPalette.secondaryText)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// The website's answer for a topic (the app's Help page sits behind the welcome).
    private func helpButton(_ topic: HelpTopic) -> some View {
        Button { openURL(HelpLinks.url(topic)) } label: {
            Label(String(localized: "Get Help"), systemImage: "arrow.up.right")
                .labelStyle(TrailingIconLabelStyle())
        }
    }

    // MARK: Your setup

    private var setup: some View {
        @Bindable var updates = context.updates
        return VStack(spacing: 0) {
            heading(
                String(localized: "Your setup"),
                updates.isAvailable
                    ? String(localized: "Two quick choices. You can change both later in General.")
                    : String(localized: "One quick choice. You can change it later in General.")
            )
            SettingsCard(footer: launchError) {
                SettingsRow(
                    title: String(localized: "Launch at login"),
                    subtitle: String(localized: "PancakeNotch opens by itself when you log in, so the notch is always there.")
                ) {
                    Toggle(String(localized: "Launch at login"), isOn: $launchAtLogin)
                        .labelsHidden()
                }
                if needsApproval {
                    SettingsRow(
                        title: String(localized: "Waiting for your approval"),
                        subtitle: String(localized: "Allow PancakeNotch in Login Items to finish turning this on.")
                    ) {
                        Button(String(localized: "Open Login Items")) { LaunchAtLogin.openSystemSettings() }
                    }
                }
                if updates.isAvailable {
                    SettingsRow(
                        title: String(localized: "Check for updates automatically"),
                        subtitle: String(localized: "Once a day it asks GitHub for a newer version, and asks you before installing. Nothing about you is sent.")
                    ) {
                        Toggle(String(localized: "Check for updates automatically"), isOn: $updates.automaticallyChecks)
                            .labelsHidden()
                    }
                }
            }
            .padding(.top, 28)
            .onChange(of: launchAtLogin) { _, enabled in
                guard enabled != LaunchAtLogin.isEnabled else { return }
                launchError = LaunchAtLogin.apply(enabled)
                launchAtLogin = LaunchAtLogin.isEnabled
                needsApproval = LaunchAtLogin.needsApproval
            }
            // Approved or turned off in System Settings meanwhile: show what's true now.
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                launchAtLogin = LaunchAtLogin.isEnabled
                needsApproval = LaunchAtLogin.needsApproval
            }
        }
    }

    private var learn: some View {
        VStack(spacing: 0) {
            heading(
                String(localized: "More lessons live in Learn"),
                String(localized: "Learn the Shelf and every module that comes later, whenever you like. Find it in the sidebar, just below Modules.")
            )
            SidebarPeek()
                .padding(.top, 28)
        }
    }

    private func heading(_ title: String, _ detail: String, alignment: HorizontalAlignment = .center) -> some View {
        VStack(alignment: alignment, spacing: 8) {
            Text(title)
                .font(.app(size: 28, weight: .bold))
                .kerning(-0.4)
                .accessibilityAddTraits(.isHeader)
            Text(detail)
                .font(.app(size: 14))
                .foregroundStyle(AppPalette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .multilineTextAlignment(alignment == .center ? .center : .leading)
        .frame(maxWidth: .infinity, alignment: alignment == .center ? .center : .leading)
        .padding(.top, alignment == .center ? 20 : 0)
    }
}

/// A small drawing of the sidebar with Learn picked out, so people know where to look.
private struct SidebarPeek: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            row(String(localized: "Home"), "house")
            row(String(localized: "Modules"), "square.grid.2x2")
            row(String(localized: "Learn"), "graduationcap", highlighted: true)
            row(String(localized: "General"), "gearshape")
                .opacity(0.5)
        }
        .padding(12)
        .frame(width: 240)
        .background(AppPalette.sidebar, in: .rect(cornerRadius: 14, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(AppPalette.hairline) }
        .accessibilityHidden(true)
    }

    private func row(_ title: String, _ symbol: String, highlighted: Bool = false) -> some View {
        HStack(spacing: 11) {
            Image(systemName: symbol)
                .font(.app(size: 13, weight: .medium))
                .frame(width: 18)
            Text(title)
                .font(.app(size: 13.5, weight: highlighted ? .semibold : .medium))
            Spacer(minLength: 0)
            if highlighted {
                Image(systemName: "arrow.left")
                    .font(.app(size: 12, weight: .bold))
            }
        }
        .foregroundStyle(highlighted ? AppPalette.primaryText : AppPalette.secondaryText)
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(highlighted ? AppPalette.selection : .clear, in: .rect(cornerRadius: 9, style: .continuous))
        .overlay {
            if highlighted { RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Color.white.opacity(0.5)) }
        }
    }
}

/// The song Now Playing found: its artwork (the one colour allowed) and its title.
private struct FoundSong: View {
    let track: NowPlayingTrack
    let artwork: NSImage?

    var body: some View {
        HStack(spacing: 14) {
            Group {
                if let artwork {
                    Image(nsImage: artwork)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: "music.note")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(AppPalette.secondaryText)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(AppPalette.selection)
                }
            }
            .frame(width: 58, height: 58)
            .clipShape(.rect(cornerRadius: 12, style: .continuous))
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(track.title)
                    .font(.app(size: 14, weight: .semibold))
                    .lineLimit(1)
                if !track.artist.isEmpty {
                    Text(track.artist)
                        .font(.app(size: 12.5))
                        .foregroundStyle(AppPalette.secondaryText)
                        .lineLimit(1)
                }
            }
            Image(systemName: "checkmark")
                .font(.app(size: 11, weight: .bold))
                .foregroundStyle(Color.black)
                .frame(width: 22, height: 22)
                .background(Color.white, in: .circle)
                .accessibilityHidden(true)
        }
        .padding(12)
        .padding(.trailing, 4)
        .background(AppPalette.hover, in: .rect(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
