import AppKit
import SwiftUI

/// The app window's colours. The window is always dark, like the notch itself, and strictly
/// monochrome: black, white and greys, no accent colour (ADR-0029). Lines and empty control
/// tracks get stronger with Increase Contrast.
enum AppPalette {
    /// The window: deep black, a touch lighter than the notch so the notch art still reads.
    static let background = gray(0.035)
    static let sidebar = gray(0.058)

    /// Glass panels: a faint white fill with a hairline border and a soft top highlight.
    static let glass = color(.white.withAlphaComponent(0.045), highContrast: .white.withAlphaComponent(0.08))
    static let glassHighlight = Color.white.opacity(0.05)
    static let hairline = color(.white.withAlphaComponent(0.085), highContrast: .white.withAlphaComponent(0.5))
    static let hairlineStrong = color(.white.withAlphaComponent(0.16), highContrast: .white.withAlphaComponent(0.6))

    static let selection = Color.white.opacity(0.1)
    static let hover = Color.white.opacity(0.055)
    static let pressed = Color.white.opacity(0.13)

    /// Text. Secondary text stays at 64% white or more so it reads comfortably on black.
    static let primaryText = Color.white
    static let secondaryText = color(.white.withAlphaComponent(0.64), highContrast: .white.withAlphaComponent(0.85))
    /// Only for decoration and hints that repeat something said elsewhere.
    static let tertiaryText = color(.white.withAlphaComponent(0.46), highContrast: .white.withAlphaComponent(0.75))

    /// Filled parts of controls: the "on" switch track, the slider's filled side.
    static let ink = gray(0.96)
    /// Empty parts of controls: the "off" switch track, the slider's rail.
    static let rail = color(.white.withAlphaComponent(0.17), highContrast: .white.withAlphaComponent(0.5))
    /// The switch knob when on: black, so it reads against the white track.
    static let knobOn = gray(0.06)
    static let knobOff = gray(0.9)

    private static func gray(_ white: CGFloat) -> Color {
        Color(nsColor: NSColor(white: white, alpha: 1))
    }

    /// A colour with a stronger variant for Increase Contrast.
    static func color(_ normal: NSColor, highContrast: NSColor? = nil) -> Color {
        guard let highContrast else { return Color(nsColor: normal) }
        return Color(nsColor: NSColor(name: nil) { appearance in
            switch appearance.bestMatch(from: [.darkAqua, .accessibilityHighContrastDarkAqua, .aqua, .accessibilityHighContrastAqua]) {
            case .accessibilityHighContrastDarkAqua, .accessibilityHighContrastAqua: highContrast
            default: normal
            }
        })
    }
}

/// Shared measurements, so edges line up from card to card and page to page.
enum AppMetrics {
    /// The gap between a card's edge and its content. Section headers and footnotes outside a
    /// card use it too, so they start on the same line as the text inside.
    static let cardInset: CGFloat = 20
}

extension View {
    /// A soft grey "glass" panel: faint white fill, a highlight fading down from the top edge and
    /// a hairline border that is brighter at the top, as if lit from above.
    func glassPanel(cornerRadius: CGFloat = 16) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return background {
            shape
                .fill(AppPalette.glass)
                .overlay {
                    shape.fill(LinearGradient(
                        colors: [AppPalette.glassHighlight, .clear],
                        startPoint: .top,
                        endPoint: .init(x: 0.5, y: 0.35)
                    ))
                }
        }
        .overlay {
            shape.strokeBorder(LinearGradient(
                colors: [AppPalette.hairlineStrong, AppPalette.hairline],
                startPoint: .top,
                endPoint: .bottom
            ))
        }
    }
}

/// A small all-caps label above a group, e.g. "HOVER".
struct SectionLabel: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.app(size: 11, weight: .semibold))
            .kerning(0.8)
            .foregroundStyle(AppPalette.secondaryText)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A page in the detail pane: a big title, a line about the page, then its content. An optional
/// control on the right of the title applies to the whole page (Statistics' time range).
struct AppPage<Accessory: View, Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let accessory: Accessory
    @ViewBuilder let content: Content

    var body: some View {
        PageScroll {
            HStack(alignment: .bottom, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.app(size: 30, weight: .bold))
                        .kerning(-0.4)
                        .foregroundStyle(AppPalette.primaryText)
                        .accessibilityAddTraits(.isHeader)
                    Text(subtitle)
                        .font(.app(size: 14))
                        .foregroundStyle(AppPalette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                accessory
            }
            .padding(.bottom, 28)
            VStack(alignment: .leading, spacing: 28) {
                content
            }
        }
    }
}

extension AppPage where Accessory == EmptyView {
    init(title: String, subtitle: String, @ViewBuilder content: () -> Content) {
        self.init(title: title, subtitle: subtitle, accessory: { EmptyView() }, content: content)
    }
}

/// The scrolling column every page sits in: same insets everywhere, capped width on big windows.
struct PageScroll<Content: View>: View {
    @ViewBuilder let content: Content

    static var maxWidth: CGFloat { 760 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .frame(maxWidth: Self.maxWidth, alignment: .leading)
            .padding(.horizontal, 40)
            .padding(.top, 48)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(.automatic)
    }
}

/// A glass group of rows with hairlines between them, under an optional small header.
struct SettingsCard<Content: View>: View {
    var header: String?
    var footer: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let header {
                SectionLabel(title: header)
                    .padding(.horizontal, AppMetrics.cardInset)
            }
            VStack(spacing: 0) {
                Group(subviews: content) { rows in
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
            .glassPanel()
            if let footer {
                Text(footer)
                    .font(.app(size: 12.5))
                    .foregroundStyle(AppPalette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, AppMetrics.cardInset)
            }
        }
    }
}

/// One setting: a title, a grey line explaining it, and its control on the right.
struct SettingsRow<Control: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder let control: Control

    var body: some View {
        HStack(spacing: 24) {
            SettingsRowLabel(title: title, subtitle: subtitle)
            control
                .fixedSize()
        }
        .settingsRowPadding()
    }
}

/// A row's title with its grey explanation underneath.
struct SettingsRowLabel: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.app(size: 13.5, weight: .medium))
                .foregroundStyle(AppPalette.primaryText)
            if let subtitle {
                Text(subtitle)
                    .font(.app(size: 12.5))
                    .foregroundStyle(AppPalette.secondaryText)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension View {
    /// The insets every row in a `SettingsCard` uses, so rows line up.
    func settingsRowPadding() -> some View {
        padding(.horizontal, AppMetrics.cardInset)
            .padding(.vertical, 14)
            .frame(minHeight: 62)
            .accessibilityElement(children: .contain)
    }
}

/// An on/off switch in white and black instead of the system accent colour. VoiceOver reads it
/// as a normal switch.
struct MonochromeSwitchStyle: ToggleStyle {
    enum Size { case regular, large }
    var size: Size = .regular

    func makeBody(configuration: Configuration) -> some View {
        MonochromeSwitch(configuration: configuration, size: size)
    }
}

private struct MonochromeSwitch: View {
    let configuration: ToggleStyleConfiguration
    let size: MonochromeSwitchStyle.Size
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let track = size == .large ? CGSize(width: 56, height: 32) : CGSize(width: 38, height: 22)
        Button {
            configuration.isOn.toggle()
        } label: {
            Capsule()
                .fill(configuration.isOn ? AppPalette.ink : AppPalette.rail)
                .overlay {
                    PillOutline(color: .white.opacity(configuration.isOn ? 0 : 0.08))
                }
                .frame(width: track.width, height: track.height)
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    Circle()
                        .fill(configuration.isOn ? AppPalette.knobOn : AppPalette.knobOff)
                        .shadow(color: .black.opacity(0.3), radius: 1.5, y: 1)
                        .padding(size == .large ? 3 : 2)
                }
                .shadow(color: .white.opacity(configuration.isOn && size == .large ? 0.18 : 0), radius: 10)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.4)
        .animation(reduceMotion ? nil : .snappy(duration: 0.22), value: configuration.isOn)
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }
        }
    }
}

/// A slider in white on grey. Arrow keys move it by one step; VoiceOver can adjust it too.
struct MonochromeSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 10
    let accessibilityLabel: String
    let accessibilityValue: String

    private let knobSize: CGFloat = 18

    var body: some View {
        GeometryReader { proxy in
            let travel = max(proxy.size.width - knobSize, 1)
            let offset = travel * fraction
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(AppPalette.rail)
                    .frame(height: 4)
                Capsule()
                    .fill(AppPalette.ink)
                    .frame(width: offset + knobSize / 2, height: 4)
                Circle()
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
                    .shadow(color: .white.opacity(0.2), radius: 6)
                    .frame(width: knobSize, height: knobSize)
                    .offset(x: offset)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { drag in
                    let position = (drag.location.x - knobSize / 2) / travel
                    set(range.lowerBound + min(max(position, 0), 1) * span)
                }
            )
        }
        .frame(height: 22)
        .focusable()
        .onKeyPress(.leftArrow) { set(value - step); return .handled }
        .onKeyPress(.rightArrow) { set(value + step); return .handled }
        .onKeyPress(.downArrow) { set(value - step); return .handled }
        .onKeyPress(.upArrow) { set(value + step); return .handled }
        .accessibilityElement()
        .accessibilityLabel(Text(accessibilityLabel))
        .accessibilityValue(Text(accessibilityValue))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: set(value + step)
            case .decrement: set(value - step)
            @unknown default: break
            }
        }
    }

    private var span: Double { range.upperBound - range.lowerBound }

    private var fraction: Double {
        span > 0 ? (value - range.lowerBound) / span : 0
    }

    /// Snaps to `step` and keeps the value inside `range`.
    private func set(_ newValue: Double) {
        let snapped = (newValue / step).rounded() * step
        value = min(max(snapped, range.lowerBound), range.upperBound)
    }
}

/// A quiet glass capsule with a hairline border, for secondary actions.
struct PillButtonStyle: ButtonStyle {
    /// Keeps the hovered look, for a button whose menu or list is open.
    var isHeld = false

    func makeBody(configuration: Configuration) -> some View {
        PillButton(configuration: configuration, isProminent: false, isHeld: isHeld)
    }
}

/// A solid white capsule with black text: the one main action in a card.
struct ProminentPillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PillButton(configuration: configuration, isProminent: true)
    }
}

private struct PillButton: View {
    let configuration: ButtonStyleConfiguration
    let isProminent: Bool
    var isHeld = false
    @State private var isHovered = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        configuration.label
            .font(.app(size: 13, weight: .semibold))
            .foregroundStyle(isProminent ? Color.black : AppPalette.primaryText)
            .padding(.horizontal, 14)
            .frame(minHeight: 30)
            .background(fill, in: Capsule())
            .overlay {
                if !isProminent {
                    PillOutline(color: AppPalette.hairlineStrong)
                }
            }
            .contentShape(.capsule)
            .opacity(isEnabled ? 1 : 0.4)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: isHovered)
            .onHover { isHovered = $0 }
    }

    private var fill: Color {
        if isProminent {
            return .white.opacity(configuration.isPressed ? 0.78 : isHovered ? 0.9 : 1)
        }
        if configuration.isPressed { return AppPalette.pressed }
        return isHovered || isHeld ? AppPalette.selection : AppPalette.hover
    }
}

/// Text first, then a small icon, as on links that leave the app.
struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            configuration.title
            configuration.icon
                .font(.app(size: 10, weight: .bold))
                .foregroundStyle(AppPalette.secondaryText)
        }
    }
}

/// A hairline capsule outline. Drawn as a rounded rectangle a hair short of a full capsule:
/// capsule strokes picked up stray marks at their ends in off-screen renders.
struct PillOutline: View {
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            RoundedRectangle(cornerRadius: max(proxy.size.height / 2 - 1, 0))
                .strokeBorder(color, lineWidth: 1)
        }
    }
}

/// A row of capsules where any number of options are on: the ones on are solid white with black text.
/// VoiceOver reads each as a toggle.
struct MonochromeChips<Value: Hashable>: View {
    let title: String
    let options: [(value: Value, label: String)]
    @Binding var selection: Set<Value>
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.value) { option in
                let isOn = selection.contains(option.value)
                Button {
                    if isOn { selection.remove(option.value) } else { selection.insert(option.value) }
                } label: {
                    Text(option.label)
                        .font(.app(size: 12, weight: .semibold))
                        .foregroundStyle(isOn ? Color.black : AppPalette.primaryText)
                        .padding(.horizontal, 11)
                        .frame(minHeight: 26)
                        .background(isOn ? AppPalette.ink : .clear, in: Capsule())
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(option.label))
                .accessibilityValue(Text(isOn ? "On" : "Off"))
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .padding(2)
        .background(AppPalette.hover, in: Capsule())
        .overlay(PillOutline(color: AppPalette.hairline))
        .opacity(isEnabled ? 1 : 0.4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(title))
    }
}

/// A row of capsules where one option is chosen: the chosen one is solid white with black text.
/// VoiceOver reads it as a standard picker.
struct MonochromeSegmented<Value: Hashable>: View {
    let title: String
    let options: [(value: Value, label: String)]
    @Binding var selection: Value
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.value) { option in
                let isSelected = option.value == selection
                Button { selection = option.value } label: {
                    Text(option.label)
                        .font(.app(size: 12, weight: .semibold))
                        .foregroundStyle(isSelected ? Color.black : AppPalette.primaryText)
                        .padding(.horizontal, 11)
                        .frame(minHeight: 26)
                        .background(isSelected ? AppPalette.ink : .clear, in: Capsule())
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(AppPalette.hover, in: Capsule())
        .overlay(PillOutline(color: AppPalette.hairline))
        .opacity(isEnabled ? 1 : 0.4)
        .animation(reduceMotion ? nil : .snappy(duration: 0.22), value: selection)
        .accessibilityRepresentation {
            Picker(title, selection: $selection) {
                ForEach(options, id: \.value) { Text($0.label).tag($0.value) }
            }
        }
    }
}

/// One choice in a `MonochromeDropdown`.
struct DropdownOption<Value: Hashable> {
    let value: Value
    let label: String
}

/// A drop-down in the app's own style, in place of the stock macOS pop-up button: a capsule showing
/// the current choice, and a dark list under it that scrolls when long and opens at the chosen row.
/// `sections` are drawn with a hairline between them. VoiceOver reads it as a standard pop-up button.
struct MonochromeDropdown<Value: Hashable>: View {
    let title: String
    let sections: [[DropdownOption<Value>]]
    @Binding var selection: Value
    /// Runs when the person picks a row (also from VoiceOver), after `selection` changes. A sound picker
    /// plays the sound here.
    var onChoose: ((Value) -> Void)?
    var width: CGFloat = 170
    @State private var isOpen = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button { isOpen.toggle() } label: {
            HStack(spacing: 6) {
                Text(currentLabel)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.down")
                    .font(.app(size: 10, weight: .bold))
                    .foregroundStyle(AppPalette.secondaryText)
            }
            .frame(width: width - 28)
        }
        .buttonStyle(PillButtonStyle(isHeld: isOpen))
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            DropdownList(sections: sections, selection: selection, width: width) { value in
                isOpen = false
                choose(value)
            }
        }
        .accessibilityRepresentation {
            Picker(title, selection: Binding(get: { selection }, set: { choose($0) })) {
                ForEach(sections.flatMap { $0 }, id: \.value) { Text($0.label).tag($0.value) }
            }
        }
    }

    private var currentLabel: String {
        sections.lazy.flatMap { $0 }.first { $0.value == selection }?.label ?? ""
    }

    private func choose(_ value: Value) {
        selection = value
        onChoose?(value)
    }
}

/// The open list of a `MonochromeDropdown`: rows with a tick on the chosen one. Arrow keys move the
/// highlight, Return chooses, Esc and a click outside close it (the popover does that).
struct DropdownList<Value: Hashable>: View {
    let sections: [[DropdownOption<Value>]]
    let selection: Value
    var width: CGFloat = 170
    let onChoose: (Value) -> Void
    @State private var highlighted: Value?
    @FocusState private var hasFocus: Bool

    static var rowHeight: CGFloat { 26 }
    static var inset: CGFloat { 6 }
    static var dividerHeight: CGFloat { 9 }
    static var tallest: CGFloat { 260 }

    private var all: [DropdownOption<Value>] { sections.flatMap { $0 } }

    /// The list's height: every row and divider plus the padding, up to `tallest`, then it scrolls.
    var height: CGFloat {
        let rows = CGFloat(all.count) * Self.rowHeight
        let dividers = CGFloat(max(sections.count - 1, 0)) * Self.dividerHeight
        return min(rows + dividers + Self.inset * 2, Self.tallest)
    }

    init(sections: [[DropdownOption<Value>]], selection: Value, width: CGFloat = 170, onChoose: @escaping (Value) -> Void) {
        self.sections = sections
        self.selection = selection
        self.width = width
        self.onChoose = onChoose
        _highlighted = State(initialValue: selection)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                content
            }
            .scrollIndicators(.never)
            .onAppear {
                proxy.scrollTo(selection, anchor: .center)
                hasFocus = true
            }
            .focusable()
            .focusEffectDisabled()
            .focused($hasFocus)
            .onKeyPress(.downArrow) { move(1, proxy); return .handled }
            .onKeyPress(.upArrow) { move(-1, proxy); return .handled }
            .onKeyPress(.return) {
                if let highlighted { onChoose(highlighted) }
                return .handled
            }
        }
        .frame(width: width, height: height)
        .background(Color(white: 0.07))
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .contain)
    }

    /// The rows and dividers, without the scroll view (also what off-screen renders draw).
    var content: some View {
        VStack(spacing: 0) {
            ForEach(Array(sections.enumerated()), id: \.offset) { index, section in
                if index > 0 {
                    AppPalette.hairline
                        .frame(height: 1)
                        .padding(.horizontal, 6)
                        .frame(height: Self.dividerHeight)
                }
                ForEach(section, id: \.value) { option in
                    row(option)
                }
            }
        }
        .padding(Self.inset)
    }

    private func row(_ option: DropdownOption<Value>) -> some View {
        let isChosen = option.value == selection
        return Button { onChoose(option.value) } label: {
            HStack(spacing: 6) {
                Image(systemName: "checkmark")
                    .font(.app(size: 10, weight: .bold))
                    .frame(width: 12)
                    .opacity(isChosen ? 1 : 0)
                    .accessibilityHidden(true)
                Text(option.label)
                    .font(.app(size: 13, weight: .medium))
                    .foregroundStyle(AppPalette.primaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(height: Self.rowHeight)
            .background(highlighted == option.value ? AppPalette.selection : .clear, in: .rect(cornerRadius: 7, style: .continuous))
            .contentShape(.rect(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .id(option.value)
        .onHover { inside in
            if inside { highlighted = option.value }
        }
        .accessibilityLabel(Text(option.label))
        .accessibilityAddTraits(isChosen ? .isSelected : [])
    }

    private func move(_ step: Int, _ proxy: ScrollViewProxy) {
        let values = all.map(\.value)
        guard !values.isEmpty else { return }
        let current = highlighted.flatMap { values.firstIndex(of: $0) }
        let next = current.map { min(max($0 + step, 0), values.count - 1) } ?? (step > 0 ? 0 : values.count - 1)
        highlighted = values[next]
        proxy.scrollTo(values[next])
    }
}
