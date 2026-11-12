import Foundation
import Testing
@testable import NotchCore

struct HomeLayoutTests {
    func p(_ kind: HomeWidgetKind, _ size: HomeWidgetSize = .small, _ column: Int = 0, _ row: Int = 0, _ page: Int = 0) -> HomePlacement {
        HomePlacement(kind: kind, size: size, slot: HomeSlot(page: page, column: column, row: row))
    }
    func slot(_ column: Int, _ row: Int = 0, _ page: Int = 0) -> HomeSlot { HomeSlot(page: page, column: column, row: row) }
    func decode(_ json: String) -> HomeLayout { .decode(Data(json.utf8)) }
    func valid(_ layout: HomeLayout, sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(Set(layout.placements.map(\.kind)).count == layout.placements.count, sourceLocation: sourceLocation)
        #expect(layout.placements.allSatisfy { $0.fits && $0.kind.supports($0.size) }, sourceLocation: sourceLocation)
        #expect(layout.occupiedCells.count == layout.placements.reduce(0) { $0 + $1.size.cellCount }, sourceLocation: sourceLocation)
        #expect(layout.placements == layout.placements.sorted(by: HomeLayout.readingOrder), sourceLocation: sourceLocation)
    }
    func fragmented(excluding excluded: Set<HomeWidgetKind>) -> HomeLayout {
        let kinds = HomeWidgetKind.allCases.filter { $0.supports(.small) && !excluded.contains($0) }
        return HomeLayout(placements: kinds.prefix(9).enumerated().map { index, kind in
            p(kind, .small, (index % 3) * 2, 0, index / 3)
        })
    }

    /// Sizes have the promised footprints and order.
    @Test func sizes() { #expect(HomeWidgetSize.allCases.map(\.cellCount) == [1, 2, 4]); #expect(HomeWidgetSize.small < .medium); #expect(HomeWidgetSize.medium < .large) }
    /// Gallery order is stable.
    @Test func catalogOrder() { #expect(HomeWidgetKind.allCases.map(\.rawValue) == ["nowPlaying", "timer", "stopwatch", "agents", "aiUsage", "shelf", "keepAwake", "allModules", "clock", "battery", "statistics"]) }
    /// Timer and stopwatch share the same module switch.
    @Test func moduleKinds() { #expect(HomeWidgetKind.kinds(forModule: "timer") == [.timer, .stopwatch]); #expect(HomeWidgetKind.kinds(forModule: "unknown").isEmpty) }
    /// Every default size is supported and every title has text.
    @Test func catalogDefaults() { for kind in HomeWidgetKind.allCases { #expect(kind.supports(kind.defaultSize)); #expect(!kind.title.isEmpty); #expect(!kind.symbol.isEmpty); #expect(kind.sizes == kind.sizes.sorted()) } }
    /// Default Home has exactly the requested seven placements.
    @Test func defaultExact() {
        #expect(HomeLayout.default == HomeLayout(placements: [p(.nowPlaying, .large), p(.timer, .medium, 2), p(.agents, .medium, 2, 1), p(.shelf, .small, 4), p(.aiUsage, .small, 5), p(.keepAwake, .small, 4, 1), p(.clock, .small, 5, 1)]))
        valid(.default); #expect(HomeLayout.default.nonEmptyPages == [0])
    }
    /// Each preset fits without duplicate widgets.
    @Test(arguments: HomePreset.allCases) func presets(_ preset: HomePreset) { valid(preset.layout); #expect(!preset.title.isEmpty) }
    /// Music places its large player in the middle.
    @Test func musicExact() { #expect(HomePreset.music.layout == HomeLayout(placements: [p(.clock, .medium), p(.battery, .medium, 0, 1), p(.nowPlaying, .large, 2), p(.timer, .medium, 4), p(.shelf, .medium, 4, 1)])) }
    /// Work gives Agents the large footprint.
    @Test func workExact() { #expect(HomePreset.work.layout == HomeLayout(placements: [p(.agents, .large), p(.aiUsage, .medium, 2), p(.timer, .medium, 2, 1), p(.keepAwake, .medium, 4), p(.clock, .small, 4, 1), p(.battery, .small, 5, 1)])) }
    /// Minimal uses only six small footprints.
    @Test func minimalExact() { #expect(HomePreset.minimal.layout == HomeLayout(placements: [p(.clock), p(.battery, .small, 0, 1), p(.nowPlaying, .small, 1), p(.timer, .small, 1, 1), p(.shelf, .small, 2), p(.keepAwake, .small, 2, 1)])) }
    /// Cell queries cover the whole large footprint.
    @Test func queries() { let l = HomeLayout.default; #expect(l.placement(at: slot(1, 1))?.kind == .nowPlaying); #expect(l.freeCells(onPage: 0).isEmpty); #expect(l.freeCells(onPage: 1).count == 12); #expect(l.isPageEmpty(2)); #expect(l.placements(onPage: 0).count == 7) }
    /// Separate pages never overlap.
    @Test func overlapPages() { #expect(!p(.clock).overlaps(p(.battery, .small, 0, 0, 1))); #expect(p(.clock).overlaps(p(.timer))) }
    /// Negative and overflowing positions do not fit.
    @Test func fitsBounds() { #expect(!p(.timer, .medium, 5).fits); #expect(!p(.clock, .small, -1).fits); #expect(!p(.clock, .small, 0, 0, 3).fits); #expect(!p(.agents, .large, 0, 1).fits) }
    /// Adding searches down the first column before the next one.
    @Test func addColumnMajor() throws { let l = HomeLayout(placements: [p(.clock)]); let n = try l.adding(.battery).get(); #expect(n.placement(of: .battery)?.slot == slot(0, 1)) }
    /// A full first page sends a new widget to page two.
    @Test func addNextPage() throws { let n = try HomeLayout.default.adding(.battery).get(); #expect(n.placement(of: .battery)?.slot == slot(0, 0, 1)) }
    /// Adding uses the requested size when a gap exists.
    @Test func explicitAddSize() throws { #expect(try HomeLayout().adding(.timer, size: .small).get().placement(of: .timer)?.size == .small) }
    /// Fragmented pages make a large default fall back to medium.
    @Test func smallerFallback() throws { let l = fragmented(excluding: [.nowPlaying]); let n = try l.adding(.nowPlaying).get(); #expect(n.placement(of: .nowPlaying)?.size == .medium); #expect(n.placement(of: .nowPlaying)?.slot == slot(0, 1)); valid(n) }
    /// A widget with no smaller size refuses fragmented pages.
    @Test func addFull() { let l = fragmented(excluding: []); #expect(l.adding(.allModules) == .failure(.full)); valid(l) }
    /// Adding never duplicates an existing widget.
    @Test func duplicateAdd() { #expect(HomeLayout.default.adding(.timer) == .failure(.alreadyOnHome)) }
    /// An unsupported explicit add size is refused.
    @Test func unsupportedAdd() { #expect(HomeLayout().adding(.clock, size: .large) == .failure(.unsupportedSize)) }
    /// Moving to an empty spot leaves other widgets alone.
    @Test func moveEmpty() throws { let l = HomeLayout(placements: [p(.clock), p(.battery, .small, 3)]); let n = try l.moving(.clock, to: slot(1)).get(); #expect(n.placement(of: .clock)?.slot == slot(1)); #expect(n.placement(of: .battery) == l.placement(of: .battery)) }
    /// A displaced neighbour picks the nearest gap with column-first ties.
    @Test func nearestNeighbour() throws { let l = HomeLayout(placements: [p(.clock), p(.battery, .small, 1)]); let n = try l.moving(.clock, to: slot(1)).get(); #expect(n.placement(of: .battery)?.slot == slot(0)); valid(n) }
    /// A gallery drop on a full page spills its neighbour to the next page.
    @Test func spillLater() throws { let n = try HomeLayout.default.inserting(.battery, size: .small, at: slot(4)).get(); #expect(n.placement(of: .shelf)?.slot == slot(0, 0, 1)); valid(n) }
    /// A displaced widget on the last page spills back to an earlier page.
    @Test func spillEarlier() throws { var l = HomeLayout.default; l.placements = l.placements.map { var p = $0; p.slot.page = 2; return p }; let n = try l.inserting(.battery, size: .small, at: slot(4, 0, 2)).get(); #expect(n.placement(of: .shelf)?.slot == slot(0)); valid(n) }
    /// Widgets untouched by displacement keep their slots.
    @Test func untouched() throws { let l = HomeLayout.default; let n = try l.inserting(.battery, size: .small, at: slot(4)).get(); for item in l.placements where item.kind != .shelf { #expect(n.placement(of: item.kind) == item) } }
    /// Growing a widget preserves all neighbours.
    @Test func resizeDisplaces() throws { let l = HomePreset.minimal.layout; let n = try l.resizing(.nowPlaying, to: .large).get(); valid(n); #expect(n.placements.count == l.placements.count); #expect(n.placement(of: .nowPlaying)?.size == .large) }
    /// Unsupported resizing preserves the original layout.
    @Test func unsupportedResize() { #expect(HomeLayout.default.resizing(.clock, to: .large) == .failure(.unsupportedSize)) }
    /// Resizing at the bottom-right clamps both coordinates.
    @Test func resizeClamp() throws { let l = HomeLayout(placements: [p(.timer, .small, 5, 1)]); #expect(try l.resizing(.timer, to: .large).get().placement(of: .timer)?.slot == slot(4)) }
    /// Moving clamps negative columns and overflowing rows.
    @Test func moveClamp() throws { let l = HomeLayout(placements: [p(.timer, .medium)]); #expect(try l.moving(.timer, to: slot(-99, 99)).get().placement(of: .timer)?.slot == slot(0, 1)) }
    /// Invalid pages refuse instead of clamping.
    @Test func invalidPage() { #expect(HomeLayout.default.moving(.timer, to: slot(0, 0, 3)) == .failure(.outOfRange)) }
    /// Missing widgets return a useful refusal.
    @Test func missingEdits() { let l = HomeLayout(); #expect(l.moving(.timer, to: slot(1)) == .failure(.notOnHome)); #expect(l.resizing(.timer, to: .small) == .failure(.notOnHome)); #expect(l.nudging(.timer, by: .left) == .failure(.notOnHome)) }
    /// An unchanged move is exactly equal to its input.
    @Test func unchangedMove() { #expect(HomeLayout.default.moving(.timer, to: slot(2)) == .success(.default)) }
    /// Gallery insertion validates size and uniqueness.
    @Test func insertValidation() { #expect(HomeLayout.default.inserting(.timer, size: .small, at: slot(0)) == .failure(.alreadyOnHome)); #expect(HomeLayout().inserting(.battery, size: .large, at: slot(0)) == .failure(.unsupportedSize)) }
    /// Removing an absent widget is harmless and preserves options.
    @Test func removal() { let l = HomeLayout(placements: [p(.statistics)], statisticsMetric: "custom"); #expect(l.removing(.statistics).isEmpty); #expect(l.removing(.statistics).statisticsMetric == "custom"); #expect(l.removing(.timer) == l) }
    /// Applying a preset keeps the Statistics option.
    @Test func applyingPreset() { let l = HomeLayout(statisticsMetric: "custom"); #expect(l.applying(.work).placements == HomePreset.work.layout.placements); #expect(l.applying(.work).statisticsMetric == "custom") }
    /// A right nudge crosses to the next page's left edge.
    @Test func nudgeRight() throws { let l = HomeLayout(placements: [p(.timer, .medium, 4)]); #expect(try l.nudging(.timer, by: .right).get().placement(of: .timer)?.slot == slot(0, 0, 1)) }
    /// A left nudge crosses to the previous page's right edge.
    @Test func nudgeLeft() throws { let l = HomeLayout(placements: [p(.timer, .medium, 0, 0, 1)]); #expect(try l.nudging(.timer, by: .left).get().placement(of: .timer)?.slot == slot(4)) }
    /// Outer horizontal edges and large vertical nudges refuse.
    @Test func nudgeBounds() { #expect(HomeLayout.default.nudging(.nowPlaying, by: .left) == .failure(.outOfRange)); #expect(HomeLayout.default.nudging(.nowPlaying, by: .down) == .failure(.outOfRange)); #expect(HomeLayout.default.nudging(.nowPlaying, by: .up) == .failure(.outOfRange)) }
    /// Vertical nudges move by exactly one row.
    @Test func nudgeVertical() throws { let l = HomeLayout(placements: [p(.clock)]); let n = try l.nudging(.clock, by: .down).get(); #expect(n.placement(of: .clock)?.slot == slot(0, 1)); #expect(try n.nudging(.clock, by: .up).get() == l) }
    /// Moving to a page prefers its first free gap.
    @Test func movePage() throws { #expect(try HomeLayout.default.movingToPage(.timer, page: 2).get().placement(of: .timer)?.slot == slot(0, 0, 2)); #expect(HomeLayout.default.movingToPage(.timer, page: -1) == .failure(.outOfRange)) }
    /// A full destination page uses displacement.
    @Test func movePageDisplaces() throws { let l = try HomeLayout.default.adding(.battery).get(); let n = try l.movingToPage(.battery, page: 0).get(); #expect(n.placement(of: .battery)?.slot.page == 0); valid(n) }
    /// Previews exactly match their final operations.
    @Test func previews() throws { let l = HomeLayout.default; #expect(l.previewMoving(.timer, to: slot(0)) == (try l.moving(.timer, to: slot(0)).get())); #expect(l.previewInserting(.battery, size: .small, at: slot(4)) == (try l.inserting(.battery, size: .small, at: slot(4)).get())); #expect(l.previewMoving(.battery, to: slot(0)) == nil) }
    /// Missing data and unreadable JSON use the default.
    @Test func badData() { #expect(HomeLayout.decode(nil) == .default); #expect(HomeLayout.decode(Data([255, 0])) == .default); #expect(decode("[]") == .default); #expect(decode("{}") == .default) }
    /// An intentionally empty saved Home stays empty.
    @Test func savedEmpty() { #expect(decode(#"{"placements":[]}"#).isEmpty) }
    /// Unknown widgets do not erase known entries.
    @Test func unknownWidget() { let l = decode(#"{"placements":[{"widget":"future"},{"widget":"clock"}]}"#); #expect(l.placements.map(\.kind) == [.clock]) }
    /// Duplicate entries keep the first one's size and location.
    @Test func duplicates() { let l = decode(#"{"placements":[{"widget":"clock","size":"medium","page":0,"column":2,"row":0},{"widget":"clock","size":"small"}]}"#); #expect(l.placements == [p(.clock, .medium, 2)]) }
    /// Overlaps are deferred until all valid saved positions are reserved.
    @Test func repairOverlap() { let l = decode(#"{"placements":[{"widget":"clock","page":0,"column":0,"row":0},{"widget":"battery","page":0,"column":0,"row":0},{"widget":"timer","size":"small","page":0,"column":0,"row":1}]}"#); #expect(l.placement(of: .battery)?.slot == slot(1)); valid(l) }
    /// Positive overflowing coordinates clamp to the last fitting slot.
    @Test func repairClamp() { let l = decode(#"{"placements":[{"widget":"timer","size":"large","page":0,"column":99,"row":99}]}"#); #expect(l.placements == [p(.timer, .large, 4)]) }
    /// Negative, missing, fractional and boolean coordinates need a fresh spot.
    @Test(arguments: ["-1", "0.5", "true", "null", "9999999999999999999999999"]) func repairInvalidCoordinate(_ value: String) { let l = decode("{\"placements\":[{\"widget\":\"clock\",\"page\":0,\"column\":\(value),\"row\":1}]}"); #expect(l.placements == [p(.clock)]) }
    /// Out-of-range pages get a fresh spot instead of wrapping.
    @Test func repairPage() { let l = decode(#"{"placements":[{"widget":"clock","page":5,"column":3,"row":1}]}"#); #expect(l.placements == [p(.clock)]) }
    /// Unsupported sizes choose the largest supported size below the saved size.
    @Test func repairSizes() { let l = decode(#"{"placements":[{"widget":"clock","size":"large"},{"widget":"allModules","size":"small"},{"widget":"timer","size":"future"}]}"#); #expect(l.placement(of: .clock)?.size == .medium); #expect(l.placement(of: .allModules)?.size == .large); #expect(l.placement(of: .timer)?.size == .small); valid(l) }
    /// Missing and future versions still load useful placements.
    @Test(arguments: ["", "\"version\":0,", "\"version\":99,"]) func versions(_ prefix: String) { #expect(decode("{\(prefix)\"placements\":[{\"widget\":\"clock\"}]}").contains(.clock)) }
    /// The migration hook currently preserves old fields.
    @Test func migrationHook() { let old: [String: Any] = ["statisticsMetric": "custom"]; #expect(HomeLayout.migrate(old, from: 0)["statisticsMetric"] as? String == "custom") }
    /// Every preset survives both public decoding paths.
    @Test(arguments: HomePreset.allCases) func roundTrip(_ preset: HomePreset) throws { var l = preset.layout; l.statisticsMetric = "opaque"; #expect(HomeLayout.decode(l.encoded()) == l); #expect(try JSONDecoder().decode(HomeLayout.self, from: JSONEncoder().encode(l)) == l) }
    /// Encoding writes flat versioned placements.
    @Test func encodedShape() throws { let o = try #require(JSONSerialization.jsonObject(with: HomeLayout.default.encoded()) as? [String: Any]); #expect(o["version"] as? Int == 1); let entries = try #require(o["placements"] as? [[String: Any]]); #expect(entries[0]["widget"] as? String == "nowPlaying"); #expect(entries[0]["slot"] == nil) }
    /// Undo and redo restore the exact arrangements and options.
    @Test func undoRedo() { var h = HomeHistory(); let before = HomeLayout.default; let after = before.removing(.timer); h.record(before); #expect(h.undo(current: after) == before); #expect(h.canRedo); #expect(h.redo(current: before) == after); #expect(!h.canRedo) }
    /// New edits clear redo and empty histories return nil.
    @Test func historyBranch() { var h = HomeHistory(); #expect(h.undo(current: .default) == nil); #expect(h.redo(current: .default) == nil); h.record(.default); _ = h.undo(current: .init()); h.record(.init()); #expect(!h.canRedo) }
    /// History retains only the latest one hundred entries.
    @Test func historyCap() { var h = HomeHistory(); for i in 0..<105 { h.record(HomeLayout(statisticsMetric: String(i))) }; var count = 0; while let l = h.undo(current: .default) { count += 1; if count == 100 { #expect(l.statisticsMetric == "5") } }; #expect(count == 100) }
    /// A full repack rescues a move when fixed neighbours leave no large gap.
    @Test func successfulRepack() throws {
        let l = HomeLayout(placements: [
            p(.nowPlaying, .large), p(.timer, .medium, 4, 1),
            p(.clock, .small, 2), p(.battery, .small, 4),
            p(.stopwatch, .small, 0, 0, 1), p(.agents, .small, 2, 0, 1), p(.aiUsage, .small, 4, 0, 1),
            p(.shelf, .small, 0, 0, 2), p(.keepAwake, .small, 2, 0, 2), p(.statistics, .small, 4, 0, 2)
        ])
        valid(l)
        let n = try l.moving(.timer, to: slot(0)).get()
        valid(n)
        #expect(n.placements.count == l.placements.count)
        #expect(n.placement(of: .timer)?.slot == slot(0))
        #expect(n.placement(of: .clock) != l.placement(of: .clock))
    }
    /// A refused full repack leaves every original widget untouched.
    @Test func fullRepackRefusal() throws {
        var l = HomeLayout()
        let ordered = HomeWidgetKind.allCases.sorted { $0.sizes.last! > $1.sizes.last! }
        for kind in ordered { l = try l.adding(kind, size: kind.sizes.last!).get() }
        valid(l)
        #expect(l.occupiedCells.count == 34)
        let before = l
        #expect(l.moving(.nowPlaying, to: slot(1)) == .failure(.full))
        #expect(l == before)
    }
    /// Repair shrinks deferred widgets when no large gap remains.
    @Test func repairShrinks() throws {
        let l = fragmented(excluding: [.nowPlaying])
        var object = try #require(JSONSerialization.jsonObject(with: l.encoded()) as? [String: Any])
        var entries = try #require(object["placements"] as? [[String: Any]])
        entries.append(["widget": "nowPlaying", "size": "large"])
        object["placements"] = entries
        let repaired = HomeLayout.decode(try JSONSerialization.data(withJSONObject: object))
        #expect(repaired.placement(of: .nowPlaying)?.size == .medium)
        valid(repaired)
    }
    /// Repair drops a deferred widget only when no supported size fits.
    @Test func repairDropsFull() throws {
        let l = fragmented(excluding: [])
        var object = try #require(JSONSerialization.jsonObject(with: l.encoded()) as? [String: Any])
        var entries = try #require(object["placements"] as? [[String: Any]])
        entries.append(["widget": "allModules", "size": "large"])
        object["placements"] = entries
        let repaired = HomeLayout.decode(try JSONSerialization.data(withJSONObject: object))
        #expect(repaired == l)
    }
    /// A non-string Statistics option is ignored without losing placements.
    @Test func repairMetric() {
        #expect(decode(#"{"placements":[],"statisticsMetric":42}"#).statisticsMetric == nil)
        #expect(decode(#"{"placements":[],"statisticsMetric":"opaque"}"#).statisticsMetric == "opaque")
    }
    /// A right nudge cannot cross the last page's outer edge.
    @Test func lastPageNudge() {
        let l = HomeLayout(placements: [p(.clock, .small, 5, 0, 2)])
        #expect(l.nudging(.clock, by: .right) == .failure(.outOfRange))
    }
    /// Seeded edits preserve geometry, uniqueness, sizes and widget counts.
    @Test func randomEdits() {
        var seed: UInt64 = 0xC0FFEE
        func random(_ limit: Int) -> Int { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Int((seed >> 32) % UInt64(limit)) }
        var l = HomeLayout.default
        for _ in 0..<500 {
            let kind = HomeWidgetKind.allCases[random(HomeWidgetKind.allCases.count)]
            let size = HomeWidgetSize.allCases[random(3)]
            let target = slot(random(8) - 1, random(4) - 1, random(5) - 1)
            let operation = random(7), before = l
            let result: Result<HomeLayout, HomeEditRefusal>
            switch operation {
            case 0: result = l.adding(kind, size: size)
            case 1: result = l.inserting(kind, size: size, at: target)
            case 2: result = l.moving(kind, to: target)
            case 3: result = l.resizing(kind, to: size)
            case 4: result = .success(l.removing(kind))
            case 5: result = l.movingToPage(kind, page: target.page)
            default: result = l.nudging(kind, by: [.left, .right, .up, .down][random(4)])
            }
            if case .success(let next) = result {
                let delta = operation == 0 || operation == 1 ? 1 : operation == 4 && before.contains(kind) ? -1 : 0
                #expect(next.placements.count == before.placements.count + delta)
                l = next
            }
            valid(l)
        }
    }
}

@MainActor struct HomeLayoutSettingsTests {
    /// Memory-only settings begin with safe defaults.
    @Test func memoryDefaults() { let s = HomeSettings(); #expect(s.layout == .default); #expect(s.opening == .lastModule); #expect(!s.hasSeenIntro) }
    /// All preferences survive reloading an isolated defaults suite.
    @Test func persistence() throws { let name = "HomeLayoutTests-\(UUID())"; let d = try #require(UserDefaults(suiteName: name)); defer { d.removePersistentDomain(forName: name) }; let s = HomeSettings(defaults: d); #expect(s.layout == .default); s.layout = HomePreset.work.layout; s.opening = .home; s.hasSeenIntro = true; let reloaded = HomeSettings(defaults: d); #expect(reloaded.layout == s.layout); #expect(reloaded.opening == .home); #expect(reloaded.hasSeenIntro) }
    /// Assigning unchanged values does not write defaults keys.
    @Test func unchangedDoesNotSave() throws { let name = "HomeLayoutTests-\(UUID())"; let d = try #require(UserDefaults(suiteName: name)); defer { d.removePersistentDomain(forName: name) }; let s = HomeSettings(defaults: d); s.layout = .default; s.opening = .lastModule; s.hasSeenIntro = false; #expect(d.object(forKey: "home.layout") == nil); #expect(d.object(forKey: "home.opening") == nil); #expect(d.object(forKey: "home.introSeen") == nil) }
    /// Failed and unchanged edits leave history empty.
    @Test func editHistory() { let s = HomeSettings(); var h = HomeHistory(); #expect(s.edit(&h) { $0.adding(.timer) } == .alreadyOnHome); #expect(!h.canUndo); s.edit(&h) { .success($0) }; #expect(!h.canUndo); s.edit(&h) { .success($0.removing(.timer)) }; #expect(h.canUndo); #expect(h.undo(current: s.layout) == .default) }
    /// Applying a refusal leaves settings unchanged.
    @Test func applyRefusal() { let s = HomeSettings(); #expect(s.apply(.failure(.full)) == .full); #expect(s.layout == .default); #expect(s.apply(.success(.init())) == nil); #expect(s.layout.isEmpty) }
}
