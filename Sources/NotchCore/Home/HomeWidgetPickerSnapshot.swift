import SwiftUI

/// Lets the app's off-screen sheet draw the internal picker without exposing its hosting API.
@MainActor
public enum HomeWidgetPickerSnapshot {
    public static func view(model: NotchViewModel, kinds: [HomeWidgetKind], resolver: HomeWidgetResolver) -> AnyView {
        AnyView(NotchView(model: model).overlay(alignment: .top) {
            HomeWidgetPicker(kinds: kinds, resolver: resolver, area: HomeWidgetMetrics.gridArea(in: model.layout),
                             add: { _ in }, close: {})
                .environment(\.homeWidgetPickerSnapshot, true)
                .offset(y: model.layout.geometry.notchRect.height + HomeWidgetMetrics.topPadding)
        })
    }
}
