import Foundation
import NotchCore
import Testing
@testable import ModuleShelf

@MainActor
struct ShelfModuleTests {
    func makeModule(_ fixture: ShelfFixture, policy: ShelfSettings.DuplicatePolicy = .ask) -> (ShelfModule, NotchViewModel) {
        let defaults = UserDefaults(suiteName: "ShelfModuleTests-\(UUID().uuidString)")!
        let settings = ShelfSettings(defaults: defaults)
        settings.duplicatePolicy = policy
        let module = ShelfModule(store: fixture.makeStore(), settings: settings)
        let notch = NotchViewModel(
            layout: NotchLayout(geometry: .simulated(in: CGRect(x: 0, y: 0, width: 1512, height: 982))),
            pointerLocation: { CGPoint(x: 756, y: 300) }
        )
        notch.module = module
        return (module, notch)
    }

    @Test func fullShelfHoldsTheRestAndAddsThemOnceThereIsRoom() throws {
        let fixture = try ShelfFixture()
        let (module, notch) = makeModule(fixture)
        let inputs = try fixture.files(22)
        module.offer(inputs)
        #expect(module.prompt == .full(pending: Array(inputs.suffix(2))))
        #expect(notch.restingState == .compact)
        #expect(module.holdsOpen)

        module.startChoosing()
        module.selection = Set(module.store.items.prefix(3).map(\.id))
        module.removeChosen()

        #expect(module.prompt == nil)
        #expect(module.store.items.count == 19)
        #expect(module.store.items.filter { $0.displayName == "f20.txt" }.count == 1)
        #expect(notch.restingState == .closed)
        #expect(!module.holdsOpen)
    }

    @Test func clearingForPendingAddsEverythingWaiting() throws {
        let fixture = try ShelfFixture()
        let (module, _) = makeModule(fixture)
        module.offer(try fixture.files(25))
        module.clearForPending()
        #expect(module.prompt == nil)
        #expect(module.store.items.count == 5)
    }

    @Test func duplicatePromptAndRememberedAnswer() throws {
        let fixture = try ShelfFixture()
        let (module, _) = makeModule(fixture)
        module.offer([.text("a"), .text("b")])
        module.offer([.text("a"), .text("c")])
        #expect(module.prompt == .duplicates(inputs: [.text("a"), .text("c")], count: 1))

        module.answerDuplicates(.moveToFront, remember: true)
        #expect(module.prompt == nil)
        #expect(module.store.items.map(\.displayName) == ["c", "a", "b"])
        #expect(module.settings.duplicatePolicy == .moveToFront)
    }

    @Test func dismissingDuplicatesAddsOnlyTheNewOnes() throws {
        let fixture = try ShelfFixture()
        let (module, _) = makeModule(fixture)
        module.offer([.text("a")])
        module.offer([.text("a"), .text("new")])
        module.dismissPrompt()
        #expect(module.store.items.map(\.displayName) == ["new", "a"])
    }

    @Test func closingTheNotchDiscardsHeldItems() throws {
        let fixture = try ShelfFixture()
        let (module, notch) = makeModule(fixture)
        notch.open()
        module.offer(try fixture.files(21))
        notch.close()
        #expect(module.prompt == nil)
        #expect(module.store.items.count == 20)
    }

    @Test func shiftClickSelectsARange() throws {
        let fixture = try ShelfFixture()
        let (module, _) = makeModule(fixture)
        module.offer([.text("a"), .text("b"), .text("c"), .text("d")])
        let ids = module.store.items.map(\.id)
        module.click(ids[0], modifiers: [])
        module.click(ids[2], modifiers: .shift)
        #expect(module.selection == Set(ids[0...2]))
        module.click(ids[3], modifiers: .command)
        #expect(module.selection.count == 4)
        #expect(module.targets(for: ids[1]).count == 4)
    }

    @Test func clearAllNeedsASecondClick() throws {
        let fixture = try ShelfFixture()
        let (module, _) = makeModule(fixture)
        module.offer([.text("a")])
        module.clearAll()
        #expect(module.store.items.count == 1)
        #expect(module.confirmingClear)
        module.clearAll()
        #expect(module.store.items.isEmpty)
    }

    @Test func dragOutRemovesOnlyWhenAskedTo() throws {
        let fixture = try ShelfFixture()
        let (module, _) = makeModule(fixture)
        module.offer([.text("a")])
        let id = try #require(module.store.items.first?.id)
        module.setDraggingOut(true)
        module.dragOutEnded([id], operation: .copy)
        #expect(module.store.items.count == 1)
        #expect(!module.holdsOpen)

        module.settings.removeAfterDragOut = true
        module.dragOutEnded([id], operation: .copy)
        #expect(module.store.items.isEmpty)
    }

    @Test func dragOutIsCopyUnlessMoveIsChosen() throws {
        let fixture = try ShelfFixture()
        let (module, _) = makeModule(fixture)
        #expect(module.dragOperations(outside: true) == .copy)
        #expect(module.dragOperations(outside: false) == [])
        module.settings.dragOutMode = .move
        #expect(module.dragOperations(outside: true).contains(.move))
    }
}
