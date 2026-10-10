import AppKit
import NotchCore
import SwiftUI
import UniformTypeIdentifiers

/// A pretend Shelf for the app window's notch previews: a few example items when open and the tray
/// ear when shrunk. Nothing in it is real or clickable; the real Shelf stays in the real notch.
@MainActor
public final class ShelfPreviewModule: NotchModule {
    struct Sample: Identifiable {
        enum Look { case icon(UTType), note(String), link }
        let id: Int
        let name: String
        let look: Look
    }

    static let samples: [Sample] = [
        Sample(id: 0, name: String(localized: "Report.pdf"), look: .icon(.pdf)),
        Sample(id: 1, name: String(localized: "Holiday.jpg"), look: .icon(.jpeg)),
        Sample(id: 2, name: String(localized: "Pick up the cake"), look: .note(String(localized: "Pick up the cake at 5"))),
        Sample(id: 3, name: "github.com", look: .link),
    ]

    public init() {}

    public func attach(to notch: NotchViewModel?) {}

    public func expandedView(layout: NotchLayout) -> AnyView {
        AnyView(ShelfPreviewPanel(layout: ShelfLayout(layout)))
    }

    public func compactEars(layout: NotchLayout) -> CompactEars? {
        CompactEars(leading: AnyView(ShelfTrayBadge(count: Self.samples.count)))
    }
}

private struct ShelfPreviewPanel: View {
    let layout: ShelfLayout

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Text("Shelf")
                    .font(.system(size: 12, weight: .semibold))
                Text("\(ShelfPreviewModule.samples.count) items", comment: "Shelf header item count")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.5))
                Spacer(minLength: 0)
            }
            .frame(width: layout.headerSideWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: layout.bandHeight)
            .padding(.horizontal, ShelfLayout.sidePadding)

            HStack(spacing: ShelfLayout.tileSpacing) {
                ForEach(ShelfPreviewModule.samples) { sample in
                    tile(sample)
                }
                Spacer(minLength: 0)
            }
            .frame(width: layout.content.width, height: layout.content.height)
            .padding(.top, layout.content.minY - layout.bandHeight)
            Spacer(minLength: 0)
        }
        .frame(width: layout.body.width, height: layout.body.height, alignment: .top)
        .foregroundStyle(.white)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Shelf preview with example items"))
    }

    private func tile(_ sample: ShelfPreviewModule.Sample) -> some View {
        VStack(spacing: 5) {
            preview(sample.look)
                .frame(width: 56, height: 56)
            Text(sample.name)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(2)
                .truncationMode(.middle)
                .multilineTextAlignment(.center)
                .frame(width: ShelfLayout.tileSize.width - 8, height: 26, alignment: .top)
        }
        .padding(.top, 5)
        .frame(width: ShelfLayout.tileSize.width, height: ShelfLayout.tileSize.height, alignment: .top)
    }

    @ViewBuilder
    private func preview(_ look: ShelfPreviewModule.Sample.Look) -> some View {
        switch look {
        case .icon(let type):
            Image(nsImage: NSWorkspace.shared.icon(for: type))
                .resizable()
                .aspectRatio(contentMode: .fit)
        case .note(let text):
            Text(text)
                .font(.system(size: 8.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(4)
                .padding(6)
                .frame(width: 52, height: 52, alignment: .topLeading)
                .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        case .link:
            Image(systemName: "link")
                .font(.system(size: 20, weight: .medium))
                .frame(width: 52, height: 52)
                .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
    }
}
