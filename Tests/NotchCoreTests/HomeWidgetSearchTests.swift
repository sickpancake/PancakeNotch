import Testing
@testable import NotchCore

struct HomeWidgetSearchTests {
    private func found(_ search: String) -> [HomeWidgetKind] {
        HomeWidgetKind.allCases.filter { $0.matches(search: search) }
    }

    @Test func anEmptySearchFindsEveryWidget() {
        #expect(found("") == HomeWidgetKind.allCases)
        #expect(found("   ") == HomeWidgetKind.allCases)
    }

    @Test func namesMatchFromTheStartOfAWord() {
        #expect(found("keep") == [.keepAwake])
        #expect(found("usage") == [.aiUsage])
        // "tim" also starts "time", a word for the Stopwatch and Clock.
        #expect(Set(found("tim")) == [.timer, .stopwatch, .clock])
        #expect(found("STOP") == [.stopwatch])
        // Inside a word doesn't count, so "lay" doesn't find Now Playing.
        #expect(found("lay").isEmpty)
    }

    @Test func relatedWordsFindTheirWidget() {
        #expect(found("music") == [.nowPlaying])
        #expect(found("song") == [.nowPlaying])
        #expect(found("files") == [.shelf])
        #expect(found("caffeine") == [.keepAwake])
        #expect(found("charging") == [.battery])
        #expect(Set(found("claude")) == [.agents, .aiUsage])
        #expect(Set(found("time")) == [.timer, .stopwatch, .clock])
    }

    @Test func everyWordTypedMustMatch() {
        #expect(found("apple mu") == [.nowPlaying])
        #expect(found("time alarm") == [.timer])
        #expect(found("music files").isEmpty)
    }

    @Test func caseAccentsAndPunctuationAreIgnored() {
        #expect(found("MÚSIC") == [.nowPlaying])
        #expect(found("airdrop") == [.shelf])
        #expect(found("keep-awake") == [.keepAwake])
    }

    @Test func everyWidgetHasSearchTerms() {
        for kind in HomeWidgetKind.allCases { #expect(!kind.searchTerms.isEmpty) }
    }
}
