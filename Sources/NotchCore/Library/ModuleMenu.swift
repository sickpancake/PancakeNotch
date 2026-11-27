import AppKit
import SwiftUI

/// The Library's words, in one place so the menu, the tiles and VoiceOver say the same thing.
enum LibraryText {
    static var open: String { String(localized: "Open", comment: "Module menu: show this module") }
    static var addFavorite: String { String(localized: "Add to Favorites", comment: "Module menu: give it a tab in the bar") }
    static var removeFavorite: String { String(localized: "Remove from Favorites", comment: "Module menu: take its tab out of the bar") }
    static var settings: String { String(localized: "Settings…", comment: "Module menu: opens its card in the PancakeNotch window") }
    static var turnOn: String { String(localized: "Turn On…", comment: "Module menu: opens a switched-off module's card in the PancakeNotch window") }
    static var barFull: String { String(localized: "The bar is full. Remove a favorite first.", comment: "Library: a favorite was refused") }
    static var noRoom: String { String(localized: "No room in the bar", comment: "Library: a favorite that has no tab") }

    static func note(_ note: LibraryNote) -> String {
        switch note {
        case .barFull: barFull
        }
    }
}

extension NotchViewModel {
    /// Favorites can be changed here: they only make tabs with "Home and tabs", and a practice notch in the
    /// app window doesn't change the real ones.
    var editsFavorites: Bool { arrangement.navigation == .tabsAndMenu && !homeLeavesOutMissing }
}

/// A module's right-click menu, the same on a bar tab, the tab beside the camera and a Library tile
/// (ADR-0045): Open · Add to / Remove from Favorites · Settings…, or Turn On… for a switched-off module.
@MainActor
enum ModuleMenu {
    /// `open` shows the module (from a tile it grows out of the tile). `nil` when nothing would be in it.
    static func make(model: NotchViewModel, moduleID: String, open: @escaping @MainActor () -> Void) -> NSMenu? {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.appearance = NSAppearance(named: .darkAqua)
        let isOn = model.modules.contains { $0.moduleID == moduleID }
        let canOpenSettings = model.openAppPage != nil
        guard isOn else {
            if canOpenSettings { menu.addItem(ActionItem(LibraryText.turnOn) { model.openModuleCard(moduleID) }) }
            return menu.items.isEmpty ? nil : menu
        }
        if model.currentPlace != .module(moduleID) {
            menu.addItem(ActionItem(LibraryText.open, action: open))
        }
        if model.editsFavorites {
            if !menu.items.isEmpty { menu.addItem(.separator()) }
            if model.arrangement.isFavorite(moduleID) {
                menu.addItem(ActionItem(LibraryText.removeFavorite) { model.toggleFavorite(moduleID) })
            } else if model.canAddFavorite {
                menu.addItem(ActionItem(LibraryText.addFavorite) { model.toggleFavorite(moduleID) })
            } else {
                // Refused in place: the item is dimmed and the line under it says why.
                let add = NSMenuItem(title: LibraryText.addFavorite, action: nil, keyEquivalent: "")
                add.isEnabled = false
                menu.addItem(add)
                let why = NSMenuItem(title: LibraryText.barFull, action: nil, keyEquivalent: "")
                why.isEnabled = false
                why.attributedTitle = NSAttributedString(string: LibraryText.barFull, attributes: [
                    .font: NSFont.menuFont(ofSize: NSFont.smallSystemFontSize),
                    .foregroundColor: NSColor.secondaryLabelColor
                ])
                menu.addItem(why)
            }
        }
        if canOpenSettings {
            if !menu.items.isEmpty { menu.addItem(.separator()) }
            menu.addItem(ActionItem(LibraryText.settings) { model.openModuleCard(moduleID) })
        }
        return menu.items.isEmpty ? nil : menu
    }

    /// A menu item that runs a closure (it is its own target, so nothing else needs keeping alive).
    private final class ActionItem: NSMenuItem {
        private let run: @MainActor () -> Void

        init(_ title: String, action: @escaping @MainActor () -> Void) {
            run = action
            super.init(title: title, action: #selector(choose), keyEquivalent: "")
            target = self
        }

        required init(coder: NSCoder) { fatalError("init(coder:) is not used") }

        @MainActor @objc private func choose() { run() }
    }
}

extension View {
    /// Right-click or Control-click shows the module's menu, holding the notch open while it's up. With
    /// `onClick` a plain click shows it too, under the view (the tab beside the camera, which is already
    /// showing its module). `anchor` lets the view show the menu from code, under it.
    func moduleMenu(model: NotchViewModel, moduleID: String, onClick: Bool = false,
                    anchor: ModuleMenuAnchor? = nil, open: (@MainActor () -> Void)? = nil) -> some View {
        overlay {
            // Off-screen pictures don't draw AppKit views (and nobody right-clicks them).
            if model.snapshotClock == nil {
                ModuleMenuCatcher(model: model, moduleID: moduleID, onClick: onClick, anchor: anchor,
                                  open: open ?? { model.select(moduleID) })
            }
        }
    }

    /// The menu's choices for VoiceOver, as actions on the element.
    func moduleMenuAccessibilityActions(model: NotchViewModel, moduleID: String) -> some View {
        modifier(ModuleMenuActions(model: model, moduleID: moduleID))
    }
}

private struct ModuleMenuActions: ViewModifier {
    let model: NotchViewModel
    let moduleID: String

    func body(content: Content) -> some View {
        let isOn = model.modules.contains { $0.moduleID == moduleID }
        let isFavorite = model.arrangement.isFavorite(moduleID)
        content
            .accessibilityActions {
                if isOn, model.editsFavorites, isFavorite || model.canAddFavorite {
                    Button(isFavorite ? LibraryText.removeFavorite : LibraryText.addFavorite) { model.toggleFavorite(moduleID) }
                }
                if model.openAppPage != nil {
                    Button(isOn ? LibraryText.settings : LibraryText.turnOn) { model.openModuleCard(moduleID) }
                }
            }
    }
}

/// Lies over a button and only answers right-clicks and Control-clicks, so ordinary clicks, hover and scrolls
/// reach the button underneath.
private struct ModuleMenuCatcher: NSViewRepresentable {
    let model: NotchViewModel
    let moduleID: String
    let onClick: Bool
    let anchor: ModuleMenuAnchor?
    let open: @MainActor () -> Void

    func makeNSView(context: Context) -> ModuleMenuCatcherView {
        let view = ModuleMenuCatcherView()
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: ModuleMenuCatcherView, context: Context) {
        view.model = model
        view.moduleID = moduleID
        view.onClick = onClick
        view.open = open
        anchor?.view = view
    }
}

/// Shows a module's menu from code, under the view it belongs to (for a press that isn't a click).
@MainActor
final class ModuleMenuAnchor {
    weak var view: ModuleMenuCatcherView?

    func showMenu() { view?.showMenuBelow() }
}

final class ModuleMenuCatcherView: NSView, NSMenuDelegate {
    weak var model: NotchViewModel?
    var moduleID = ""
    var onClick = false
    var open: (@MainActor () -> Void)?

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let event = NSApp.currentEvent,
              Self.wantsMenu(event) || (onClick && event.type == .leftMouseDown) else { return nil }
        return super.hitTest(point)
    }

    static func wantsMenu(_ event: NSEvent) -> Bool {
        event.type == .rightMouseDown || (event.type == .leftMouseDown && event.modifierFlags.contains(.control))
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let model, let open else { return nil }
        let menu = ModuleMenu.make(model: model, moduleID: moduleID, open: open)
        menu?.delegate = self
        return menu
    }

    override func mouseDown(with event: NSEvent) {
        guard event.modifierFlags.contains(.control) || onClick, let menu = menu(for: event) else {
            return super.mouseDown(with: event)
        }
        if event.modifierFlags.contains(.control) {
            NSMenu.popUpContextMenu(menu, with: event, for: self)
        } else {
            popUpBelow(menu)
        }
    }

    /// The menu under the view, as for a plain click.
    func showMenuBelow() {
        guard let model, let open, let menu = ModuleMenu.make(model: model, moduleID: moduleID, open: open) else { return }
        menu.delegate = self
        popUpBelow(menu)
    }

    /// A plain click: the menu hangs under the icon, like a pop-up button's.
    private func popUpBelow(_ menu: NSMenu) {
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: isFlipped ? bounds.maxY + 4 : -4), in: self)
    }

    func menuWillOpen(_ menu: NSMenu) { model?.menuShowingChanged(true) }
    func menuDidClose(_ menu: NSMenu) { model?.menuShowingChanged(false) }
}
