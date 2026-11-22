import Foundation
import NotesCore
import Testing
@testable import ModuleNotes

struct NotesEditorCountsTests {
    @Test func countsWordsAndGraphemesIncludingWhitespace() throws {
        let text = "Don't stop.\nCafe\u{301} 👨‍👩‍👧‍👦"
        let counts = try #require(NotesEditorCounts.measure(text))
        #expect(counts.words == 3)
        #expect(counts.characters == 18)
        #expect(counts.items == 0)
        let chinese = try #require(NotesEditorCounts.measure("你好世界"))
        #expect(chinese.words > 0)
    }

    @Test func recognizesBulletedAndNumberedItemsWithContent() {
        let text = "Shopping\r\n- oats\u{2028}  * eggs\n\t+ oil\n• tea\n1. coffee\n---\n-\t  \n3.14\n3)no space\nordinary prose\n22) milk"
        #expect(NotesEditorCounts.measure(text)?.items == 6)
    }

    @Test func selectionUsesAppKitOffsetsAndClearingItRestoresTotals() throws {
        let text = "- 👨‍👩‍👧‍👦 tea cake\n- oats"
        let range = try #require(text.range(of: "tea cake"))
        let selection = try #require(NotesEditorCountInput(text: text, selection: NSRange(range, in: text)).measure())
        #expect(selection.isSelection)
        #expect(selection.words == 2)
        #expect(selection.characters == 8)
        #expect(selection.items == 0)

        let wholeNote = try #require(NotesEditorCountInput(text: text, selection: NSRange()).measure())
        #expect(!wholeNote.isSelection)
        #expect(wholeNote.words == 3)
        #expect(wholeNote.items == 2)
        let staleRange = NSRange(location: NSNotFound, length: 2)
        #expect(NotesEditorCountInput(text: text, selection: staleRange).measure() == wholeNote)
    }

    @Test func emptyAndSingularCountsAreReadable() {
        #expect(NotesEditorCounts.empty.summary == "0 words · 0 characters")
        #expect(NotesEditorCounts.measure(" \n")?.summary == "0 words · 2 characters")
        #expect(NotesEditorCounts.measure("a")?.summary == "1 word · 1 character")
        #expect(NotesEditorCounts.measure("- a")?.summary == "1 item · 1 word · 3 characters")
    }

    @Test @MainActor func replacingPendingCountPublishesOnlyTheNewInput() async {
        let initialInput = NotesEditorCountInput(text: "One", selection: NSRange())
        let pending = Task { await initialInput.measureAfterPause() }
        pending.cancel()
        let latestInput = NotesEditorCountInput(text: "One two", selection: NSRange())
        #expect(await pending.value == nil)
        #expect(await latestInput.measureAfterPause()?.words == 2)
    }

    @Test @MainActor func cancelledMeasurementReturnsNoPartialCounts() async {
        let input = NotesEditorCountInput(text: String(repeating: "- An item\n", count: 20_000), selection: NSRange())
        let task = Task { input.measure() }
        task.cancel()
        #expect(await task.value == nil)
    }

    @Test @MainActor func choosingAListRowEndsEditingEvenForTheSameNote() throws {
        let store = NotesStore(directory: nil)
        let suite = "NotesEditorCountsTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let module = NotesModule(store: store, settings: NotesSettings(defaults: defaults))
        let first = try #require(store.add("First"))
        let second = try #require(store.add("Second"))

        module.select(first.id)
        module.startEditing()
        #expect(module.isEditing)
        module.select(first.id)
        #expect(!module.isEditing)
        module.startEditing()
        module.select(second.id)
        #expect(!module.isEditing)
        #expect(module.selectedNote?.id == second.id)
    }
}
