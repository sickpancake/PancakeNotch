import Learn
import NotchCore
import SwiftUI

/// The first-run welcome (ADR-0020): fills the window, without the sidebar, and covers only the
/// notch basics. Welcome → the basics lesson → try the real notch → launch at login → where the
/// lessons live. Shown once; "Show welcome again" in About brings it back.
struct OnboardingView: View {
    enum Step: Int, CaseIterable {
        case welcome, basics, realNotch, launch, learn
    }

    @Bindable var preferences: Preferences
    let shortcuts: ShortcutController
    let stats: UsageStats
    let progress: LearnProgress
    @State private var step: Step
    /// Real notch opens counted when the "try the real one" step appeared.
    @State private var opensAtStart: Int?
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var needsApproval = LaunchAtLogin.needsApproval
    @State private var launchError: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(preferences: Preferences, shortcuts: ShortcutController, stats: UsageStats, progress: LearnProgress, step: Step = .welcome) {
        self.preferences = preferences
        self.shortcuts = shortcuts
        self.stats = stats
        self.progress = progress
        _step = State(initialValue: step)
    }

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
                Button(String(localized: "Skip welcome"), action: finish)
                    .buttonStyle(.plain)
                    .font(.app(size: 12.5, weight: .medium))
                    .foregroundStyle(AppPalette.secondaryText)
                    .accessibilityHint(Text("Goes straight to the app. You can see the welcome again from About."))
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
        default: String(localized: "Continue")
        }
    }

    private func go(to next: Step?) {
        guard let next else { return }
        withAnimation(.easeInOut(duration: reduceMotion ? 0.15 : 0.25)) { step = next }
    }

    private func finish() {
        progress.onboardingDone = true
    }

    // MARK: Pages

    @ViewBuilder
    private var page: some View {
        switch step {
        case .welcome: welcome
        case .basics: basics
        case .realNotch: realNotch
        case .launch: launch
        case .learn: learn
        }
    }

    private var welcome: some View {
        VStack(spacing: 0) {
            NotchStage(behavior: preferences.notchBehavior, practice: [.shelf], activeHint: String(localized: "Go on, hover it."))
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
                shortcuts: shortcuts,
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
                    Text("The notch is switched off.")
                        .font(.app(size: 12.5))
                        .foregroundStyle(AppPalette.secondaryText)
                    Button(String(localized: "Turn It On")) { preferences.notchEnabled = true }
                } else if !realNotchOpened {
                    Text("Nothing happening? The notch lives on your MacBook's built-in screen. If the pointer is on another display, move it across first.")
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
            .accessibilityElement(children: .combine)
        }
        .onAppear { if opensAtStart == nil { opensAtStart = stats.opensTotal } }
        .onChange(of: realNotchOpened) { _, opened in
            if opened { AccessibilityNotification.Announcement(String(localized: "The notch opened. It works.")).post() }
        }
    }

    private var launch: some View {
        VStack(spacing: 0) {
            heading(
                String(localized: "Start with your Mac?"),
                String(localized: "PancakeNotch can open by itself when you log in, so the notch is always there.")
            )
            SettingsCard(footer: launchError) {
                SettingsRow(
                    title: String(localized: "Launch at login"),
                    subtitle: String(localized: "You can change this later in General.")
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
            }
            .padding(.top, 28)
            .onChange(of: launchAtLogin) { _, enabled in
                guard enabled != LaunchAtLogin.isEnabled else { return }
                launchError = LaunchAtLogin.apply(enabled)
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
