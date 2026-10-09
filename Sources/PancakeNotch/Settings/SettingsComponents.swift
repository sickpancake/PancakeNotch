import AppKit
import SwiftUI

/// The settings window's colours: monochrome only, adapting to light, dark and Increase Contrast
/// (ADR-0029).
enum SettingsPalette {
    static let windowBackground = adaptive(light: gray(0.985), dark: gray(0.12))
    static let sidebarBackground = adaptive(light: gray(0.955), dark: gray(0.095))
    static let cardBackground = adaptive(light: gray(0.955), dark: gray(0.165))
    static let hairline = adaptive(light: .black.withAlphaComponent(0.08), dark: .white.withAlphaComponent(0.08),
                                   highContrastLight: .black.withAlphaComponent(0.45), highContrastDark: .white.withAlphaComponent(0.5))
    static let selection = adaptive(light: .black.withAlphaComponent(0.075), dark: .white.withAlphaComponent(0.1))
    static let hover = adaptive(light: .black.withAlphaComponent(0.04), dark: .white.withAlphaComponent(0.05))

    /// Filled parts of controls: the "on" switch track, the slider's filled side.
    static let ink = adaptive(light: gray(0.1), dark: gray(0.93))
    /// Empty parts of controls: the "off" switch track, the slider's rail.
    static let rail = adaptive(light: .black.withAlphaComponent(0.13), dark: .white.withAlphaComponent(0.2),
                               highContrastLight: .black.withAlphaComponent(0.4), highContrastDark: .white.withAlphaComponent(0.5))
    /// The switch knob when on: the window colour, so it reads against the ink track.
    static let knobOn = adaptive(light: .white, dark: gray(0.12))
    static let knobOff = adaptive(light: .white, dark: gray(0.93))

    private static func gray(_ white: CGFloat) -> NSColor {
        NSColor(white: white, alpha: 1)
    }

    static func adaptive(
        light: NSColor,
        dark: NSColor,
        highContrastLight: NSColor? = nil,
        highContrastDark: NSColor? = nil
    ) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            switch appearance.bestMatch(from: [.aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua]) {
            case .darkAqua: dark
            case .accessibilityHighContrastAqua: highContrastLight ?? light
            case .accessibilityHighContrastDarkAqua: highContrastDark ?? dark
            default: light
            }
        })
    }
}

/// A page in the detail pane: a big title, a line about the page, then its cards.
struct SettingsPage<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.largeTitle.weight(.bold))
                    .accessibilityAddTraits(.isHeader)
                Text(subtitle)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                VStack(alignment: .leading, spacing: 24) {
                    content
                }
                .padding(.top, 24)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 40)
            .padding(.top, 44)
            .padding(.bottom, 32)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}

/// A rounded group of rows with hairlines between them, under an optional small header.
struct SettingsCard<Content: View>: View {
    var header: String?
    var footer: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let header {
                Text(header.uppercased())
                    .font(.caption.weight(.semibold))
                    .kerning(0.6)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 16)
                    .accessibilityAddTraits(.isHeader)
            }
            VStack(spacing: 0) {
                Group(subviews: content) { rows in
                    ForEach(rows) { row in
                        if row.id != rows.first?.id {
                            SettingsPalette.hairline
                                .frame(height: 1)
                                .padding(.horizontal, 16)
                        }
                        row
                    }
                }
            }
            .background(SettingsPalette.cardBackground, in: .rect(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(SettingsPalette.hairline)
            }
            if let footer {
                Text(footer)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)
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
                .font(.body.weight(.medium))
            if let subtitle {
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension View {
    /// The insets every row in a `SettingsCard` uses, so rows line up.
    func settingsRowPadding() -> some View {
        padding(.horizontal, 16)
            .padding(.vertical, 13)
            .frame(minHeight: 58)
            .accessibilityElement(children: .contain)
    }
}

/// An on/off switch in ink and window colours instead of the system accent colour.
struct MonochromeSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        MonochromeSwitch(configuration: configuration)
    }
}

private struct MonochromeSwitch: View {
    let configuration: ToggleStyleConfiguration
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            Capsule()
                .fill(configuration.isOn ? SettingsPalette.ink : SettingsPalette.rail)
                .frame(width: 38, height: 22)
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    Circle()
                        .fill(configuration.isOn ? SettingsPalette.knobOn : SettingsPalette.knobOff)
                        .shadow(color: .black.opacity(0.18), radius: 1, y: 0.5)
                        .padding(2)
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.4)
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: configuration.isOn)
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }
        }
    }
}

/// A slider in ink colours. Arrow keys move it by one step; VoiceOver can adjust it too.
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
                    .fill(SettingsPalette.rail)
                    .frame(height: 4)
                Capsule()
                    .fill(SettingsPalette.ink)
                    .frame(width: offset + knobSize / 2, height: 4)
                Circle()
                    .fill(Color.white)
                    .overlay(Circle().strokeBorder(Color.black.opacity(0.12)))
                    .shadow(color: .black.opacity(0.22), radius: 1.5, y: 1)
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

/// A quiet rounded button with a hairline border, for secondary actions.
struct PillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PillButton(configuration: configuration)
    }
}

private struct PillButton: View {
    let configuration: ButtonStyleConfiguration
    @State private var isHovered = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .font(.body.weight(.medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .frame(minHeight: 28)
            .background(fill, in: Capsule(style: .circular))
            .overlay(Capsule(style: .circular).strokeBorder(SettingsPalette.hairline))
            .contentShape(.capsule)
            .opacity(isEnabled ? 1 : 0.4)
            .onHover { isHovered = $0 }
    }

    private var fill: Color {
        if configuration.isPressed { return SettingsPalette.selection }
        return isHovered ? SettingsPalette.hover : SettingsPalette.windowBackground
    }
}
