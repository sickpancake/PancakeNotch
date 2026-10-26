import CoreGraphics
import Testing
@testable import NotchCore

struct DragPasteboardTrackerTests {
    @Test func dragWrittenAfterThePressCounts() {
        var tracker = DragPasteboardTracker(settledCount: 4)
        tracker.pressed(count: 4)
        #expect(tracker.isNewDrag(count: 5))
    }

    /// Finder: the drag is already on the pasteboard when the press reaches the app.
    @Test func dragWrittenBeforeThePressArrivesCounts() {
        var tracker = DragPasteboardTracker(settledCount: 4)
        tracker.pressed(count: 5)
        #expect(tracker.isNewDrag(count: 5))
    }

    @Test func windowMoveDoesNotCount() {
        var tracker = DragPasteboardTracker(settledCount: 4)
        tracker.pressed(count: 4)
        #expect(!tracker.isNewDrag(count: 4))
    }

    @Test func windowMoveAfterAnEarlierDragDoesNotCount() {
        var tracker = DragPasteboardTracker(settledCount: 4)
        tracker.pressed(count: 5)
        tracker.settled(count: 5)
        tracker.pressed(count: 5)
        #expect(!tracker.isNewDrag(count: 5))
    }

    /// A drag out of the Shelf (its release goes unseen, its end settles the count): the next window
    /// move mustn't open the notch, the next real drag must.
    @Test func windowMoveAfterADragOutOfTheAppDoesNotCount() {
        var tracker = DragPasteboardTracker(settledCount: 4)
        tracker.ownPressed(count: 4)
        tracker.settled(count: 5)
        tracker.pressed(count: 5)
        #expect(!tracker.isNewDrag(count: 5))
        #expect(tracker.isNewDrag(count: 6))
    }

    @Test func clickInTheAppKeepsFinderDragsWorking() {
        var tracker = DragPasteboardTracker(settledCount: 4)
        tracker.ownPressed(count: 4)
        tracker.settled(count: 4)
        tracker.pressed(count: 5)
        #expect(tracker.isNewDrag(count: 5))
    }

    /// A press in the app whose release went unseen used to make every Finder drag that wrote before
    /// its press arrived look like a window move, until the next click elsewhere.
    @Test func unseenReleaseInTheAppKeepsFinderDragsWorking() {
        var tracker = DragPasteboardTracker(settledCount: 4)
        tracker.ownPressed(count: 4)
        tracker.pressed(count: 5)
        #expect(tracker.isNewDrag(count: 5))
    }

    /// The drag out of the Shelf, then a Finder drop on the notch (its release unseen too), then another
    /// Finder drag that writes before its press arrives.
    @Test func dragsAfterADropOnTheNotchStillCount() {
        var tracker = DragPasteboardTracker(settledCount: 4)
        tracker.ownPressed(count: 4)
        tracker.settled(count: 5)
        tracker.pressed(count: 6)
        #expect(tracker.isNewDrag(count: 6))
        tracker.settled(count: 6)
        tracker.pressed(count: 7)
        #expect(tracker.isNewDrag(count: 7))
    }

    @Test func windowMoveAfterADropOnTheNotchDoesNotCount() {
        var tracker = DragPasteboardTracker(settledCount: 4)
        tracker.pressed(count: 5)
        tracker.settled(count: 5)
        tracker.pressed(count: 5)
        #expect(!tracker.isNewDrag(count: 5))
    }
}

struct MissionControlDragGuardTests {
    /// 14-inch MacBook Pro at its default size: 1512 × 982 points, 33-point menu bar.
    let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
    let zone = CGRect(x: 438, y: 802, width: 636, height: 180)

    @Test func floorSitsJustBelowTheMenuBar() {
        #expect(MissionControlDragGuard.floorY(screenFrame: screen, stripHeight: 33) == CGFloat(982 - 33 - 6))
    }

    @Test func pointerInTheMenuBarOverTheNotchStops() {
        let floorY = MissionControlDragGuard.floorY(screenFrame: screen, stripHeight: 33)
        #expect(MissionControlDragGuard.floorPoint(for: CGPoint(x: 756, y: 970), zone: zone, floorY: floorY)
            == CGPoint(x: 756, y: floorY))
        #expect(MissionControlDragGuard.floorPoint(for: CGPoint(x: 438, y: 982), zone: zone, floorY: floorY)
            == CGPoint(x: 438, y: floorY))
    }

    @Test func pointerBelowTheFloorIsLeftAlone() {
        let floorY = MissionControlDragGuard.floorY(screenFrame: screen, stripHeight: 33)
        #expect(MissionControlDragGuard.floorPoint(for: CGPoint(x: 756, y: floorY), zone: zone, floorY: floorY) == nil)
        #expect(MissionControlDragGuard.floorPoint(for: CGPoint(x: 756, y: 850), zone: zone, floorY: floorY) == nil)
    }

    /// Menu bar icons beside the open notch's area still take drops.
    @Test func pointerBesideTheNotchAreaIsLeftAlone() {
        let floorY = MissionControlDragGuard.floorY(screenFrame: screen, stripHeight: 33)
        #expect(MissionControlDragGuard.floorPoint(for: CGPoint(x: 437, y: 975), zone: zone, floorY: floorY) == nil)
        #expect(MissionControlDragGuard.floorPoint(for: CGPoint(x: 1074, y: 975), zone: zone, floorY: floorY) == nil)
    }
}
