import AppKit
import NotchCore
import SwiftUI

/// The open Shelf: header beside the notch, then the tile row, drop zones or a card (ADR-0013).
/// Visuals are plain SwiftUI so the off-screen snapshot can draw them; mouse handling for tiles is an
/// invisible AppKit overlay (`ShelfTileInteraction`).
struct ShelfView: View {
    let module: ShelfModule
    let layout: ShelfLayout

    var body: some View {
        VStack(spacing: 0) {
            ShelfHeader(module: module, layout: layout)
                .frame(height: layout.bandHeight)
                .padding(.horizontal, ShelfLayout.sidePadding)
            content
                .frame(width: layout.content.width, height: layout.content.height)
                .padding(.top, layout.content.minY - layout.bandHeight)
            Spacer(minLength: 0)
        }
        .frame(width: layout.body.width, height: layout.body.height, alignment: .top)
        // Clicks on empty space clear the selection instead of shrinking the notch.
        .background(Color.black.opacity(0.001).onTapGesture { module.backgroundClicked() })
        .foregroundStyle(.white)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Shelf"))
    }

    @ViewBuilder
    private var content: some View {
        if let zone = module.dropZone {
            ShelfDropZones(zone: zone, showsAirDrop: module.dragCanAirDrop, layout: layout)
        } else if let prompt = module.prompt, !prompt.isChoosing {
            ShelfPromptCard(module: module, prompt: prompt)
        } else if module.store.items.isEmpty {
            ShelfEmptyView()
        } else {
            ShelfTileRow(module: module)
        }
    }
}

private extension ShelfModule.Prompt {
    var isChoosing: Bool {
        if case .choosing = self { return true }
        return false
    }
}

// MARK: Header

private struct ShelfHeader: View {
    let module: ShelfModule
    let layout: ShelfLayout

    var body: some View {
        let count = module.store.items.count
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                if case .choosing = module.prompt {
                    Text("Choose items to remove")
                        .font(.system(size: 12, weight: .semibold))
                } else {
                    Text("Shelf")
                        .font(.system(size: 12, weight: .semibold))
                    if count > 0 {
                        Text(count == 1 ? String(localized: "1 item") : String(localized: "\(count) items", comment: "Shelf item count in the notch header"))
                            .font(.system(size: 11.5))
                            .foregroundStyle(.white.opacity(0.5))
                            .monospacedDigit()
                    }
                }
            }
            .lineLimit(1)
            .frame(width: layout.headerSideWidth, alignment: .leading)

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                if case .choosing = module.prompt {
                    ShelfPillButton(title: String(localized: "Cancel")) {
                        if case .choosing(let pending) = module.prompt { module.prompt = .full(pending: pending) }
                        module.selection = []
                    }
                    ShelfPillButton(
                        title: String(localized: "Remove \(module.selection.count)", comment: "Remove the chosen shelf items"),
                        prominent: true
                    ) { module.removeChosen() }
                    .disabled(module.selection.isEmpty)
                } else if count > 0, module.dropZone == nil, module.prompt == nil {
                    ShelfDragAllHandle(module: module)
                    ShelfPillButton(
                        title: !module.confirmingClear ? String(localized: "Clear all")
                            : count == 1 ? String(localized: "Clear 1 item?")
                            : String(localized: "Clear \(count) items?", comment: "Second click confirms clearing the shelf"),
                        prominent: module.confirmingClear
                    ) { module.clearAll() }
                }
            }
            .frame(width: layout.headerSideWidth, alignment: .trailing)
        }
    }
}

/// Drags every item on the shelf at once.
private struct ShelfDragAllHandle: View {
    let module: ShelfModule

    var body: some View {
        Image(systemName: "square.stack.3d.up")
            .font(.system(size: 12, weight: .medium))
            .frame(width: 28, height: 22)
            .background(.white.opacity(0.12), in: Capsule())
            .overlay { if !module.isSnapshot { ShelfTileInteraction(module: module, itemID: nil) } }
            .help(String(localized: "Drag all items"))
            .accessibilityElement()
            .accessibilityLabel(Text("Drag all items"))
    }
}

struct ShelfPillButton: View {
    let title: String
    var prominent = false
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11.5, weight: .semibold))
                .lineLimit(1)
                .foregroundStyle(prominent ? .black : .white)
                .padding(.horizontal, 10)
                .frame(height: 22)
                .background(prominent ? .white : .white.opacity(0.14), in: Capsule())
                .opacity(isEnabled ? 1 : 0.4)
        }
        .buttonStyle(.plain)
    }
}

// MARK: Tiles

private struct ShelfTileRow: View {
    let module: ShelfModule

    var body: some View {
        if module.isSnapshot {
            tiles.fixedSize(horizontal: true, vertical: false)
                .frame(maxWidth: .infinity, alignment: .leading)
                .clipped()
        } else {
            ScrollView(.horizontal, showsIndicators: false) { tiles }
        }
    }

    private var tiles: some View {
            HStack(spacing: ShelfLayout.tileSpacing) {
                ForEach(module.store.items) { item in
                    ShelfTile(
                        module: module,
                        item: item,
                        thumbnail: module.thumbnails.images[item.id],
                        isSelected: module.selection.contains(item.id),
                        isChoosing: module.prompt?.isChoosing ?? false,
                        isCopied: module.copiedID == item.id
                    )
                }
            }
            .frame(maxHeight: .infinity)
    }
}

struct ShelfTile: View {
    let module: ShelfModule
    let item: ShelfItem
    let thumbnail: NSImage?
    let isSelected: Bool
    let isChoosing: Bool
    let isCopied: Bool

    var body: some View {
        VStack(spacing: 5) {
            preview
                .frame(width: 56, height: 56)
                .overlay(alignment: .topTrailing) {
                    if isChoosing {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white, .black)
                            .background(Circle().fill(.black.opacity(0.6)))
                            .offset(x: 5, y: -5)
                    }
                }
                .overlay {
                    if isCopied {
                        Text("Copied")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 7)
                            .frame(height: 18)
                            .background(.white, in: Capsule())
                    }
                }
            Text(item.displayName)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.white.opacity(isSelected ? 1 : 0.8))
                .lineLimit(2)
                .truncationMode(.middle)
                .multilineTextAlignment(.center)
                .frame(width: ShelfLayout.tileSize.width - 8, height: 26, alignment: .top)
        }
        .padding(.top, 5)
        .frame(width: ShelfLayout.tileSize.width, height: ShelfLayout.tileSize.height, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.white.opacity(isSelected ? 0.16 : 0))
        )
        .overlay {
            if !module.isSnapshot {
                ShelfTileInteraction(module: module, itemID: item.id).accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityLabel))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityAction { module.activate(item.id) }
        .accessibilityAction(named: Text(item.isFile ? "Open" : "Copy")) { module.activate(item.id) }
        .accessibilityAction(named: Text("Quick Look")) { module.quickLook([item]) }
        .accessibilityAction(named: Text("Remove")) { module.remove([item.id]) }
    }

    @ViewBuilder
    private var preview: some View {
        switch item.kind {
        case .file:
            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                symbolCard("doc")
            }
        case .text(let text):
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(.white.opacity(0.1))
                .overlay(alignment: .topLeading) {
                    Text(text)
                        .font(.system(size: 7.5))
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(5)
                        .padding(6)
                }
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "text.quote")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.5))
                        .padding(5)
                }
        case .link:
            symbolCard("link")
        }
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
        switch item.kind {
        case .file: String(localized: "File, \(item.displayName)")
        case .text: String(localized: "Text, \(item.displayName)")
        case .link: String(localized: "Link, \(item.displayName)")
        }
    }
}

private struct ShelfEmptyView: View {
    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(.white.opacity(0.45))
                .accessibilityHidden(true)
            Text("Drop files here")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
            Text("Files, images, text and links stay here until you drag them out.")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.45))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: Dropping

/// Shown while a drag is over the open notch: the Shelf, and AirDrop when the content can be sent.
struct ShelfDropZones: View {
    let zone: ShelfModule.DropZone
    let showsAirDrop: Bool
    let layout: ShelfLayout

    var body: some View {
        HStack(spacing: 8) {
            target(
                symbol: "tray.and.arrow.down.fill",
                title: String(localized: "Drop to add to Shelf"),
                isTargeted: zone == .shelf
            )
            if showsAirDrop {
                target(
                    symbol: "dot.radiowaves.left.and.right",
                    title: String(localized: "AirDrop"),
                    isTargeted: zone == .airDrop
                )
                .frame(width: ShelfLayout.airDropWidth)
            }
        }
    }

    private func target(symbol: String, title: String, isTargeted: Bool) -> some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(.white.opacity(isTargeted ? 0.14 : 0.04))
            .strokeBorder(.white.opacity(isTargeted ? 0.85 : 0.3), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            .overlay {
                VStack(spacing: 7) {
                    Image(systemName: symbol)
                        .font(.system(size: 20, weight: .medium))
                        .accessibilityHidden(true)
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(.white.opacity(isTargeted ? 1 : 0.6))
            }
            .accessibilityElement(children: .combine)
    }
}

// MARK: Cards

/// The duplicate question and the "Shelf is full" warning, shown inside the notch.
struct ShelfPromptCard: View {
    let module: ShelfModule
    let prompt: ShelfModule.Prompt
    @State private var remember = false

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .medium))
                .frame(width: 30)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) { buttons }
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
        .overlay(alignment: .topTrailing) {
            Button { module.dismissPrompt() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 22, height: 22)
                    .background(.white.opacity(0.12), in: Circle())
            }
            .buttonStyle(.plain)
            .padding(8)
            .accessibilityLabel(Text("Close"))
        }
        .accessibilityElement(children: .contain)
    }

    private var symbol: String {
        if case .duplicates = prompt { return "square.on.square" }
        return "tray.full"
    }

    private var title: String {
        switch prompt {
        case .duplicates(_, let count):
            String(localized: "\(count) already on the Shelf", comment: "Duplicate prompt title; count of items")
        case .full, .choosing:
            String(localized: "The Shelf is full")
        }
    }

    private var message: String {
        switch prompt {
        case .duplicates(_, let count):
            count == 1
                ? String(localized: "Move it to the front, or add it again?")
                : String(localized: "Move them to the front, or add them again?")
        case .full(let pending), .choosing(let pending):
            String(localized: "\(pending.count) didn't fit. Make room and they'll be added.", comment: "Shelf full card; count of waiting items")
        }
    }

    @ViewBuilder
    private var buttons: some View {
        switch prompt {
        case .duplicates:
            ShelfPillButton(title: String(localized: "Move to front"), prominent: true) {
                module.answerDuplicates(.moveToFront, remember: remember)
            }
            ShelfPillButton(title: String(localized: "Add again")) {
                module.answerDuplicates(.addAgain, remember: remember)
            }
            Button { remember.toggle() } label: {
                HStack(spacing: 4) {
                    Image(systemName: remember ? "checkmark.square.fill" : "square")
                    Text("Don't ask again")
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.75))
            }
            .buttonStyle(.plain)
            .padding(.leading, 4)
            .accessibilityAddTraits(remember ? .isSelected : [])
        case .full, .choosing:
            ShelfPillButton(title: String(localized: "Clear all"), prominent: true) { module.clearForPending() }
            ShelfPillButton(title: String(localized: "Choose items to remove")) { module.startChoosing() }
        }
    }
}

// MARK: Compact

/// Ears shown while the shelf is full, the only time the Shelf shows on a closed notch.
struct ShelfFullEars: View {
    let layout: NotchLayout

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: "tray.full.fill")
                .font(.system(size: 11, weight: .medium))
                .frame(width: layout.compactEarWidth)
            Spacer(minLength: 0)
            Text("Full")
                .font(.system(size: 10, weight: .semibold))
                .frame(width: layout.compactEarWidth)
        }
        .foregroundStyle(.white.opacity(0.85))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Shelf is full"))
    }
}
