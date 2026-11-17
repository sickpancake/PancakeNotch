import Testing
@testable import NotchCore

struct EarAllocatorTests {
    /// All ranking permutations, including unknown IDs (the allocator only sees ranked input).
    static let orders = permutations(["a", "b", "c", "d"])

    private static func permutations(_ values: [String]) -> [[String]] {
        guard !values.isEmpty else { return [[]] }
        return values.flatMap { value in permutations(values.filter { $0 != value }).map { [value] + $0 } }
    }

    /// Compare every state/rank/temporary-badge/side combination with the pre-refactor algorithm.
    /// State 0 omits a module; 1...6 cover each placement with and without a waiting alert.
    @Test(arguments: orders)
    func preservesExistingAllocation(order: [String]) {
        for state in 0..<2401 { // 7^4
            var encoded = state
            let candidates = order.enumerated().compactMap { index, id -> EarAllocator.Candidate? in
                let value = encoded % 7
                encoded /= 7
                guard value != 0 else { return nil }
                let placement: CompactEarPlacement = [.byRank, .first, .second][(value - 1) % 3]
                return EarAllocator.Candidate(moduleID: id,
                    configuration: CompactEarConfiguration(placement: placement, hasExtra: index.isMultiple(of: 2)),
                    waitsForYou: value > 3, borrowsSecond: false)
            }
            for briefID in [nil] + order.map(Optional.some) {
                let input = candidates.map {
                    EarAllocator.Candidate(moduleID: $0.moduleID, configuration: $0.configuration,
                        waitsForYou: $0.waitsForYou, borrowsSecond: $0.moduleID == briefID)
                }
                for swapped in [false, true] {
                    let expected = baseline(input, swapped: swapped)
                    let actual = EarAllocator.allocate(input, swapsSides: swapped)
                    if actual != expected {
                        Issue.record("Allocation changed: order=\(order), state=\(state), brief=\(briefID ?? "none"), swapped=\(swapped); expected \(expected), got \(actual)")
                        return
                    }
                }
            }
        }
    }

    /// Frozen selection/placement logic from NotchViewModel.ears at e1cfec8. Keep this independent
    /// of the new allocator helpers: it is the behavior baseline, not a second production policy.
    private func baseline(_ modules: [EarAllocator.Candidate], swapped: Bool) -> EarAllocator.Allocation {
        func takesSecond(_ module: EarAllocator.Candidate) -> Bool {
            module.configuration.placement == .second || module.borrowsSecond
        }
        let waiting = modules.filter { $0.waitsForYou }
        let byPriority = waiting + modules.filter { !$0.waitsForYou }
        var firstClaim = modules.first { $0.configuration.placement == .first }
        let secondClaim = byPriority.first { $0.moduleID != firstClaim?.moduleID && takesSecond($0) }
        if let claimed = firstClaim, let second = secondClaim,
           modules.contains(where: { $0.waitsForYou && $0.moduleID != claimed.moduleID && $0.moduleID != second.moduleID }) {
            firstClaim = nil
        }
        let ordinarySecond = modules.first {
            !$0.waitsForYou && $0.moduleID != firstClaim?.moduleID && takesSecond($0)
        }
        let reserved = [firstClaim, ordinarySecond].compactMap { $0 }.filter { !$0.waitsForYou }
        let candidates = waiting + reserved + modules.filter { candidate in
            !candidate.waitsForYou && !reserved.contains { $0.moduleID == candidate.moduleID }
        }
        let chosen = candidates.prefix(2).map(\.moduleID)
        var picked = modules.filter { chosen.contains($0.moduleID) }
        let selectedFirst = picked.first { $0.configuration.placement == .first }
        let secondCandidates = picked.filter { $0.waitsForYou } + picked.filter { !$0.waitsForYou }
        let selectedSecond = secondCandidates.first { $0.moduleID != selectedFirst?.moduleID && takesSecond($0) }
        if picked.count > 1,
           let first = selectedFirst ?? picked.first(where: { $0.moduleID != selectedSecond?.moduleID }),
           let second = selectedSecond ?? picked.first(where: { $0.moduleID != first.moduleID }) {
            picked = [first, second]
        }
        var slots: [EarAllocator.Slot?] = []
        if picked.count == 1, let module = picked.first {
            let main = EarAllocator.Slot(moduleID: module.moduleID, content: .main)
            let extra = module.configuration.hasExtra ? EarAllocator.Slot(moduleID: module.moduleID, content: .extra) : nil
            slots = module.configuration.placement == .second ? [extra, main] : [main, extra]
        } else {
            slots = picked.map { EarAllocator.Slot(moduleID: $0.moduleID, content: .main) }
        }
        let first = slots.first ?? nil
        let second = slots.count > 1 ? slots[1] : nil
        return swapped ? .init(left: second, right: first) : .init(left: first, right: second)
    }
}
