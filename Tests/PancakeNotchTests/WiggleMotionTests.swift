import Foundation
import NotchCore
import Testing
@testable import PancakeNotch

/// The editor's wiggle: it eases in and out, and is exactly level when it's off.
struct WiggleMotionTests {
    let start = Date(timeIntervalSinceReferenceDate: 1_000)

    @Test func startsLevelAndStaysLevel() {
        let motion = WiggleMotion()
        #expect(motion.isLevel(at: start))
        #expect(motion.degrees(at: start, seed: 3) == 0)
        #expect(motion.degrees(at: start.addingTimeInterval(7.3), seed: 3) == 0)
    }

    @Test func easesInThenStaysWithinTheLimit() {
        let on = WiggleMotion().retargeted(wiggling: true, at: start)
        #expect(on.amplitude(at: start) == 0)
        #expect(on.amplitude(at: start.addingTimeInterval(WiggleMotion.rampDuration / 2)) > 0.4)
        #expect(on.amplitude(at: start.addingTimeInterval(WiggleMotion.rampDuration)) == 1)
        let tilts = (0..<400).map { on.degrees(at: start.addingTimeInterval(1 + Double($0) * 0.007), seed: 5) }
        #expect(tilts.allSatisfy { abs($0) <= WiggleMotion.maxDegrees + 1e-9 })
        #expect(tilts.contains { $0 > 0.5 } && tilts.contains { $0 < -0.5 }) // it really swings both ways
    }

    @Test func settlesToExactlyLevel() {
        let on = WiggleMotion().retargeted(wiggling: true, at: start)
        let stopAt = start.addingTimeInterval(2)
        let off = on.retargeted(wiggling: false, at: stopAt)
        #expect(off.amplitude(at: stopAt) == 1) // continues from where it was
        #expect(!off.isLevel(at: stopAt.addingTimeInterval(0.1)))
        let done = stopAt.addingTimeInterval(WiggleMotion.rampDuration)
        #expect(off.isLevel(at: done))
        #expect(off.degrees(at: done, seed: 2) == 0)
    }

    @Test func turningBackOnMidSettleDoesNotJump() {
        let on = WiggleMotion().retargeted(wiggling: true, at: start)
        let off = on.retargeted(wiggling: false, at: start.addingTimeInterval(1))
        let midway = start.addingTimeInterval(1 + WiggleMotion.rampDuration / 2)
        let again = off.retargeted(wiggling: true, at: midway)
        #expect(abs(again.amplitude(at: midway) - off.amplitude(at: midway)) < 1e-9)
    }

    @Test func widgetsAreOutOfStep() {
        #expect(WiggleMotion.seed(for: .clock) == WiggleMotion.seed(for: .clock))
        #expect(Set(HomeWidgetKind.allCases.map(WiggleMotion.seed(for:))).count > 3)
    }
}
