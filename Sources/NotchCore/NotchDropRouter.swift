import AppKit
import os

/// Passes drags that reach a notch view on to its module, in notch-body coordinates, and opens the
/// notch when the module wants the drag. Shared by the real notch and the app window's previews.
@MainActor
final class NotchDropRouter: NotchDropDelegate {
    weak var model: NotchViewModel?
    /// Which drags may drop in. The real notch takes only drags from other apps (`source == nil`), so
    /// an item dragged out of the Shelf never lands back in it; previews also take the app's own
    /// practice files.
    private let acceptsSource: @MainActor (Any?) -> Bool
    private let logger = Logger(subsystem: "io.github.sickpancake.PancakeNotch", category: "notch")

    init(acceptsSource: @escaping @MainActor (Any?) -> Bool = { $0 == nil }) {
        self.acceptsSource = acceptsSource
    }

    /// Converts a point in the hosted content to the expanded notch body, where modules lay out their drop zones.
    nonisolated static func bodyPoint(_ contentPoint: CGPoint, layout: NotchLayout) -> CGPoint {
        let origin = layout.bodyOrigin(for: .expanded)
        return CGPoint(x: contentPoint.x - origin.x, y: contentPoint.y - origin.y)
    }

    /// The model and the module that takes this drag (switching the open notch to it), if it may drop here.
    private func target(_ info: any NSDraggingInfo) -> (NotchViewModel, any NotchModule)? {
        guard let model, acceptsSource(info.draggingSource),
              let module = model.module(accepting: info.draggingPasteboard) else { return nil }
        return (model, module)
    }

    func dragEntered(_ info: any NSDraggingInfo, at contentPoint: CGPoint) -> NSDragOperation {
        guard let (model, module) = target(info) else { return [] }
        logger.info("Drag entered notch: \(info.draggingPasteboard.types?.map(\.rawValue) ?? [], privacy: .public)")
        let operation = module.dragUpdated(info, at: Self.bodyPoint(contentPoint, layout: model.layout))
        if !operation.isEmpty { model.dragEntered(focusing: module.moduleID) }
        return operation
    }

    func dragUpdated(_ info: any NSDraggingInfo, at contentPoint: CGPoint) -> NSDragOperation {
        guard let (model, module) = target(info) else { return [] }
        let operation = module.dragUpdated(info, at: Self.bodyPoint(contentPoint, layout: model.layout))
        if !operation.isEmpty, model.state != .expanded || model.selectedModule !== module || model.showsMenu {
            model.dragEntered(focusing: module.moduleID)
        }
        return operation
    }

    func dragExited() {
        model?.dragExited()
    }

    func performDrop(_ info: any NSDraggingInfo, at contentPoint: CGPoint) -> Bool {
        guard let (model, module) = target(info) else { return false }
        let accepted = module.performDrop(info, at: Self.bodyPoint(contentPoint, layout: model.layout))
        logger.info("Drop on notch accepted=\(accepted)")
        return accepted
    }

    func dragConcluded() {
        model?.dragConcluded()
    }
}
