import AppKit
import ConvertKit
import NotchCore
import SwiftUI

/// Convert in the notch, a little taller than the Shelf (ADR-0038): a scrolling row of the formats the
/// files can become, then progress on the chosen one, then the result.
struct ShelfConvertView: View {
    let module: ShelfModule
    let session: ShelfConversion
    let layout: ShelfLayout
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            header
                .frame(height: layout.bandHeight)
                .padding(.horizontal, ShelfLayout.sidePadding)
            content
                .frame(width: layout.content.width, height: layout.content.height)
                .padding(.top, layout.content.minY - layout.bandHeight)
            Spacer(minLength: 0)
        }
        .frame(width: layout.body.width, height: layout.body.height, alignment: .top)
        .foregroundStyle(.white)
        .animation(reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.3, dampingFraction: 0.86), value: session.phase)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Convert"))
    }

    private var header: some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                Button { module.endConversion() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 24, height: 22)
                        .background(.white.opacity(0.14), in: Capsule())
                }
                .buttonStyle(.plain)
                .help(String(localized: "Back to the Shelf"))
                .accessibilityLabel(Text("Back to the Shelf"))
                Text("Convert")
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
            }
            .frame(width: layout.headerSideWidth, alignment: .leading)

            Spacer(minLength: 0)

            Text(session.title)
                .font(.system(size: 11.5))
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: layout.headerSideWidth, alignment: .trailing)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch session.phase {
        case .receiving:
            VStack(spacing: 8) {
                ProgressView().controlSize(.small).tint(.white)
                Text("Getting the files…", comment: "Convert: promised files are arriving")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.opacity)
        case .looking, .choosing, .converting:
            ShelfConvertRow(module: module, session: session)
                .transition(.opacity)
        case .done(let done):
            ShelfConvertDoneCard(module: module, done: done)
                .transition(.opacity)
        case .failed(let message):
            ShelfConvertFailedCard(module: module, session: session, message: message)
                .transition(.opacity)
        }
    }
}

// MARK: The row

private struct ShelfConvertRow: View {
    let module: ShelfModule
    let session: ShelfConversion

    var body: some View {
        VStack(spacing: 10) {
            Group {
                if module.isSnapshot {
                    // Off-screen renders can't scroll: show what fits.
                    tiles.frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView(.horizontal, showsIndicators: false) { tiles }
                            .onChange(of: session.focus) { _, focus in
                                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(focus) }
                            }
                    }
                }
            }
            .frame(height: ShelfConvertTile.size.height)
            Text(footer)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.45))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: .infinity)
    }

    private var tiles: some View {
        HStack(spacing: 8) {
            ForEach(session.options) { option in
                ShelfConvertTile(
                    option: option,
                    state: state(of: option),
                    progress: session.progress,
                    isFocused: session.focus == option.format,
                    choose: { module.chooseConvertFormat(option.format) },
                    stop: { module.stopConverting() }
                )
                .id(option.format)
            }
        }
    }

    private func state(of option: ConvertOption) -> ShelfConvertTile.State {
        switch session.phase {
        case .converting(let format): format == option.format ? .converting : .waiting
        case .looking: .looking
        default: option.isAvailable ? .ready : .unavailable
        }
    }

    private var footer: String {
        let settings = module.settings
        let place = if module.keepsConvertedFiles {
            String(localized: "Saves to this practice Shelf", comment: "Convert footer in the app window")
        } else if settings.convertDestination == .folder, let folder = settings.convertFolder {
            String(localized: "Saves to \(folder.lastPathComponent)", comment: "Convert footer; a folder's name")
        } else {
            String(localized: "Saves next to the original", comment: "Convert footer")
        }
        return place + " · " + String(localized: "\(settings.convertQuality.title) quality", comment: "Convert footer; Best, Balanced or Smaller file")
    }
}

struct ShelfConvertTile: View {
    enum State: Equatable {
        /// The helper is still reading the files.
        case looking
        case ready
        /// Dimmed, with its note ("Too big").
        case unavailable
        case converting
        /// Another tile is converting.
        case waiting
    }

    static let size = CGSize(width: 108, height: 124)

    let option: ConvertOption
    let state: State
    let progress: Double
    let isFocused: Bool
    let choose: () -> Void
    let stop: () -> Void
    @SwiftUI.State private var isHovered = false
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        // Not `.disabled`: that greys the converting tile too. Only a ready tile converts.
        Button { if state == .ready { choose() } } label: {
            VStack(spacing: 5) {
                icon
                    .frame(width: 44, height: 44)
                Text(option.format.badge)
                    .font(.system(size: 14, weight: .bold))
                if option.format.title != option.format.badge {
                    Text(option.format.title)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
                if let note = option.note, state != .converting {
                    Text(note.text)
                        .font(.system(size: 9.5, weight: .semibold))
                        .lineLimit(1)
                        .padding(.horizontal, 6)
                        .frame(height: 16)
                        .overlay(Capsule().strokeBorder(.white.opacity(0.45), lineWidth: 1))
                }
            }
            .padding(.horizontal, 6)
            .frame(width: Self.size.width, height: Self.size.height)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.white.opacity(isHovered && state == .ready ? 0.13 : 0.07))
                    .strokeBorder(.white.opacity(borderOpacity), lineWidth: isFocused && state != .waiting ? 1.5 : 1)
            )
            .opacity(contentOpacity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .overlay(alignment: .topTrailing) {
            if state == .converting {
                Button(action: stop) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .frame(width: 20, height: 20)
                        .background(.white.opacity(0.18), in: Circle())
                }
                .buttonStyle(.plain)
                .padding(6)
                .help(String(localized: "Stop converting"))
                .accessibilityLabel(Text("Stop converting"))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityLabel))
        .accessibilityValue(Text(accessibilityValue))
        .accessibilityHint(Text(accessibilityHint))
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(isFocused ? .isSelected : [])
        .accessibilityAction { if state == .ready { choose() } }
        .accessibilityAction(named: Text("Stop converting")) { if state == .converting { stop() } }
    }

    @ViewBuilder
    private var icon: some View {
        if state == .converting {
            ZStack {
                Circle().stroke(.white.opacity(0.15), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: max(0.02, progress))
                    .stroke(.white, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.2), value: progress)
                Text(verbatim: "\(Int((progress * 100).rounded()))%")
                    .font(.system(size: 10, weight: .semibold))
                    .monospacedDigit()
            }
            .padding(4)
        } else {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.white.opacity(0.1))
                .overlay {
                    Image(systemName: option.format.symbol)
                        .font(.system(size: 18, weight: .medium))
                }
        }
    }

    private var borderOpacity: Double {
        if state == .converting || isFocused && state != .waiting { return 0.85 }
        return contrast == .increased ? 0.4 : 0.14
    }

    private var contentOpacity: Double {
        switch state {
        case .ready, .converting: 1
        case .looking: 0.6
        case .unavailable: 0.4
        case .waiting: 0.3
        }
    }

    private var accessibilityLabel: String {
        option.format == .combinedPDF
            ? option.format.title
            : String(localized: "Convert to \(option.format.title)", comment: "VoiceOver; a Convert format tile")
    }

    private var accessibilityValue: String {
        if state == .converting { return String(localized: "\(Int((progress * 100).rounded())) percent", comment: "VoiceOver; Convert progress") }
        return option.note?.text ?? ""
    }

    private var accessibilityHint: String {
        switch option.note {
        case .tooBig: String(localized: "Too big to convert to this format. Choosing Smaller file in the Shelf's settings may let it fit.")
        case .tooLong: String(localized: "GIFs are made from clips up to 15 seconds long.")
        case .cantRepackage: String(localized: "This video can't change format without re-encoding, which Convert doesn't do.")
        case .picturesNotKept: String(localized: "The text is kept; pictures are left out.")
        default: ""
        }
    }
}

// MARK: Results

private struct ShelfConvertDoneCard: View {
    let module: ShelfModule
    let done: ShelfConversion.Done

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            preview
                .frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .accessibilityHidden(true)
                    Text("Converted to \(done.format.badge)", comment: "Convert finished; the format")
                }
                .font(.system(size: 13, weight: .semibold))
                Text(done.files.count == 1 ? done.files[0].lastPathComponent : String(localized: "\(done.files.count) files", comment: "Convert: several new files"))
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(whereText)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    ShelfPillButton(title: String(localized: "Open"), prominent: true) {
                        for file in done.files.prefix(10) { NSWorkspace.shared.open(file) }
                    }
                    ShelfPillButton(title: String(localized: "Show in Finder")) {
                        NSWorkspace.shared.activateFileViewerSelecting(done.files)
                    }
                    ShelfPillButton(title: String(localized: "Done")) { module.endConversion() }
                }
                .padding(.top, 6)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.white.opacity(0.07))
                .strokeBorder(.white.opacity(0.14), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
    }

    /// The new file, ready to drag out (it's on the Shelf too, so it drags like a tile).
    private var preview: some View {
        let item = done.files.first.flatMap { file in module.store.items.first { $0.path == file.path } }
        return Image(nsImage: NSWorkspace.shared.icon(forFile: done.files[0].path))
            .resizable()
            .aspectRatio(contentMode: .fit)
            .overlay {
                if let item, !module.isSnapshot {
                    ShelfTileInteraction(module: module, itemID: item.id).accessibilityHidden(true)
                }
            }
            .help(String(localized: "Drag to use it"))
            .accessibilityHidden(true)
    }

    private var whereText: String {
        var lines: [String] = []
        if module.keepsConvertedFiles {
            lines.append(String(localized: "Added to this practice Shelf.", comment: "Convert in the app window's practice Shelf"))
        } else if done.keptInShelf {
            lines.append(String(localized: "Kept in the Shelf: the folder can't be written to.", comment: "Convert: saved to the Shelf's own storage"))
        } else {
            lines.append(String(localized: "Saved, and added to the Shelf.", comment: "Convert finished"))
        }
        if done.failed > 0 {
            lines.append(done.failed == 1
                ? String(localized: "1 file couldn't be converted.")
                : String(localized: "\(done.failed) files couldn't be converted.", comment: "Convert: some files failed"))
        }
        return lines.joined(separator: " ")
    }
}

private struct ShelfConvertFailedCard: View {
    let module: ShelfModule
    let session: ShelfConversion
    let message: String

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 22, weight: .medium))
                .frame(width: 30)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Couldn't convert", comment: "Convert failed: card title")
                    .font(.system(size: 13, weight: .semibold))
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    if session.options.contains(where: \.isAvailable) {
                        ShelfPillButton(title: String(localized: "Choose another format"), prominent: true) {
                            session.phase = .choosing
                        }
                    }
                    ShelfPillButton(title: String(localized: "Back to the Shelf")) { module.endConversion() }
                }
                .padding(.top, 6)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.white.opacity(0.07))
                .strokeBorder(.white.opacity(0.14), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
    }
}

// MARK: Under the notch

/// "✓ Converted Report.pdf" in the strip under the notch, when a conversion ends while it's closed.
struct ShelfConvertPeek: View {
    let text: String
    let failed: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: failed ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                .font(.system(size: 11, weight: .semibold))
                .accessibilityHidden(true)
            Text(text)
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(.white)
        .lineLimit(1)
        .truncationMode(.middle)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}
