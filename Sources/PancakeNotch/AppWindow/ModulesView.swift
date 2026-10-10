import ModuleShelf
import SwiftUI

/// The modules that live in the notch: the Shelf (what it does, then its settings), and a
/// "Coming soon" card for Now Playing.
struct ModulesView: View {
    @Bindable var shelfSettings: ShelfSettings
    let shelfStore: ShelfStore

    var body: some View {
        AppPage(
            title: String(localized: "Modules"),
            subtitle: String(localized: "Small tools that live inside the notch.")
        ) {
            ModuleCard(
                title: String(localized: "Shelf"),
                symbol: "tray",
                summary: String(localized: "A place in the notch for things you're about to use: drop them on, drag them out later."),
                points: [
                    String(localized: "Drop files, images, text and links on the notch"),
                    String(localized: "Click an item for a big preview, or to edit a note or link"),
                    String(localized: "Right-click to copy, share or AirDrop"),
                    String(localized: "A small tray in the notch shows the count when it's nearly full"),
                ],
                isComingSoon: false
            ) {
                ShelfArt()
            }
            ShelfSettingsCard(settings: shelfSettings, store: shelfStore)
            VStack(spacing: 16) {
                ModuleCard(
                    title: String(localized: "Now Playing"),
                    symbol: "music.note",
                    summary: String(localized: "Media controls and artwork in the notch, for whatever is playing."),
                    points: [
                        String(localized: "Album art and the track at a glance"),
                        String(localized: "Play, pause and skip without switching apps"),
                    ]
                ) {
                    NowPlayingArt()
                }
            }
        }
    }
}

private struct ModuleCard<Art: View>: View {
    let title: String
    let symbol: String
    let summary: String
    let points: [String]
    var isComingSoon = true
    @ViewBuilder let art: Art

    var body: some View {
        HStack(spacing: 0) {
            // Overlays, so the art never makes the card taller than its text.
            Color.black
                .overlay(alignment: .top) {
                    ZStack(alignment: .top) {
                        NotchGlow(scale: 0.75)
                        art
                    }
                }
                .frame(width: 280)
            .frame(maxHeight: .infinity)
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 16, bottomLeadingRadius: 16, style: .continuous))
            .accessibilityHidden(true)

            AppPalette.hairline.frame(width: 1)

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
                    if isComingSoon { ComingSoonBadge() }
                }
                Text(summary)
                    .font(.app(size: 13.5))
                    .foregroundStyle(AppPalette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 14)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(points, id: \.self) { point in
                        HStack(alignment: .firstTextBaseline, spacing: 9) {
                            Circle()
                                .fill(AppPalette.secondaryText)
                                .frame(width: 4, height: 4)
                                .alignmentGuide(.firstTextBaseline) { $0[.bottom] + 3 }
                            Text(point)
                                .font(.app(size: 12.5, weight: .medium))
                        }
                    }
                }
                .padding(.top, 16)
            }
            .padding(AppMetrics.cardInset)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(minHeight: 196)
        .fixedSize(horizontal: false, vertical: true)
        .glassPanel()
        .accessibilityElement(children: .contain)
    }
}

struct ComingSoonBadge: View {
    var body: some View {
        Text("Coming soon")
            .font(.app(size: 10.5, weight: .semibold))
            .kerning(0.4)
            .textCase(.uppercase)
            .foregroundStyle(AppPalette.secondaryText)
            .padding(.horizontal, 9)
            .frame(height: 22)
            .overlay(PillOutline(color: AppPalette.hairlineStrong))
    }
}

/// An open notch with a few things on the Shelf: a document, a photo, a note and a link.
private struct ShelfArt: View {
    var body: some View {
        ZStack(alignment: .top) {
            NotchPanelShape()
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Capsule().fill(.white.opacity(0.85)).frame(width: 34, height: 6)
                    Capsule().fill(.white.opacity(0.35)).frame(width: 26, height: 6)
                }
                HStack(spacing: 10) {
                    tile(symbol: "doc.richtext.fill")
                    tile(symbol: "photo.fill")
                    tile(symbol: "text.alignleft")
                    tile(symbol: "link")
                }
            }
            .padding(.horizontal, 30)
            .padding(.top, 38)
        }
        .frame(width: 236, height: 138)
    }

    private func tile(symbol: String) -> some View {
        VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.white.opacity(0.14))
                .frame(width: 36, height: 36)
                .overlay {
                    Image(systemName: symbol)
                        .font(.app(size: 15, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                }
            Capsule().fill(.white.opacity(0.3)).frame(width: 28, height: 4)
        }
    }
}

/// An open notch playing a song: artwork, track lines, progress and transport buttons.
private struct NowPlayingArt: View {
    var body: some View {
        ZStack(alignment: .top) {
            NotchPanelShape()
            VStack(spacing: 14) {
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(LinearGradient(colors: [.white.opacity(0.42), .white.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 46, height: 46)
                        .overlay {
                            Image(systemName: "music.note")
                                .font(.app(size: 18, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.9))
                        }
                    VStack(alignment: .leading, spacing: 7) {
                        Capsule().fill(.white.opacity(0.85)).frame(width: 72, height: 7)
                        Capsule().fill(.white.opacity(0.35)).frame(width: 50, height: 6)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "waveform")
                        .font(.app(size: 16, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                }
                HStack(spacing: 10) {
                    Capsule()
                        .fill(.white.opacity(0.18))
                        .frame(height: 4)
                        .overlay(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.85)).frame(width: 52, height: 4)
                        }
                    HStack(spacing: 14) {
                        Image(systemName: "backward.fill")
                        Image(systemName: "pause.fill").font(.app(size: 15))
                        Image(systemName: "forward.fill")
                    }
                    .font(.app(size: 11))
                    .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 30)
            .padding(.top, 34)
        }
        .frame(width: 236, height: 138)
    }
}

/// The Shelf's settings (ADR-0013).
private struct ShelfSettingsCard: View {
    @Bindable var settings: ShelfSettings
    let store: ShelfStore
    @State private var confirmingClear = false

    var body: some View {
        SettingsCard(
            header: String(localized: "Shelf"),
            footer: String(localized: "Holds up to \(ShelfStore.capacity) items. Files stay where they are: the Shelf only remembers where to find them.")
        ) {
            SettingsRow(
                title: String(localized: "Shelf"),
                subtitle: String(localized: "Drop files, images, text and links on the notch to keep them handy.")
            ) {
                Toggle(String(localized: "Shelf"), isOn: $settings.isEnabled)
                    .labelsHidden()
            }
            Group {
                SettingsRow(
                    title: String(localized: "On the Shelf now"),
                    subtitle: String(localized: "\(store.items.count) of \(ShelfStore.capacity) items")
                ) {
                    // Two clicks, like Clear all in the notch.
                    Button(!confirmingClear ? String(localized: "Clear Shelf")
                           : store.items.count == 1 ? String(localized: "Clear 1 item?")
                           : String(localized: "Clear \(store.items.count) items?")) {
                        if confirmingClear { store.clear() }
                        confirmingClear.toggle()
                    }
                    .disabled(store.items.isEmpty)
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
            .disabled(!settings.isEnabled)
        }
    }
}
