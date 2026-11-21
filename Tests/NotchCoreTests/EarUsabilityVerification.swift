import Testing
@testable import NotchCore

enum EarVerificationInputs {
    static let ids = ["nowPlaying", "shelf", "agents", "timer", "keepAwake", "aiUsage"]
    static func orders(_ ids: [String]) -> [[String]] {
        ids.isEmpty ? [[]] : ids.flatMap { id in orders(ids.filter { $0 != id }).map { [id] + $0 } }
    }
}

struct EarUsabilityVerification {
    @Test(arguments: EarVerificationInputs.orders(EarVerificationInputs.ids))
    func sixModuleStatesPreserveUsability(order: [String]) {
        for state in 0..<192 {
            var bits = state
            func take(_ base: Int) -> Int { defer { bits /= base }; return bits % base }
            let music = take(2), shelf = take(2), agent = take(3), timer = take(4), awake = take(2), usage = take(2)
            for brief in [false, true] {
                let candidates = order.compactMap { id -> EarAllocator.Candidate? in
                    let active: Bool
                    let placement: CompactEarPlacement
                    let waiting: Bool
                    switch id {
                    case "nowPlaying": active = music > 0; placement = .byRank; waiting = false
                    case "shelf": active = shelf > 0; placement = .byRank; waiting = false
                    case "agents": active = agent > 0; placement = .byRank; waiting = agent == 2
                    case "timer": active = timer > 0; placement = timer >= 2 ? .second : .byRank; waiting = timer == 3
                    case "keepAwake": active = awake > 0; placement = .first; waiting = false
                    default: active = usage > 0; placement = .byRank; waiting = false
                    }
                    guard active || (id == "shelf" && brief) else { return nil }
                    return .init(moduleID: id, configuration: .init(placement: placement, hasExtra: id == "nowPlaying"),
                                 waitsForYou: waiting, borrowsSecond: id == "shelf" && brief && !active)
                }
                let normal = EarAllocator.allocate(candidates, swapsSides: false)
                for swapped in [false, true] {
                    let result = EarAllocator.allocate(candidates, swapsSides: swapped)
                    let context = "order=\(order), state=\(state), brief=\(brief), swapped=\(swapped)"
                    if let failure = violation(result, candidates: candidates, normal: normal, swapped: swapped) {
                        Issue.record("\(failure): \(context); slots=\(result)")
                        return
                    }
                }
            }
        }
    }

    private func violation(_ result: EarAllocator.Allocation, candidates: [EarAllocator.Candidate],
                           normal: EarAllocator.Allocation, swapped: Bool) -> String? {
        if swapped && (result.left != normal.right || result.right != normal.left) { return "SWAPPED_SIDES" }
        let left = swapped ? result.right : result.left, right = swapped ? result.left : result.right
        let slots = [left, right].compactMap { $0 }
        let mains = slots.filter { $0.content == .main }
        let owners = Set(mains.map(\.moduleID))
        if mains.count != min(2, candidates.count) || owners.count != mains.count { return "CAPACITY" }
        let waiting = candidates.filter(\.waitsForYou).prefix(2).map(\.moduleID)
        if !Set(waiting).isSubset(of: owners) { return "WAITING_VISIBLE" }
        for slot in slots {
            guard let candidate = candidates.first(where: { $0.moduleID == slot.moduleID }) else { return "ELIGIBLE_CONTENT" }
            if slot.content == .extra && (owners.count != 1 || !candidate.configuration.hasExtra) { return "ELIGIBLE_CONTENT" }
        }
        if candidates.count == 1, let only = candidates.first {
            let main = EarAllocator.Slot(moduleID: only.moduleID, content: .main)
            let extra = only.configuration.hasExtra ? EarAllocator.Slot(moduleID: only.moduleID, content: .extra) : nil
            let expectedLeft = only.configuration.placement == .second ? extra : main
            let expectedRight = only.configuration.placement == .second ? main : extra
            if left != expectedLeft || right != expectedRight { return "LONE_CONTENT" }
        }
        if owners.count == 2 {
            if slots.contains(where: { $0.content != .main }) { return "ELIGIBLE_CONTENT" }
            let chosen = candidates.filter { owners.contains($0.moduleID) }
            if owners.contains("keepAwake") && left?.moduleID != "keepAwake" { return "FIRST_PLACEMENT" }
            let seconds = chosen.filter { $0.configuration.placement == .second || $0.borrowsSecond }
            let claimedSecond = seconds.first(where: \.waitsForYou) ?? seconds.first
            if let claimedSecond, right?.moduleID != claimedSecond.moduleID { return "SECOND_PLACEMENT" }
            if !owners.contains("keepAwake"), claimedSecond == nil,
               left?.moduleID != chosen.first?.moduleID { return "RANKED_SIDES" }
        }
        if candidates.allSatisfy({ !$0.waitsForYou && $0.configuration.placement == .byRank && !$0.borrowsSecond }),
           owners != Set(candidates.prefix(2).map(\.moduleID)) { return "RANKED_OWNERS" }
        return nil
    }
}
