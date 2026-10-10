import AppKit
import NotchCore
import SwiftUI

/// The tall notch for one item: a mini text editor, a link editor, or a big file preview.
/// Header beside the notch: back arrow on the left, Copy and Remove on the right.
struct ShelfDetailView: View {
    let module: ShelfModule
    let item: ShelfItem
    let layout: ShelfLayout

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
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(title))
    }

    private var title: String {
        switch item.kind {
        case .text: String(localized: "Text")
        case .link: String(localized: "Link")
        case .file: String(localized: "File")
        }
    }

    private var header: some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                Button { module.closeDetail() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 24, height: 22)
                        .background(.white.opacity(0.14), in: Capsule())
                }
                .buttonStyle(.plain)
                .help(String(localized: "Back to the Shelf"))
                .accessibilityLabel(Text("Back to the Shelf"))
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
            }
            .frame(width: layout.headerSideWidth, alignment: .leading)

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                ShelfPillButton(title: module.copiedID == item.id ? String(localized: "Copied") : String(localized: "Copy")) {
                    module.copy([item])
                }
                Button { module.remove([item.id]) } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11, weight: .medium))
                        .frame(width: 28, height: 22)
                        .background(.white.opacity(0.14), in: Capsule())
                }
                .buttonStyle(.plain)
                .help(String(localized: "Remove from the Shelf"))
                .accessibilityLabel(Text("Remove from the Shelf"))
            }
            .frame(width: layout.headerSideWidth, alignment: .trailing)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch item.kind {
        case .text(let text):
            ShelfTextEditor(module: module, id: item.id, text: text, openIn: openInButton)
                .id(item.id)
        case .link(let url):
            ShelfLinkEditor(module: module, id: item.id, url: url, openIn: openInButton)
                .id(item.id)
        case .file:
            ShelfFilePreview(module: module, item: item, openIn: openInButton)
        }
    }

    private var openInButton: ShelfOpenInButton {
        let name = module.detailInfo?.defaultAppName
        let title: String = switch item.kind {
        case .link: name.map { String(localized: "Open in \($0)", comment: "Button; app name") } ?? String(localized: "Open Link")
        default: name.map { String(localized: "Open in \($0)", comment: "Button; app name") } ?? String(localized: "Open")
        }
        return ShelfOpenInButton(
            title: title,
            open: { module.open(item, with: module.detailInfo?.defaultApp) },
            choose: { module.showOpenWithMenu(for: item) }
        )
    }
}

// MARK: Text

private struct ShelfTextEditor: View {
    let module: ShelfModule
    let id: UUID
    let openIn: ShelfOpenInButton
    @State private var draft: String
    @FocusState private var isFocused: Bool

    init(module: ShelfModule, id: UUID, text: String, openIn: ShelfOpenInButton) {
        self.module = module
        self.id = id
        self.openIn = openIn
        _draft = State(initialValue: text)
    }

    var body: some View {
        VStack(spacing: 8) {
            Group {
                if module.isSnapshot {
                    // `ImageRenderer` can't draw the AppKit text view.
                    Text(draft)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(.horizontal, 5)
                } else {
                    TextEditor(text: $draft)
                        .scrollContentBackground(.hidden)
                        .scrollIndicators(.automatic)
                        .focused($isFocused)
                        .onChange(of: draft) { module.editText(id, draft) }
                        .onAppear { isFocused = true }
                        .accessibilityLabel(Text("Text"))
                }
            }
            .font(.system(size: 13))
            .tint(.white)
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.white.opacity(0.07))
                    .strokeBorder(.white.opacity(isFocused ? 0.3 : 0.12), lineWidth: 1)
            )

            HStack(spacing: 8) {
                openIn
                Spacer(minLength: 0)
                if let size = module.detailInfo?.size {
                    Text(size)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.45))
                        .monospacedDigit()
                }
            }
        }
    }
}

// MARK: Link

private struct ShelfLinkEditor: View {
    let module: ShelfModule
    let id: UUID
    let url: URL
    let openIn: ShelfOpenInButton
    @State private var draft: String
    @State private var isValid = true
    @FocusState private var isFocused: Bool

    init(module: ShelfModule, id: UUID, url: URL, openIn: ShelfOpenInButton) {
        self.module = module
        self.id = id
        self.url = url
        self.openIn = openIn
        _draft = State(initialValue: url.absoluteString)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "link")
                    .font(.system(size: 20, weight: .medium))
                    .frame(width: 44, height: 44)
                    .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(url.host(percentEncoded: false) ?? url.absoluteString)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                    Text("Link")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }

            Group {
                if module.isSnapshot {
                    Text(draft).frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    TextField(String(localized: "Address"), text: $draft)
                        .textFieldStyle(.plain)
                        .focused($isFocused)
                        .onChange(of: draft) { isValid = module.editLink(id, draft) }
                        .onSubmit { if isValid { module.open([module.detailItem].compactMap { $0 }) } }
                        .onAppear { isFocused = true }
                        .accessibilityLabel(Text("Address"))
                }
            }
            .font(.system(size: 13))
            .tint(.white)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(.white.opacity(0.07))
                    .strokeBorder(.white.opacity(!isValid ? 0.7 : isFocused ? 0.3 : 0.12), style: StrokeStyle(lineWidth: 1, dash: isValid ? [] : [4, 3]))
            )

            if !isValid {
                Label(String(localized: "Not a valid link. The last valid address is kept."), systemImage: "exclamationmark.triangle")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.7))
            }

            Spacer(minLength: 0)
            openIn
        }
    }
}

// MARK: File

private struct ShelfFilePreview: View {
    let module: ShelfModule
    let item: ShelfItem
    let openIn: ShelfOpenInButton

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            preview
                .frame(width: ShelfLargePreview.pointSize.width, height: ShelfLargePreview.pointSize.height)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(item.displayName)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                if let info = module.detailInfo {
                    Text([info.kind, info.size].compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.6))
                    if let path = info.path {
                        Text((path as NSString).abbreviatingWithTildeInPath)
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.4))
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    }
                }
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 6) {
                    openIn
                    HStack(spacing: 6) {
                        ShelfPillButton(title: String(localized: "Show in Finder")) { module.reveal([item]) }
                        ShelfPillButton(title: String(localized: "Quick Look")) { module.quickLook([item]) }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var preview: some View {
        if let image = module.largePreview.image {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.white.opacity(0.07))
                .overlay {
                    Image(systemName: "doc")
                        .font(.system(size: 34, weight: .light))
                        .foregroundStyle(.white.opacity(0.5))
                }
        }
    }
}

// MARK: Open in…

/// "Open in Preview" plus a small arrow listing the other apps that can open it.
struct ShelfOpenInButton: View {
    let title: String
    let open: () -> Void
    let choose: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: open) {
                Text(title)
                    .font(.system(size: 11.5, weight: .semibold))
                    .lineLimit(1)
                    .padding(.leading, 11)
                    .padding(.trailing, 8)
                    .frame(height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Rectangle()
                .fill(.black.opacity(0.25))
                .frame(width: 1, height: 14)
                .accessibilityHidden(true)
            Button(action: choose) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(String(localized: "Open with another app"))
            .accessibilityLabel(Text("Open with another app"))
        }
        .foregroundStyle(.black)
        .background(.white, in: Capsule())
        .fixedSize()
    }
}
