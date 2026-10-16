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

    /// A drag out of the Shelf whose release went unseen: the next window move mustn't open the notch.
    @Test func windowMoveAfterADragOutOfTheAppDoesNotCount() {
        var tracker = DragPasteboardTracker(settledCount: 4)
        tracker.ownPressed()
        tracker.pressed(count: 5)
        #expect(!tracker.isNewDrag(count: 5))
        #expect(tracker.isNewDrag(count: 6))
    }

    @Test func clickInTheAppKeepsFinderDragsWorking() {
        var tracker = DragPasteboardTracker(settledCount: 4)
        tracker.ownPressed()
        tracker.settled(count: 4)
        tracker.pressed(count: 5)
        #expect(tracker.isNewDrag(count: 5))
    }
}
