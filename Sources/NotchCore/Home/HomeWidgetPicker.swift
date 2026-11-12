import SwiftUI

/// The grid-sized gallery hosted by Home's edit mode. The host owns insertion and dismissal.
@MainActor
struct HomeWidgetPicker: View {
    let kinds: [HomeWidgetKind]
    let resolver: HomeWidgetResolver
    let area: CGSize
    let add: (HomeWidgetKind) -> Void
    let close: () -> Void
    @Environment(\.homeWidgetPickerSnapshot) private var isSnapshot

    static func addable(layout: HomeLayout, resolver: HomeWidgetResolver) -> [HomeWidgetKind] {
        HomeWidgetKind.allCases.filter { !layout.contains($0) && !resolver.isTurnedOff($0) }
    }

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if kinds.isEmpty {
                    HomeWidgetEmptyLine(String(localized: "Every widget is on Home"))
                } else {
                    Group {
                        if isSnapshot {
                            // As with Shelf: off-screen rendering cannot draw a scroll view.
                            choices.frame(width: max(0, area.width - 32), alignment: .leading).clipped()
                        } else {
                            ScrollView(.horizontal) { choices }
                                .scrollIndicators(.hidden)
                        }
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel(Text("Widgets you can add"))
                }
            }
            .frame(maxWidth: .infinity)
            NotchRoundButton(symbol: "xmark", label: String(localized: "Back to Home"), size: 24, action: close)
        }
        .frame(width: area.width, height: area.height)
        .background(.black)
        .foregroundStyle(.white)
    }

    private var choices: some View {
        HStack(spacing: HomeWidgetMetrics.gap) {
            ForEach(kinds) { kind in
                HomeWidgetPickerChoice(kind: kind, resolver: resolver, area: area) { add(kind) }
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .padding(3)
    }
}

private struct HomeWidgetPickerSnapshotKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var homeWidgetPickerSnapshot: Bool {
        get { self[HomeWidgetPickerSnapshotKey.self] }
        set { self[HomeWidgetPickerSnapshotKey.self] = newValue }
    }
}

@MainActor
private struct HomeWidgetPickerChoice: View {
    let kind: HomeWidgetKind
    let resolver: HomeWidgetResolver
    let area: CGSize
    let add: () -> Void
    @State private var isHovered = false

    var body: some View {
        let size = HomeWidgetMetrics.frame(column: 0, row: 0, size: kind.defaultSize,
                                           cell: HomeWidgetMetrics.cellSize(in: area)).size
        let previewHeight = max(0, area.height - 36)
        let scale = min(1, 140 / max(1, size.width), previewHeight / max(1, size.height))
        let width = max(84, size.width * scale + 16)
        Button(action: add) {
            VStack(spacing: 6) {
                HomeWidgetCard(kind: kind, size: size, opens: false) {
                    resolver.content(kind, size: kind.defaultSize,
                                     context: HomeWidgetContext(size: size, isLive: false, isSnapshot: true,
                                                                isPractice: true,
                                                                fixedNow: Date(timeIntervalSince1970: 1_794_390_060)))
                } open: {}
                .background(.black, in: .rect(cornerRadius: HomeWidgetMetrics.cornerRadius, style: .continuous))
                .scaleEffect(scale)
                .frame(width: width - 16, height: previewHeight)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                Text(kind.title)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.white.opacity(isHovered ? 0.85 : 0.45))
                    .lineLimit(1)
                    .frame(height: 13)
            }
            .padding(.horizontal, 8)
            .frame(width: width, height: max(0, area.height - 6))
            .background(.white.opacity(isHovered ? 0.2 : 0.13),
                        in: .rect(cornerRadius: HomeWidgetMetrics.cornerRadius, style: .continuous))
            .contentShape(.rect(cornerRadius: HomeWidgetMetrics.cornerRadius))
        }
        .buttonStyle(PressableStyle())
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(kind.title))
        .accessibilityHint(Text("Adds it to Home"))
        .help(Text(kind.title))
    }
}
