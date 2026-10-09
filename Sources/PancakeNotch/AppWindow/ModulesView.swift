import SwiftUI

/// The modules that will live in the notch. None has shipped yet, so each is a "Coming soon" card
/// with a sketch of how it will look.
struct ModulesView: View {
    var body: some View {
        AppPage(
            title: String(localized: "Modules"),
            subtitle: String(localized: "Small tools that live inside the notch. These are on the way.")
        ) {
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
                ModuleCard(
                    title: String(localized: "Shelf"),
                    symbol: "tray",
                    summary: String(localized: "Drop files on the notch to keep them handy, then drag them out wherever you need them."),
                    points: [
                        String(localized: "A place to park files between apps"),
                        String(localized: "Always one hover away"),
                    ]
                ) {
                    ShelfArt()
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
                    ComingSoonBadge()
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
            .padding(22)
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
                        Capsule().fill(.white.opacity(0.85)).frame(width: 92, height: 7)
                        Capsule().fill(.white.opacity(0.35)).frame(width: 62, height: 6)
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

/// An open notch holding a few files, with room to drop another.
private struct ShelfArt: View {
    var body: some View {
        ZStack(alignment: .top) {
            NotchPanelShape()
            HStack(spacing: 10) {
                file("doc.text.fill", width: 38)
                file("photo.fill", width: 30)
                file("folder.fill", width: 34)
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(.white.opacity(0.3), style: StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
                    .frame(width: 40, height: 50)
                    .overlay {
                        Image(systemName: "plus")
                            .font(.app(size: 13, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .padding(.bottom, 13)
            }
            .padding(.top, 40)
        }
        .frame(width: 236, height: 138)
    }

    private func file(_ symbol: String, width: CGFloat) -> some View {
        VStack(spacing: 7) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(LinearGradient(colors: [.white.opacity(0.2), .white.opacity(0.08)], startPoint: .top, endPoint: .bottom))
                .frame(width: 40, height: 50)
                .overlay {
                    Image(systemName: symbol)
                        .font(.app(size: 17))
                        .foregroundStyle(.white.opacity(0.9))
                }
            Capsule().fill(.white.opacity(0.4)).frame(width: width, height: 5)
        }
    }
}
