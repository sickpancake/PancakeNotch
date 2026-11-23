import AppKit
import Foundation
import Testing
@testable import ModuleNotes
@testable import NotesCore

@MainActor
struct NotesSearchTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func note(_ text: String, pinned: Bool = false, minutesAgo: Double = 0) -> Note {
        Note(text: text, created: now - minutesAgo * 60, isPinned: pinned)
    }

    func makeModule(_ notes: [Note]) -> NotesModule {
        let suite = "NotesSearchTests-\(UUID().uuidString)"
        let settings = NotesSettings(defaults: UserDefaults(suiteName: suite)!)
        let now = now
        return NotesModule(store: NotesStore(directory: nil, notes: notes, now: { now }), settings: settings)
    }

    func key(_ code: UInt16, _ characters: String = "", command: Bool = false) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: command ? .command : [], timestamp: 0,
                         windowNumber: 0, context: nil, characters: characters,
                         charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)!
    }

    // MARK: Matching

    @Test func matchesEveryWordInAnyOrderIgnoringCaseAndAccents() {
        let groceries = note("Groceries\nEggs, flour and a Café latte")
        #expect(NotesSearch("groc").matches(groceries))
        #expect(NotesSearch("CAFE eggs").matches(groceries))
        #expect(NotesSearch("latte   groceries").matches(groceries))
        #expect(!NotesSearch("eggs bacon").matches(groceries))
    }

    @Test func emptyOrBlankSearchShowsEverything() {
        let notes = [note("One"), note("Two")]
        #expect(NotesSearch("").isEmpty)
        #expect(NotesSearch("   \n ").isEmpty)
        #expect(NotesSearch("  ").filter(notes) == notes)
    }

    @Test func repeatedWordsCountOnce() {
        #expect(NotesSearch("milk MILK mílk").terms == ["milk"])
    }

    @Test func titlesOnlyIgnoresTheRestOfTheNote() {
        let groceries = note("Groceries\nMaple syrup")
        #expect(!NotesSearch("syrup", scope: .titlesOnly).matches(groceries))
        #expect(NotesSearch("groc", scope: .titlesOnly).matches(groceries))
        #expect(NotesSearch("syrup", scope: .titleAndText).matches(groceries))
    }

    @Test func filterKeepsTheGivenOrderAndAKeptNote() {
        let pinned = note("Pinned plan", pinned: true)
        let other = note("Plan B")
        let unrelated = note("Shopping")
        let list = [pinned, other, unrelated]
        #expect(NotesSearch("plan").filter(list).map(\.id) == [pinned.id, other.id])
        #expect(NotesSearch("plan").filter(list, keeping: unrelated.id).map(\.id) == [pinned.id, other.id, unrelated.id])
    }

    // MARK: Highlights and previews

    @Test func rangesAreSortedAndMerged() {
        let text = "the theme of the day"
        let ranges = NotesSearch("the them").ranges(in: text).map { String(text[$0]) }
        #expect(ranges == ["the", "them", "the"])
    }

    @Test func runsCoverTheWholeText() {
        let runs = NotesSearch("syrup").runs(in: "Maple Syrup, please")
        #expect(runs.map(\.text).joined() == "Maple Syrup, please")
        #expect(runs.filter(\.isMatch).map { String($0.text) } == ["Syrup"])
    }

    @Test func snippetStartsNearADeepMatch() {
        let preview = "Pack the charger, the passport, sunscreen, a book for the plane and the blue jacket"
        let snippet = NotesSearch("jacket").snippet(of: preview)
        #expect(snippet.hasPrefix("…"))
        #expect(snippet.hasSuffix("blue jacket"))
        #expect(snippet.count < preview.count)
        // An early match, or titles-only search, leaves the preview as it is.
        #expect(NotesSearch("charger").snippet(of: preview) == preview)
        #expect(NotesSearch("jacket", scope: .titlesOnly).snippet(of: preview) == preview)
    }

    @Test func nsRangesPointAtTheWordsInTheText() {
        let text = "Café — café"
        let ranges = NotesSearch("cafe").nsRanges(in: text)
        #expect(ranges.map { (text as NSString).substring(with: $0) } == ["Café", "café"])
    }

    @Test func titlesOnlyHighlightsOnlyTheTitle() {
        let text = "\nPancake place\nThe best pancake in town"
        let ranges = NotesSearch("pancake", scope: .titlesOnly).nsRanges(in: text)
        #expect(ranges == [NSRange(location: 1, length: 7)])
    }

    // MARK: The module

    @Test func searchingNarrowsTheListAndKeepsPinnedFirst() {
        let pinned = note("Pinned groceries", pinned: true, minutesAgo: 30)
        let recent = note("Groceries for Saturday", minutesAgo: 1)
        let other = note("Weekend ideas", minutesAgo: 2)
        let module = makeModule([recent, other, pinned])
        module.setQuery("groceries")
        #expect(module.shownNotes.map(\.id) == [pinned.id, recent.id])
        #expect(module.notes.count == 3) // widgets still see every note
        #expect(module.selectedNote?.id == pinned.id)
        #expect(NotesText.matches(2, of: 3) == "2 of 3 notes")
    }

    @Test func nothingMatchesLeavesNoSelection() {
        let module = makeModule([note("Groceries"), note("Ideas")])
        module.setQuery("taxes")
        #expect(module.shownNotes.isEmpty)
        #expect(module.selectedNote == nil)
        #expect(module.isFiltering)
        module.clearSearch()
        #expect(module.shownNotes.count == 2)
    }

    @Test func aHiddenSelectionComesBackWhenTheSearchClears() {
        let a = note("Alpha", minutesAgo: 1)
        let b = note("Beta", minutesAgo: 2)
        let module = makeModule([a, b])
        module.select(b.id)
        module.setQuery("alpha")
        #expect(module.selectedNote?.id == a.id)
        module.clearSearch()
        #expect(module.selectedNote?.id == b.id)
    }

    @Test func commandFStartsSearchingAndEscClearsThenLeaves() {
        let module = makeModule([note("Groceries")])
        #expect(module.handleKey(key(3, "f", command: true)))
        #expect(module.isSearching)
        #expect(module.holdsOpen)
        module.setQuery("groc")
        #expect(module.handleKey(key(53)))
        #expect(module.query.isEmpty)
        #expect(module.isSearching)
        #expect(module.handleKey(key(53)))
        #expect(!module.isSearching)
        #expect(!module.holdsOpen)
    }

    @Test func commandFFromInsideANoteMovesToTheSearch() {
        let module = makeModule([note("Groceries")])
        module.startEditing()
        #expect(module.isEditing)
        #expect(module.handleKey(key(3, "f", command: true)))
        #expect(module.isSearching)
        #expect(!module.isEditing)
    }

    @Test func typedLettersReachTheField() {
        let module = makeModule([note("Groceries")])
        module.startSearching()
        #expect(!module.handleKey(key(0, "a")))
        #expect(!module.handleKey(key(51))) // Delete erases in the field, not a note
        #expect(module.store.notes.count == 1)
    }

    @Test func arrowsWalkTheMatchesAndReturnOpensOne() {
        let first = note("Plan one", minutesAgo: 1)
        let skipped = note("Shopping", minutesAgo: 2)
        let second = note("Plan two", minutesAgo: 3)
        let module = makeModule([first, skipped, second])
        module.startSearching()
        module.setQuery("plan")
        #expect(module.handleKey(key(125)))
        #expect(module.selectedNote?.id == second.id)
        #expect(module.handleKey(key(125)))
        #expect(module.selectedNote?.id == second.id) // stops at the last match
        #expect(module.handleKey(key(126)))
        #expect(module.selectedNote?.id == first.id)
        #expect(module.handleKey(key(36)))
        #expect(module.isEditing)
        #expect(!module.isSearching)
        #expect(module.holdsOpen)
        #expect(module.query == "plan") // the search stays while you write
    }

    @Test func theNoteYouWriteInStaysListedUntilTheSearchChanges() {
        let plan = note("Plan")
        let module = makeModule([plan, note("Other")])
        module.setQuery("plan")
        module.openFromSearch(plan.id)
        module.edit(plan.id, text: "Shopping list")
        #expect(module.shownNotes.map(\.id) == [plan.id])
        module.setQuery("other")
        #expect(!module.shownNotes.contains { $0.id == plan.id })
    }

    @Test func aNewNoteEndsTheSearch() {
        let module = makeModule([note("Groceries")])
        module.startSearching()
        module.setQuery("groc")
        #expect(module.handleKey(key(45, "n", command: true)))
        #expect(module.query.isEmpty)
        #expect(module.isEditing)
        #expect(!module.isSearching)
        #expect(module.selectedNote?.isEmpty == true)
    }

    @Test func undoBringsBackANoteEvenIfItDoesNotMatch() {
        let keep = note("Groceries", minutesAgo: 1)
        let gone = note("Taxes", minutesAgo: 2)
        let module = makeModule([keep, gone])
        module.delete(gone.id)
        module.setQuery("groc")
        module.undoDelete()
        #expect(module.shownNotes.map(\.id).contains(gone.id))
        #expect(module.selectedNote?.id == gone.id)
    }

    @Test func deletingAMatchSelectsTheNextMatch() {
        let a = note("Plan A", minutesAgo: 1)
        let other = note("Other", minutesAgo: 2)
        let b = note("Plan B", minutesAgo: 3)
        let module = makeModule([a, other, b])
        module.setQuery("plan")
        module.delete(a.id)
        #expect(module.selectedNote?.id == b.id)
    }

    @Test func closingTheNotchClearsTheSearchUnlessKept() {
        let module = makeModule([note("Groceries")])
        module.startSearching()
        module.setQuery("groc")
        module.notchDidClose()
        #expect(module.query.isEmpty)
        #expect(!module.isSearching)

        module.settings.keepsSearch = true
        module.setQuery("groc")
        module.notchDidClose()
        #expect(module.query == "groc")
        #expect(module.shownNotes.count == 1)
    }

    @Test func theFieldShowsAlwaysOrOnlyWhileSearching() {
        let module = makeModule([note("Groceries")])
        #expect(module.showsSearchField)
        module.settings.searchField = .whenSearching
        #expect(!module.showsSearchField)
        module.startSearching()
        #expect(module.showsSearchField)
        module.stopSearching()
        #expect(!module.showsSearchField) // nothing typed: it tucks away again
        module.startSearching()
        module.setQuery("groc")
        module.stopSearching()
        #expect(module.showsSearchField) // words typed: it stays so you can see why the list is short
    }

    @Test func noNotesMeansNoSearch() {
        let module = makeModule([])
        #expect(!module.showsSearchField)
        // Nothing to search: ⌘F isn't taken, so it can reach the app you were in.
        #expect(!module.handleKey(key(3, "f", command: true)))
        #expect(!module.isSearching)
    }

    @Test func titlesOnlySettingNarrowsWhatIsSearched() {
        let module = makeModule([note("Groceries\nMaple syrup"), note("Syrup brands")])
        module.setQuery("syrup")
        #expect(module.shownNotes.count == 2)
        module.settings.searchScope = .titlesOnly
        #expect(module.shownNotes.map(\.title) == ["Syrup brands"])
    }

    @Test func searchSettingsAreRemembered() {
        let suite = "NotesSearchTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let settings = NotesSettings(defaults: defaults)
        #expect(settings.searchField == .always)
        #expect(settings.searchScope == .titleAndText)
        #expect(!settings.keepsSearch)
        settings.searchField = .whenSearching
        settings.searchScope = .titlesOnly
        settings.keepsSearch = true
        let reopened = NotesSettings(defaults: defaults)
        #expect(reopened.searchField == .whenSearching)
        #expect(reopened.searchScope == .titlesOnly)
        #expect(reopened.keepsSearch)
        defaults.removePersistentDomain(forName: suite)
    }

    @Test func foundIsReportedForLearn() {
        let module = makeModule([note("Pancake place")])
        var found = 0
        module.onFound = { found += 1 }
        module.setQuery("waffle")
        #expect(found == 0)
        module.setQuery("pancake")
        #expect(found == 1)
    }

    // MARK: The field

    @Test func theFieldHasAVoiceOverLabelAndTakesNoDrops() {
        let field = NotesSearchField.makeField(text: "groc")
        #expect(field.accessibilityLabel() == "Search notes")
        #expect(field.accessibilityHelp()?.isEmpty == false)
        #expect(field.registeredDraggedTypes.isEmpty)
        #expect(field.stringValue == "groc")
        let editor = field.cell?.fieldEditor(for: field)
        #expect(editor?.isFieldEditor == true)
        #expect(editor?.registeredDraggedTypes.isEmpty == true)
    }
}
