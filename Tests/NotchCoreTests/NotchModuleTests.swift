import AppKit
import SwiftUI
import Testing
@testable import NotchCore

/// A stand-in module that records what the notch tells it.
@MainActor
final class FakeModule: NotchModule {
    weak var notch: NotchViewModel?
    var holdsOpen = false
    var opens = 0
    var closes = 0
    var dragEnds = 0

    func attach(to notch: NotchViewModel?) { self.notch = notch }
    func expandedView(layout: NotchLayout) -> AnyView { AnyView(EmptyView()) }
    func notchDidOpen() { opens += 1 }
    func notchDidClose() { closes += 1 }
    func dragEnded() { dragEnds += 1 }
    func handleKey(_ event: NSEvent) -> Bool { event.charactersIgnoringModifiers == " " }
}

@MainActor
struct NotchModuleTests {
    let layout = NotchLayout(geometry: .simulated(in: CGRect(x: 0, y: 0, width: 1512, height: 982)))
    /// Well below the notch, outside every window frame.
    static let outside = CGPoint(x: 756, y: 300)
    /// On the notch itself.
    static let inside = CGPoint(x: 756, y: 975)

    func makeModel(state: NotchState = .closed, pointer: CGPoint = outside) -> (NotchViewModel, FakeModule) {
        let model = NotchViewModel(
            layout: layout,
            state: state,
            behavior: NotchBehavior(openDelay: .milliseconds(10), closeDelay: .milliseconds(10)),
            collapseLinger: .milliseconds(10),
            pointerLocation: { pointer }
        )
        let module = FakeModule()
        model.module = module
        return (model, module)
    }

    @Test func attachingAndDetachingTellsTheModule() {
        let (model, module) = makeModel()
        #expect(module.notch === model)
        model.module = nil
        #expect(module.notch == nil)
    }

    @Test func dragOpensImmediately() {
        let (model, module) = makeModel()
        model.dragEntered()
        #expect(model.state == .expanded)
        #expect(module.opens == 1)
    }

    @Test func dragLeavingCloses() async throws {
        let (model, module) = makeModel()
        model.dragEntered()
        model.dragExited()
        try await Task.sleep(for: .milliseconds(300))
        #expect(model.state == .closed)
        #expect(module.dragEnds == 1)
        #expect(module.closes == 1)
    }

    @Test func dropWithPointerStillOnNotchStaysOpen() async throws {
        let (model, _) = makeModel(pointer: Self.inside)
        model.dragEntered()
        model.dragConcluded()
        try await Task.sleep(for: .milliseconds(300))
        #expect(model.state == .expanded)
    }

    @Test func holdKeepsNotchOpenUntilReleased() async throws {
        let (model, module) = makeModel(state: .expanded)
        module.holdsOpen = true
        model.hoverChanged(false)
        model.tap()
        try await Task.sleep(for: .milliseconds(300))
        #expect(model.state == .expanded)

        module.holdsOpen = false
        model.holdReleased()
        try await Task.sleep(for: .milliseconds(300))
        #expect(model.state == .closed)
    }

    @Test func releasingHoldWithPointerInsideStaysOpen() async throws {
        let (model, module) = makeModel(state: .expanded, pointer: Self.inside)
        module.holdsOpen = false
        model.holdReleased()
        try await Task.sleep(for: .milliseconds(300))
        #expect(model.state == .expanded)
    }

    @Test func hidingMidDragClearsTheDrag() {
        let (model, module) = makeModel()
        model.dragEntered()
        model.reset()
        #expect(model.state == .closed)
        #expect(module.dragEnds == 1)
        #expect(module.closes == 1)
    }

    @Test func closingReleasesKeyFocus() {
        let (model, _) = makeModel()
        var released = 0
        model.releaseKeyFocus = { released += 1 }
        model.open()
        model.close()
        #expect(released == 1)
    }

    @Test func keysGoToModuleThenEscapeCloses() throws {
        let (model, _) = makeModel(state: .expanded)
        let space = try #require(Self.key(" ", code: 49))
        #expect(model.handleKey(space))
        #expect(model.state == .expanded)
        let escape = try #require(Self.key("\u{1b}", code: 53))
        #expect(model.handleKey(escape))
        #expect(model.state == .closed)
    }

    static func key(_ characters: String, code: UInt16) -> NSEvent? {
        NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
            context: nil, characters: characters, charactersIgnoringModifiers: characters,
            isARepeat: false, keyCode: code
        )
    }
}
