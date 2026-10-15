import Learn
import ModuleNowPlaying
import ModuleShelf
import NotchCore
import SwiftUI

/// Hands-on lessons: pick one, then do each step in the practice notch. Steps tick themselves when
/// the lesson notices you did them (ADR-0031). Nothing here touches the real notch or Shelf.
struct LearnView: View {
    let context: AppContext
    @Binding var lesson: LessonID

    private var progress: LearnProgress { context.progress }

    var body: some View {
        AppPage(
            title: String(localized: "Learn"),
            subtitle: String(localized: "Short lessons you do with your own hands, in a practice notch.")
        ) {
            HStack(spacing: 12) {
                ForEach(Lesson.all) { item in
                    LessonCard(lesson: item, isSelected: item.id == lesson, isDone: progress.isDone(item.id)) {
                        lesson = item.id
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)

            LessonPlayer(
                lesson: Lesson.lesson(lesson),
                behavior: context.preferences.notchBehavior,
                shortcuts: context.shortcuts,
                arrangement: context.arrangement,
                nextLesson: nextLesson,
                onFinish: { progress.markDone(lesson) },
                onNext: { if let next = nextLesson { lesson = next.id } }
            )
            .id(lesson)
        }
    }

    /// The first unfinished lesson after this one, for the "Next lesson" button.
    private var nextLesson: Lesson? {
        let all = Lesson.all
        guard let index = all.firstIndex(where: { $0.id == lesson }) else { return nil }
        return all[(index + 1)...].first { !progress.isDone($0.id) } ?? all[..<index].first { !progress.isDone($0.id) }
    }
}

/// A lesson to pick: its symbol, name, what it covers and whether it's done.
private struct LessonCard: View {
    let lesson: Lesson
    let isSelected: Bool
    let isDone: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: lesson.symbol)
                    .font(.app(size: 13, weight: .semibold))
                    .frame(width: 30, height: 30)
                    .background(AppPalette.selection, in: .rect(cornerRadius: 8, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(lesson.title)
                        .font(.app(size: 15, weight: .bold))
                    Text(lesson.summary)
                        .font(.app(size: 12.5))
                        .foregroundStyle(AppPalette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(isDone ? String(localized: "Done") : String(localized: "\(lesson.steps.count) steps"))
                        .font(.app(size: 11.5, weight: .semibold))
                        .foregroundStyle(isDone ? AppPalette.primaryText : AppPalette.secondaryText)
                        .padding(.top, 6)
                }
                Spacer(minLength: 8)
                if isDone {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.app(size: 17))
                        .accessibilityHidden(true)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(isSelected ? AppPalette.selection : isHovered ? AppPalette.hover : .clear, in: shape)
            .glassPanel()
            .overlay {
                if isSelected { shape.strokeBorder(Color.white.opacity(0.55), lineWidth: 1.5) }
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityHint(Text("Shows this lesson below."))
    }
}

/// One lesson being done: the practice notch on top (for the Shelf, with practice files to drag on
/// and a box to drag items out to), the steps below it. Used on Learn and in the welcome.
struct LessonPlayer: View {
    let lesson: Lesson
    let behavior: NotchBehavior
    let shortcuts: ShortcutController
    /// The user's module order and navigation, so the practice notch moves between modules like theirs.
    var arrangement: ModuleArrangement?
    var nextLesson: Lesson?
    var onFinish: () -> Void = {}
    var onNext: () -> Void = {}
    @State private var runner: LessonRunner
    @State private var practice: PracticeShelf?
    /// The pretend player (the Now Playing lesson), next to a practice Shelf to switch to.
    @State private var nowPlaying: PracticeNowPlaying?
    @State private var practiceFiles: [URL] = []
    @State private var shortcutHint: String?

    init(
        lesson: Lesson,
        behavior: NotchBehavior,
        shortcuts: ShortcutController,
        arrangement: ModuleArrangement? = nil,
        nextLesson: Lesson? = nil,
        onFinish: @escaping () -> Void = {},
        onNext: @escaping () -> Void = {}
    ) {
        self.lesson = lesson
        self.behavior = behavior
        self.shortcuts = shortcuts
        self.arrangement = arrangement
        self.nextLesson = nextLesson
        self.onFinish = onFinish
        self.onNext = onNext
        _runner = State(initialValue: LessonRunner(lesson: lesson))
    }

    private var usesShelf: Bool { lesson.id == .shelf }
    private var usesNowPlaying: Bool { lesson.id == .nowPlaying }

    /// What the practice notch holds: the pretend player first (Now Playing lesson), then the Shelf.
    private var practiceModules: [any NotchModule] {
        [nowPlaying?.module as (any NotchModule)?, practice?.module].compactMap { $0 }
    }

    private var hint: String? {
        if usesShelf { return String(localized: "This is a practice Shelf: nothing here touches your real one.") }
        if usesNowPlaying { return String(localized: "A practice player: the songs are made up and silent, and your music isn't touched.") }
        return nil
    }

    var body: some View {
        VStack(spacing: 0) {
            NotchStage(
                behavior: behavior,
                arrangement: arrangement,
                modules: practiceModules,
                activeHint: hint,
                onStateChange: notchChanged
            )
            .background(Color.black)

            if usesShelf, practice != nil {
                AppPalette.hairline.frame(height: 1)
                PracticeTray(files: practiceFiles)
            }

            AppPalette.hairline.frame(height: 1)
            if runner.isFinished {
                finished
            } else {
                steps
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .glassPanel()
        .onAppear(perform: start)
        .onDisappear(perform: stop)
        .onChange(of: runner.stepIndex) { stepChanged() }
        .onChange(of: shortcuts.shortcut != nil) { stepChanged() }
        .onChange(of: runner.justTicked) { _, ticked in
            guard let ticked, let step = lesson.steps.first(where: { $0.id == ticked }) else { return }
            AccessibilityNotification.Announcement(String(localized: "Done: \(step.title)")).post()
        }
    }

    // MARK: Steps

    private var steps: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                SectionLabel(title: String(localized: "Step \(min(runner.stepIndex + 1, lesson.steps.count)) of \(lesson.steps.count)"))
                Spacer(minLength: 8)
                Button(String(localized: "Back"), action: runner.back)
                    .disabled(runner.stepIndex == 0)
                Button(String(localized: "Skip Step"), action: skip)
                    .accessibilityHint(Text("Moves on without doing this step."))
                // Ticks the step by hand: drags and hovers need a pointer, this doesn't. The shortcut
                // step has its own recorder.
                if lesson.steps.indices.contains(runner.stepIndex), case let current = lesson.steps[runner.stepIndex],
                   current.signal != .shortcutSet {
                    Button(String(localized: "Mark as Done")) { runner.receive(current.signal) }
                        .accessibilityHint(Text("Ticks this step off, as if you'd done it."))
                }
            }
            .padding(.bottom, 12)
            ForEach(Array(lesson.steps.enumerated()), id: \.element.id) { index, step in
                StepRow(
                    step: step,
                    number: index + 1,
                    status: status(of: step, at: index),
                    markDone: { runner.receive(step.signal) }
                ) {
                    if step.signal == .shortcutSet, index == runner.stepIndex {
                        HStack(spacing: 10) {
                            ShortcutRecorder(controller: shortcuts, hint: $shortcutHint)
                            if let shortcutHint {
                                Text(shortcutHint)
                                    .font(.app(size: 12))
                                    .foregroundStyle(AppPalette.secondaryText)
                            }
                        }
                        .padding(.top, 8)
                    }
                }
            }
        }
        .padding(AppMetrics.cardInset)
    }

    private func status(of step: LessonStep, at index: Int) -> StepStatus {
        if runner.ticked.contains(step.id) { return .done }
        if runner.skipped.contains(step.id) { return .skipped }
        return index == runner.stepIndex ? .current : .upcoming
    }

    private var finished: some View {
        HStack(spacing: 14) {
            Image(systemName: "checkmark")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.black)
                .frame(width: 42, height: 42)
                .background(.white, in: .rect(cornerRadius: 11, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(runner.isComplete ? String(localized: "Lesson done") : String(localized: "End of the lesson"))
                    .font(.app(size: 17, weight: .bold))
                Text(runner.isComplete
                    ? String(localized: "Nicely done. You can do it again any time.")
                    : String(localized: "You skipped a step, so this lesson isn't checked off yet. Do it again whenever you like."))
                    .font(.app(size: 12.5))
                    .foregroundStyle(AppPalette.secondaryText)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 12)
            Button(String(localized: "Do again"), action: restart)
            if let nextLesson {
                Button(String(localized: "Next: \(nextLesson.title)"), action: onNext)
                    .buttonStyle(ProminentPillButtonStyle())
            }
        }
        .padding(AppMetrics.cardInset)
    }

    // MARK: Lesson logic

    private func start() {
        // Only a lesson done without skipping (optional steps aside) gets its checkmark.
        runner.onFinish = { [weak runner] in if runner?.isComplete == true { onFinish() } }
        if practice == nil { makePractice() }
        stepChanged()
    }

    private func stop() {
        runner.onFinish = nil
        practice?.close()
        practice = nil
        nowPlaying?.close()
        nowPlaying = nil
    }

    private func restart() {
        stop()
        runner.restart()
        start()
    }

    private func makePractice() {
        if usesNowPlaying {
            let player = PracticeNowPlaying()
            let signals = NowPlayingSignals(runner: runner)
            player.module.onEvent = { event in signals.handle(event) }
            nowPlaying = player
        }
        // The basics lesson shows example items; the Shelf lesson starts empty, for your drops.
        let shelf = PracticeShelf(seeded: !usesShelf)
        let signals = ShelfSignals(runner: runner)
        shelf.module.onEvent = { event in signals.handle(event) }
        practice = shelf
        practiceFiles = usesShelf ? shelf.practiceFiles() : []
    }

    private func skip() {
        runner.skip()
    }

    /// Opening counts however it happened; shrinking and closing only when a click did it, not
    /// the pointer leaving or the Shelf's short "added" moment after a drop.
    private func notchChanged(_ state: NotchState, byClick: Bool) {
        switch state {
        case .expanded: runner.receive(.notchOpened)
        case .compact: if byClick { runner.receive(.notchShrunk) }
        case .closed: if byClick { runner.receive(.notchClosed) }
        }
    }

    /// Makes the current step doable: a shortcut that's already set counts, and Shelf steps that need
    /// items on the practice Shelf (say the first step was skipped) get practice files put on it.
    private func stepChanged() {
        guard let step = runner.currentStep else { return }
        if step.signal == .shortcutSet, shortcuts.shortcut != nil {
            runner.receive(.shortcutSet)
        }
        // "Play it again" needs a paused song (say the pause step was skipped).
        if step.signal == .musicPlayed, let center = nowPlaying?.module.center, center.track?.isPlaying == true {
            center.send(.pause)
        }
        guard usesShelf, let practice else { return }
        let needed = switch step.signal {
        case .shelfSeveralSelected: 2
        case .shelfItemOpened, .shelfItemClosed, .shelfMenuOpened, .shelfDraggedOut, .shelfCleared: 1
        default: 0
        }
        let store = practice.module.store
        guard store.items.count < needed else { return }
        let missing = practice.practiceFiles().prefix(needed - store.items.count)
        _ = store.add(missing.map { .file($0, owned: false) }, duplicates: .addAgain)
    }
}

private enum StepStatus { case done, skipped, current, upcoming }

/// Turns what happens in the practice player into lesson signals. A class the module's callback holds,
/// so the callback doesn't keep the page alive.
@MainActor
private final class NowPlayingSignals {
    private weak var runner: LessonRunner?

    init(runner: LessonRunner) {
        self.runner = runner
    }

    func handle(_ event: NowPlayingEvent) {
        guard let runner else { return }
        switch event {
        case .paused: runner.receive(.musicPaused)
        case .played: runner.receive(.musicPlayed)
        case .skippedForward, .skippedBack: runner.receive(.musicSkipped)
        case .seeked: runner.receive(.musicSeeked)
        case .shuffleChanged, .repeatChanged: runner.receive(.musicModeChanged)
        case .artworkClicked: runner.receive(.musicArtworkClicked)
        case .switchedAway: runner.receive(.moduleSwitched)
        }
    }
}

/// Turns what happens on the practice Shelf into lesson signals. A class the Shelf's callback holds,
/// so the callback doesn't keep the page (and through it the practice Shelf) alive.
@MainActor
private final class ShelfSignals {
    private weak var runner: LessonRunner?
    /// The item count at the last change, to tell an addition from other saves.
    private var itemCount = 0

    init(runner: LessonRunner) {
        self.runner = runner
    }

    func handle(_ event: ShelfEvent) {
        guard let runner else { return }
        switch event {
        case .itemsChanged(let count):
            if count > itemCount { runner.receive(.shelfItemAdded) }
            itemCount = count
        case .detailOpened: runner.receive(.shelfItemOpened)
        case .detailClosed: runner.receive(.shelfItemClosed)
        case .menuOpened: runner.receive(.shelfMenuOpened)
        case .dragOutEnded(let accepted): if accepted { runner.receive(.shelfDraggedOut) }
        case .selectionChanged(let count): if count >= 2 { runner.receive(.shelfSeveralSelected) }
        case .cleared: runner.receive(.shelfCleared)
        case .menuClosed, .airDropped: break
        }
    }
}

/// One step in the list: done ✓, skipped, the current one (highlighted, with how to do it) or still to come.
private struct StepRow<Extra: View>: View {
    let step: LessonStep
    let number: Int
    let status: StepStatus
    /// Ticks the step without doing it, for VoiceOver users (drags are hard without a pointer).
    let markDone: () -> Void
    @ViewBuilder var extra: Extra
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            badge
                .frame(width: 26, height: 26)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Image(systemName: step.symbol)
                        .font(.app(size: 12, weight: .semibold))
                        .foregroundStyle(AppPalette.secondaryText)
                        .accessibilityHidden(true)
                    Text(step.title)
                        .font(.app(size: 13.5, weight: status == .current ? .bold : .medium))
                        .foregroundStyle(status == .upcoming ? AppPalette.secondaryText : AppPalette.primaryText)
                        .strikethrough(status == .skipped, color: AppPalette.tertiaryText)
                }
                if status == .current {
                    Text(step.detail)
                        .font(.app(size: 12.5))
                        .foregroundStyle(AppPalette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    extra
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, status == .current ? 12 : 7)
        .background {
            if status == .current {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(AppPalette.selection)
                    .overlay {
                        RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(AppPalette.hairline)
                    }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(accessibilityLabel))
        .accessibilityActions {
            if status == .current {
                Button(String(localized: "Mark as Done"), action: markDone)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: status)
    }

    @ViewBuilder
    private var badge: some View {
        switch status {
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .font(.app(size: 19))
                .foregroundStyle(.white)
        case .skipped:
            Image(systemName: "arrow.uturn.forward.circle")
                .font(.app(size: 19))
                .foregroundStyle(AppPalette.tertiaryText)
        case .current, .upcoming:
            Text(number.formatted())
                .font(.app(size: 12, weight: .bold))
                .foregroundStyle(status == .current ? Color.black : AppPalette.secondaryText)
                .frame(width: 22, height: 22)
                .background(Circle().fill(status == .current ? Color.white : Color.clear))
                .overlay { if status == .upcoming { Circle().strokeBorder(AppPalette.hairlineStrong) } }
        }
    }

    private var accessibilityLabel: String {
        switch status {
        case .done: String(localized: "Step \(number), \(step.title): done")
        case .skipped: String(localized: "Step \(number), \(step.title): skipped")
        case .current: String(localized: "Step \(number), now: \(step.title). \(step.detail)")
        case .upcoming: String(localized: "Step \(number), \(step.title): still to do")
        }
    }
}

/// Practice files to drag onto the notch, and a box to drag Shelf items out to.
private struct PracticeTray: View {
    let files: [URL]
    @State private var isTargeted = false
    @State private var received = 0

    var body: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(title: String(localized: "Practice files"))
                HStack(spacing: 10) {
                    ForEach(files, id: \.self) { url in
                        PracticeFileChip(url: url)
                    }
                }
            }
            Spacer(minLength: 12)
            dropBox
        }
        .padding(.horizontal, AppMetrics.cardInset)
        .padding(.vertical, 16)
    }

    /// Takes whatever is dragged out of the practice Shelf and keeps none of it.
    private var dropBox: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return VStack(spacing: 6) {
            Image(systemName: received > 0 ? "checkmark" : "tray.and.arrow.up")
                .font(.app(size: 16, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
            Text(received > 0 ? String(localized: "Got it") : String(localized: "Drag items out to here"))
                .font(.app(size: 11.5, weight: .medium))
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(isTargeted ? AppPalette.primaryText : AppPalette.secondaryText)
        .frame(width: 150, height: 76)
        .background(isTargeted ? AppPalette.selection : .clear, in: shape)
        .overlay {
            shape.strokeBorder(isTargeted ? Color.white.opacity(0.6) : AppPalette.hairlineStrong, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        }
        .onDrop(of: [.fileURL, .url, .utf8PlainText, .image], isTargeted: $isTargeted) { _ in
            received += 1
            return true
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(received > 0
            ? String(localized: "Box for items dragged out of the practice Shelf. Got it.")
            : String(localized: "Box to drag items out of the practice Shelf to")))
    }
}

/// A practice file you can pick up and drop on the practice notch.
private struct PracticeFileChip: View {
    let url: URL
    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 5) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .frame(width: 38, height: 38)
            Text(url.lastPathComponent)
                .font(.app(size: 11, weight: .medium))
                .foregroundStyle(AppPalette.secondaryText)
                .lineLimit(1)
        }
        .frame(width: 76, height: 70)
        .background(isHovered ? AppPalette.hover : .clear, in: .rect(cornerRadius: 10, style: .continuous))
        .contentShape(.rect(cornerRadius: 10))
        .onHover { isHovered = $0 }
        .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
        .help(Text("Drag onto the notch"))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Practice file \(url.lastPathComponent)"))
        .accessibilityHint(Text("Drag it onto the notch above."))
    }
}
