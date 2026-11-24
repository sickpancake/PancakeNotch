/// A module's preferred logical spot, before the user's Swap sides setting.
public enum CompactEarPlacement: Equatable, Sendable {
    /// Take a spot according to the user's module order.
    case byRank
    /// Reserve #1 ahead of ordinary activity, yielding when needed to show waiting alerts.
    case first
    /// Reserve #2 ahead of ordinary activity; alone, keep the main view in #2.
    case second
}

/// Describes available ear content without constructing SwiftUI views. This stays available even
/// when the module is inactive, so shrinking after a click can still show the selected module.
public struct CompactEarConfiguration: Equatable, Sendable {
    public var placement: CompactEarPlacement
    public var hasExtra: Bool

    public init(placement: CompactEarPlacement = .byRank, hasExtra: Bool = false) {
        self.placement = placement
        self.hasExtra = hasExtra
    }
}

/// Chooses owners separately from placing them. Inputs are eligible modules in the user's order;
/// the result contains no views and is shared by rendering and pointer targeting.
enum EarAllocator {
    struct Candidate: Sendable {
        let moduleID: String
        let configuration: CompactEarConfiguration
        let waitsForYou: Bool
        /// A brief badge on an otherwise inactive module borrows #2 beside another owner.
        let borrowsSecond: Bool

        var takesSecond: Bool { configuration.placement == .second || borrowsSecond }
    }

    struct Slot: Equatable, Sendable {
        enum Content: String, Sendable { case main, extra }
        let moduleID: String
        let content: Content
        var id: String { moduleID + "." + content.rawValue }
    }

    struct Allocation: Equatable, Sendable {
        /// Which ear shows the "+n" overflow count.
        enum Side: String, Sendable { case left, right }

        var left: Slot?
        var right: Slot?
        /// Candidates that didn't fit the two spots, in the input's (rank) order.
        var displacedModuleIDs: [String] = []
        /// The ear the count belongs to: the side most of the displaced candidates wanted
        /// (#1 for `first`/`byRank`, #2 for `second`/the borrowed spot). A tie goes to the left.
        var overflowSide: Side?

        init(left: Slot? = nil, right: Slot? = nil, displacedModuleIDs: [String] = [], overflowSide: Side? = nil) {
            self.left = left
            self.right = right
            self.displacedModuleIDs = displacedModuleIDs
            self.overflowSide = overflowSide
        }
    }

    static func allocate(_ candidates: [Candidate], swapsSides: Bool) -> Allocation {
        let chosen = choose(candidates)
        var result = place(chosen)
        result.displacedModuleIDs = candidates.filter { candidate in
            !chosen.contains { $0.moduleID == candidate.moduleID }
        }.map(\.moduleID)
        let displaced = candidates.filter { result.displacedModuleIDs.contains($0.moduleID) }
        let onTheRight = displaced.filter(\.takesSecond).count
        result.overflowSide = result.displacedModuleIDs.isEmpty
            ? nil
            : (onTheRight > displaced.count - onTheRight ? .right : .left)
        if swapsSides {
            swap(&result.left, &result.right)
            if result.overflowSide == .left { result.overflowSide = .right }
            else if result.overflowSide == .right { result.overflowSide = .left }
        }
        return result
    }

    private static func choose(_ candidates: [Candidate]) -> [Candidate] {
        let waiting = candidates.filter(\.waitsForYou)
        let ordinary = candidates.filter { !$0.waitsForYou }
        var firstReservation = candidates.first { $0.configuration.placement == .first }
        let secondReservation = (waiting + ordinary).first {
            $0.moduleID != firstReservation?.moduleID && $0.takesSecond
        }
        // Keep the second reservation, but release the first if both would hide a waiting alert.
        if let first = firstReservation, let second = secondReservation,
           waiting.contains(where: { $0.moduleID != first.moduleID && $0.moduleID != second.moduleID }) {
            firstReservation = nil
        }
        let ordinarySecond = ordinary.first { $0.moduleID != firstReservation?.moduleID && $0.takesSecond }
        let reserved = [firstReservation, ordinarySecond].compactMap { $0 }.filter { !$0.waitsForYou }
        let remaining = ordinary.filter { candidate in !reserved.contains { $0.moduleID == candidate.moduleID } }
        let owners = (waiting + reserved + remaining).prefix(2).map(\.moduleID)
        // Selection priority does not change the relative sides of ordinary ranked modules.
        return candidates.filter { owners.contains($0.moduleID) }
    }

    private static func place(_ chosen: [Candidate]) -> Allocation {
        guard let only = chosen.first else { return Allocation() }
        func main(_ candidate: Candidate) -> Slot { Slot(moduleID: candidate.moduleID, content: .main) }
        if chosen.count == 1 {
            let extra = only.configuration.hasExtra ? Slot(moduleID: only.moduleID, content: .extra) : nil
            // A brief Shelf badge borrows #2 only beside another module; alone it stays in #1.
            return only.configuration.placement == .second
                ? Allocation(left: extra, right: main(only)) : Allocation(left: main(only), right: extra)
        }
        let first = chosen.first { $0.configuration.placement == .first }
        let byAttention = chosen.filter(\.waitsForYou) + chosen.filter { !$0.waitsForYou }
        let second = byAttention.first { $0.moduleID != first?.moduleID && $0.takesSecond }
        let rankedFirst = chosen[0], rankedSecond = chosen[1]
        let left = first ?? (rankedFirst.moduleID == second?.moduleID ? rankedSecond : rankedFirst)
        let right = second ?? (rankedFirst.moduleID == left.moduleID ? rankedSecond : rankedFirst)
        return Allocation(left: main(left), right: main(right))
    }
}
