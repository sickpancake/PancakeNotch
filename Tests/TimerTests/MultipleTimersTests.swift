import AppKit
import Foundation
import NotchCore
import Testing
@testable import ModuleTimer
@testable import TimerCore

/// Several named timers at once (issue #70): each runs on its own end date, rings once, and the notch
/// shows the one ending soonest (or the oldest Done) with the rest counted.
@MainActor
struct MultipleTimersTests {
    func makeCenter(defaults: UserDefaults? = nil) -> (TimerCenter, TestClock, () -> [String]) {
        let clock = TestClock()
        let center = TimerCenter(defaults: defaults, now: { clock.now })
        var finished: [String] = []
        center.onFinish = { finished.append($0.name) }
        return (center, clock, { finished })
    }

    @Test func severalRunAtOnceWithNames() {
        let (center, _, _) = makeCenter()
        center.startTimer(seconds: 600, name: "  Laundry  ")
        center.startTimer(seconds: 300, name: "Pasta")
        center.startTimer(seconds: 900)
        #expect(center.timers.count == 3)
        #expect(center.timers.map(\.name) == ["Laundry", "Pasta", ""])
        #expect(center.sortedTimers.map(\.name) == ["Pasta", "Laundry", ""])
        #expect(center.timer.name == "Pasta")
        #expect(center.hasActivity)
    }

    @Test func namesAreCut() {
        let (center, _, _) = makeCenter()
        center.startTimer(seconds: 60, name: String(repeating: "a", count: 40))
        #expect(center.timer.name.count == TimerSettings.nameLength)
    }

    @Test func eachEndRingsOnceInOrder() {
        let (center, clock, finished) = makeCenter()
        center.startTimer(seconds: 600, name: "Laundry")
        center.startTimer(seconds: 300, name: "Pasta")
        clock.advance(301)
        center.timeMayHaveJumped()
        center.checkFinished()
        #expect(finished() == ["Pasta"])
        #expect(center.timer.name == "Pasta")
        #expect(center.timer.isDone)
        clock.advance(300)
        center.timeMayHaveJumped()
        center.timeMayHaveJumped()
        #expect(finished() == ["Pasta", "Laundry"])
        // Done alerts queue: the oldest shows; stopping it shows the next.
        #expect(center.doneTimers.map(\.name) == ["Pasta", "Laundry"])
        center.stopTimer()
        #expect(center.timer.name == "Laundry")
        center.stopTimer()
        #expect(center.timers.isEmpty)
        #expect(center.timer.isIdle)
        #expect(!center.hasActivity)
    }

    /// Two that end while the Mac sleeps both ring on wake, the earlier one first.
    @Test func bothEndingInOneWakeRingBoth() {
        let (center, clock, finished) = makeCenter()
        center.startTimer(seconds: 600, name: "B")
        center.startTimer(seconds: 300, name: "A")
        clock.advance(3_600)
        center.timeMayHaveJumped()
        #expect(finished() == ["A", "B"])
    }

    @Test func perTimerControlsLeaveTheOthersAlone() throws {
        let (center, clock, _) = makeCenter()
        let pasta = try #require(center.startTimer(seconds: 300, name: "Pasta"))
        let laundry = try #require(center.startTimer(seconds: 600, name: "Laundry"))
        center.pauseTimer(id: laundry)
        clock.advance(100)
        #expect(center.timer(id: laundry)?.remaining(at: clock.now) == 600)
        #expect(center.timer(id: pasta)?.remaining(at: clock.now) == 200)
        center.addMinute(id: pasta)
        #expect(center.timer(id: pasta)?.remaining(at: clock.now) == 260)
        center.addMinute(id: laundry)
        #expect(center.timer(id: laundry)?.remaining(at: clock.now) == 660)
        center.cancelTimer(id: pasta)
        #expect(center.timers.map(\.id) == [laundry])
        center.resumeTimer(id: laundry)
        #expect(center.timer.isRunning)
    }

    @Test func runningComesBeforePaused() throws {
        let (center, _, _) = makeCenter()
        let soon = try #require(center.startTimer(seconds: 60, name: "Soon"))
        center.startTimer(seconds: 600, name: "Later")
        center.pauseTimer(id: soon)
        #expect(center.timer.name == "Later")
        #expect(center.sortedTimers.map(\.name) == ["Later", "Soon"])
    }

    @Test func noMoreThanTheMost() {
        let (center, _, _) = makeCenter()
        for index in 0 ..< TimerCenter.mostTimers { center.startTimer(seconds: 60 + Double(index)) }
        #expect(!center.canAddTimer)
        #expect(center.startTimer(seconds: 60) == nil)
        #expect(center.timers.count == TimerCenter.mostTimers)
    }

    @Test func savedAndRestored() {
        let defaults = scratchDefaults()
        let (center, clock, _) = makeCenter(defaults: defaults)
        center.startTimer(seconds: 600, name: "Laundry")
        center.startTimer(seconds: 60, name: "Pasta")
        let reopened = TimerCenter(defaults: defaults, now: { clock.now + 120 })
        #expect(reopened.timers.map(\.name) == ["Laundry", "Pasta"])
        #expect(reopened.timer.name == "Pasta")
        #expect(reopened.timer.isDone)
        #expect(reopened.finishedWhileAway)
        #expect(reopened.timer(id: center.timers[0].id)?.isRunning == true)
    }

    /// A save from before several timers (one `timer`, no id or name) still opens.
    @Test func readsTheOldOneTimerSave() throws {
        let defaults = scratchDefaults()
        let end = Date(timeIntervalSinceReferenceDate: 900_000_300)
        let old = """
        {"timer":{"phase":{"running":{"end":\(end.timeIntervalSinceReferenceDate)}},"duration":300,"total":300},
         "stopwatch":\(String(data: try JSONEncoder().encode(Stopwatch()), encoding: .utf8)!)}
        """
        defaults.set(Data(old.utf8), forKey: TimerCenter.Keys.state)
        let center = TimerCenter(defaults: defaults, now: { Date(timeIntervalSinceReferenceDate: 900_000_000) })
        #expect(center.timers.count == 1)
        #expect(center.timer.isRunning)
        #expect(center.timer.name.isEmpty)
        #expect(center.timer.remaining(at: Date(timeIntervalSinceReferenceDate: 900_000_000)) == 300)
    }

    // MARK: The module

    @Test func moduleStatusCountsTheOthers() {
        let clock = TestClock()
        let center = TimerCenter(now: { clock.now })
        let module = TimerModule(center: center, settings: TimerSettings(defaults: scratchDefaults()), presents: false)
        center.startTimer(seconds: 300, name: "Pasta")
        center.startTimer(seconds: 600, name: "Laundry")
        #expect(module.menuStatus?.hasPrefix("2 timers") == true)
        #expect(module.accessibilityStatus?.hasPrefix("Pasta, 5 minutes left") == true)
        #expect(module.accessibilityStatus?.contains("1 more timers") == true)
        #expect(TimerPane.Page(module) == .list)
    }

    @Test func newTimerPageAndNamedStart() {
        let clock = TestClock()
        let center = TimerCenter(now: { clock.now })
        let module = TimerModule(center: center, settings: TimerSettings(defaults: scratchDefaults()), presents: false)
        #expect(TimerPane.Page(module) == .setup)
        module.newName = "Pasta"
        module.wheelSeconds = 300
        module.startWheels()
        #expect(center.timer.name == "Pasta")
        #expect(module.newName.isEmpty)
        #expect(TimerPane.Page(module) == .counting)
        module.beginAdding()
        #expect(TimerPane.Page(module) == .setup)
        module.cancelAdding()
        #expect(TimerPane.Page(module) == .counting)
        module.beginAdding()
        module.startPreset(TimerPreset(id: UUID(), seconds: 60, name: "Tea"))
        #expect(center.sortedTimers.map(\.name) == ["Tea", "Pasta"])
        #expect(TimerPane.Page(module) == .list)
        clock.advance(61)
        center.timeMayHaveJumped()
        #expect(TimerPane.Page(module) == .done)
        #expect(module.isActive)
        #expect(module.waitsForYou)
        #expect(TimerDoneText.title(center) == "Tea done")
    }

    @Test func typingTheName() throws {
        let center = TimerCenter()
        let module = TimerModule(center: center, settings: TimerSettings(defaults: scratchDefaults()), presents: false)
        module.beginEditingName()
        #expect(module.holdsOpen)
        for character in "Pastaa" { #expect(module.handleKey(try key(String(character)))) }
        #expect(module.handleKey(try key("\u{7F}", code: 51)))
        #expect(module.newName == "Pasta")
        // Space is part of a name while typing, not Start.
        #expect(module.handleKey(try key(" ", code: 49)))
        #expect(center.timers.isEmpty)
        module.wheelSeconds = 120
        #expect(module.handleKey(try key("\r", code: 36)))
        #expect(center.timer.name == "Pasta")
        #expect(!module.editingName)
    }

    @Test func escGoesBackFromNewTimer() throws {
        let center = TimerCenter()
        let module = TimerModule(center: center, settings: TimerSettings(defaults: scratchDefaults()), presents: false)
        center.startTimer(seconds: 60)
        module.beginAdding()
        #expect(module.showsSetup)
        #expect(module.handleKey(try key("\u{1B}", code: 53)))
        #expect(!module.showsSetup)
    }

    private func key(_ characters: String, code: UInt16 = 0) throws -> NSEvent {
        try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
                                      context: nil, characters: characters, charactersIgnoringModifiers: characters,
                                      isARepeat: false, keyCode: code))
    }
}
