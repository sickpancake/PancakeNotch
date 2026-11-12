import Stats
import Testing
@testable import PancakeNotch

/// Home's Statistics widget reads the database once each time Home opens, not each time its page or
/// view comes back (ADR-0042).
@MainActor
struct HomeStatisticsReadingTests {
    @Test func readsOncePerOpening() async {
        let reading = HomeStatisticsReading { StatsSummary(opensPerDay: [1, 2, 3]) }
        await reading.refresh(for: 1)
        #expect(reading.reads == 1)
        #expect(reading.summary?.opensPerDay == [1, 2, 3])
        // The same opening: changing pages, resizing or toggling the widget doesn't read again.
        await reading.refresh(for: 1)
        await reading.refresh(for: 1)
        #expect(reading.reads == 1)
        // Home opens again: one new read.
        await reading.refresh(for: 2)
        #expect(reading.reads == 2)
    }
}
