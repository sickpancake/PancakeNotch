import Foundation
import Testing
@testable import NotchCore

struct HomeReplayLayout {
    func valid(_ l: HomeLayout) {
        #expect(Set(l.placements.map(\.kind)).count == l.placements.count)
        for a in l.placements {
            #expect(a.fits)
            #expect(a.kind.supports(a.size))
            for b in l.placements where a.kind != b.kind { #expect(!a.overlaps(b)) }
        }
    }
    /// Model's six mutant paths, expanded to the real 6 x 2 x 3 grid.
    @Test func editCounterexamples() throws {
        let s = HomeSlot(page: 0, column: 0, row: 0)
        let l = try HomeLayout().inserting(.timer, size: .small, at: s).get()
        valid(try l.inserting(.allModules, size: .large, at: s).get()) // overlap
        #expect(l.adding(.timer) == .failure(.alreadyOnHome)) // duplicate
        #expect(l.inserting(.allModules, size: .small, at: s) == .failure(.unsupportedSize))
        #expect(l.moving(.timer, to: .init(page: 3, column: 0, row: 0)) == .failure(.outOfRange))
        #expect(l.placement(of: .timer)?.slot == s) // refusal unchanged
        valid(try l.resizing(.timer, to: .large).get())
        #expect(l.removing(.timer).isEmpty)
        #expect(HomeLayout.decode(l.encoded()) == l)
    }
    /// RepairKeepsValid: malformed entry is processed before an unrelated valid placement.
    @Test func repairDoesNotStealValidSlot() {
        let data = Data(#"{"placements":[{"widget":"timer","size":"small","page":0,"column":99,"row":0},{"widget":"allModules","size":"large","page":0,"column":4,"row":0}]}"#.utf8)
        let repaired = HomeLayout.decode(data)
        valid(repaired)
        #expect(repaired.placement(of: .allModules)?.slot == HomeSlot(page: 0, column: 4, row: 0))
        #expect(repaired.placement(of: .timer) != nil)
    }
    /// Generated real-code inputs supplement the smaller model, including edges absent in 2 columns.
    @Test func boundedRealGridEdits() throws {
        for kind in HomeWidgetKind.allCases {
            for size in kind.sizes {
                let original = try HomeLayout().adding(kind, size: size).get()
                for page in -1...3 { for col in -1...6 { for row in -1...2 {
                    let result = original.moving(kind, to: .init(page: page, column: col, row: row))
                    if case .success(let next) = result { valid(next); #expect(HomeLayout.decode(next.encoded()) == next) }
                    else { #expect(original.placements.count == 1) }
                } } }
            }
        }
        let spill = try HomeLayout.default.inserting(.battery, size: .small, at: .init(page: 0, column: 4, row: 0)).get()
        #expect(spill.placement(of: .shelf)?.slot.page == 1)
        valid(spill)
    }
}
