import AppKit
import ImageIO
import SwiftUI

/// The Shelf's Clipboard row (#79): recent copies, newest first. Click one to copy it again, drag it out,
/// or use its buttons to pin it, keep it on the Shelf, or AirDrop it.
struct ShelfClipboardRow: View {
    let module: ShelfModule
    let clipboard: ShelfClipboard
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if clipboard.entries.isEmpty {
            ShelfClipboardEmptyView(isRunning: clipboard.isRunning)
        } else if module.isSnapshot {
            tiles.frame(maxWidth: .infinity, alignment: .leading)
        } else {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) { tiles }
                    .onChange(of: module.clipboardCursor) { _, id in
                        guard let id else { return }
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { proxy.scrollTo(id) }
                    }
            }
        }
    }

    private var tiles: some View {
        HStack(spacing: ShelfLayout.tileSpacing) {
            ForEach(clipboard.entries) { entry in
                ShelfClipboardTile(
                    module: module,
                    entry: entry,
                    imageURL: clipboard.fileURL(for: entry),
                    isCursor: module.clipboardCursor == entry.id,
                    isCopied: module.copiedID == entry.id
                )
                .id(entry.id)
                .transition(reduceMotion ? .opacity : .scale(scale: 0.85).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.8), value: clipboard.entries.map(\.id))
        .frame(maxHeight: .infinity)
    }
}

struct ShelfClipboardTile: View {
    let module: ShelfModule
    let entry: ShelfClipboardEntry
    let imageURL: URL?
    let isCursor: Bool
    let isCopied: Bool
    @State private var isHovering = false
    @State private var image: NSImage?

    var body: some View {
        VStack(spacing: 5) {
            preview
                .frame(width: 56, height: 56)
                .overlay(alignment: .topLeading) {
                    if entry.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.black)
                            .frame(width: 17, height: 17)
                            .background(.white, in: Circle())
                            .offset(x: -5, y: -5)
                            .transition(.scale.combined(with: .opacity))
                            .accessibilityHidden(true)
                    }
                }
                .overlay(alignment: .bottom) {
                    if isHovering && !module.isSnapshot && !isCopied { actions.transition(.opacity) }
                }
                .overlay {
                    if isCopied {
                        Text("Copied")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 7)
                            .frame(height: 18)
                            .background(.white, in: Capsule())
                            .transition(.opacity)
                    }
                }
                .animation(.easeOut(duration: 0.15), value: isHovering)
                .animation(.easeOut(duration: 0.15), value: isCopied)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: entry.isPinned)
            Text(entry.item.displayName)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.white.opacity(isCursor ? 1 : 0.8))
                .lineLimit(2)
                .truncationMode(.tail)
                .multilineTextAlignment(.center)
                .frame(width: ShelfLayout.tileSize.width - 8, height: 26, alignment: .top)
        }
        .padding(.top, 5)
        .frame(width: ShelfLayout.tileSize.width, height: ShelfLayout.tileSize.height, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.white.opacity(isCursor ? 0.16 : 0))
        )
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture { module.copyClipboardEntry(entry) }
        .onDrag { module.clipboardDragProvider(entry) }
        .help(entry.item.displayName)
        .task(id: imageURL) {
            guard let imageURL else { image = nil; return }
            // A 112-pixel thumbnail of a PNG we wrote ourselves: quick enough to make here.
            image = Self.thumbnail(imageURL)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityLabel))
        .accessibilityHint(Text("Copies it again", comment: "VoiceOver hint for a recent copy in the Shelf"))
        .accessibilityAddTraits(isCursor ? .isSelected : [])
        .accessibilityAction { module.copyClipboardEntry(entry) }
        .accessibilityActions {
            Button(entry.isPinned ? String(localized: "Unpin") : String(localized: "Pin")) { module.clipboard?.togglePin(entry.id) }
            Button(String(localized: "Keep on Shelf")) { module.keepClipboardEntry(entry) }
            Button(String(localized: "AirDrop")) { module.airDropClipboardEntry(entry) }
            Button(String(localized: "Remove")) { module.clipboard?.remove(entry.id) }
        }
    }

    @ViewBuilder
    private var preview: some View {
        switch entry.item.kind {
        case .file:
            // Off-screen renders draw before `.task` runs: read the small PNG right away there.
            if let image = image ?? (module.isSnapshot ? imageURL.flatMap(Self.thumbnail) : nil) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            } else {
                symbolCard("photo")
            }
        case .text: symbolCard("text.alignleft")
        case .link: symbolCard("link")
        }
    }

    private var actions: some View {
        HStack(spacing: 2) {
            button(entry.isPinned ? "pin.slash" : "pin", entry.isPinned ? String(localized: "Unpin") : String(localized: "Pin")) {
                module.clipboard?.togglePin(entry.id)
            }
            button("tray.and.arrow.down", String(localized: "Keep on Shelf")) { module.keepClipboardEntry(entry) }
            button("airplayaudio", String(localized: "AirDrop")) { module.airDropClipboardEntry(entry) }
        }
        .padding(2)
        .background(.black.opacity(0.75), in: Capsule())
        .offset(y: 6)
    }

    private func button(_ symbol: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9.5, weight: .semibold))
                .frame(width: 17, height: 17)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(Text(title))
    }

    /// A 112-pixel preview, so ten copied images cost a few hundred KB, not a decoded 2048-pixel bitmap each.
    nonisolated static func thumbnail(_ url: URL) -> NSImage? {
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 112,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
        return NSImage(cgImage: image, size: CGSize(width: image.width / 2, height: image.height / 2))
    }

    private func symbolCard(_ symbol: String) -> some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(.white.opacity(0.1))
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
            }
    }

    private var accessibilityLabel: String {
        let pinned = entry.isPinned ? String(localized: "Pinned, ", comment: "Prefix for a pinned recent copy") : ""
        switch entry.item.kind {
        case .file: return pinned + String(localized: "Copied image")
        case .text: return pinned + String(localized: "Copied text, \(entry.item.displayName)")
        case .link: return pinned + String(localized: "Copied link, \(entry.item.displayName)")
        }
    }
}

private struct ShelfClipboardEmptyView: View {
    let isRunning: Bool

    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(.white.opacity(0.45))
                .accessibilityHidden(true)
            Text("Nothing copied yet")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
            Text(isRunning
                 ? String(localized: "Text, links and images you copy show up here. Passwords are skipped.")
                 : String(localized: "Turn on Remember what I copy in Shelf settings."))
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.45))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
