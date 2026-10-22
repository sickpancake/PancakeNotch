import AgentsCore
import AppKit
import Foundation
import NotchCore
import Testing
@testable import ModuleAgents

@MainActor
struct AIUsageModuleTests {
    func makeModule(peeks: Bool = true) -> (AIUsageModule, NotchViewModel) {
        let module = AIUsageModule(center: .practice(), peeks: peeks)
        let notch = NotchViewModel(
            layout: NotchLayout(geometry: .simulated(in: CGRect(x: 0, y: 0, width: 1512, height: 982))),
            state: .expanded,
            pointerLocation: { CGPoint(x: 756, y: 100) }
        )
        notch.module = module
        return (module, notch)
    }

    @Test func theSymbolsExist() {
        let module = AIUsageModule(center: .practice())
        #expect(NSImage(systemSymbolName: module.symbol, accessibilityDescription: nil) != nil)
        #expect(NSImage(systemSymbolName: AgentsModule(center: .practice()).symbol, accessibilityDescription: nil) != nil)
        for tool in AgentTool.allCases {
            #expect(NSImage(systemSymbolName: tool.symbol, accessibilityDescription: nil) != nil)
        }
    }

    @Test func theMenuLineFollowsTheChosenAccount() {
        let (module, _) = makeModule()
        // The practice center starts on the personal account, whose session has 63% left.
        #expect(module.menuStatus == "Session 63% left")
        module.center.selection = .all
        #expect(module.menuStatus == "All accounts")
    }

    @Test func anAccountUnderTenPercentTakesAnEar() {
        let (module, _) = makeModule()
        #expect(module.isActive)
        #expect(module.accessibilityStatus?.contains("Work") == true)
    }

    @Test func theMenuHoldsTheNotchOpenUntilItCloses() {
        let (module, _) = makeModule()
        #expect(!module.holdsOpen)
        module.openMenu()
        #expect(module.holdsOpen)
        module.choose(.all)
        #expect(!module.holdsOpen)
        #expect(module.center.selection == .all)
    }

    @Test func leavingTheModuleClosesTheMenu() {
        let (module, _) = makeModule()
        module.openMenu()
        module.userSwitchedAway()
        #expect(!module.holdsOpen)
        module.openMenu()
        module.notchDidClose()
        #expect(!module.holdsOpen)
    }

    @Test func theAccountMenuCanBeUsedWithTheKeyboard() throws {
        let (module, notch) = makeModule()
        _ = notch
        func key(_ code: UInt16) throws -> NSEvent {
            try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                          windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "",
                                          isARepeat: false, keyCode: code))
        }
        module.openMenu()
        let initial = module.focusedAccount
        #expect(module.handleKey(try key(125)))
        #expect(module.focusedAccount != initial)
        let choice = module.focusedAccount
        #expect(module.handleKey(try key(36)))
        #expect(module.center.selection == choice)
        #expect(!module.holdsOpen)
        module.openMenu()
        #expect(module.handleKey(try key(53)))
        #expect(!module.holdsOpen)
    }

    @Test func aCopyThatDoesNotPeekLeavesTheCenterAlone() {
        let (peeking, _) = makeModule()
        #expect(peeking.center.onNearLimit != nil)
        let (quiet, _) = makeModule(peeks: false)
        #expect(quiet.center.onNearLimit == nil)
    }
}
