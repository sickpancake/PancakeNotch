import Foundation

/// Event-driven paging math. Position is measured in pages; deltas and velocity in points.
struct HomeScrollMotion {
    private(set) var origin = 0
    private(set) var travel: CGFloat = 0
    private(set) var velocity: CGFloat = 0
    private var travelX: CGFloat = 0
    private var lastTime: TimeInterval = 0
    private(set) var active = false
    private(set) var vertical = false
    private var horizontal = false

    mutating func begin(page: Int, time: TimeInterval) {
        self = Self()
        origin = page
        lastTime = time
        active = true
    }

    mutating func move(y: CGFloat, x: CGFloat, time: TimeInterval) {
        guard active else { return }
        travel += -y
        travelX += x
        if !vertical && !horizontal, max(abs(travel), abs(travelX)) >= 3 {
            vertical = abs(travel) > abs(travelX)
            horizontal = !vertical
        }
        let elapsed = time - lastTime
        if elapsed > 0, y != 0 { velocity = -y / max(0.008, elapsed) }
        lastTime = time
    }

    func position(height: CGFloat, count: Int) -> CGFloat {
        guard vertical else { return CGFloat(origin) }
        let distance = travel / max(1, height)
        let lower = CGFloat(max(0, origin - 1) - origin)
        let upper = CGFloat(min(max(0, count - 1), origin + 1) - origin)
        let bounded = min(upper, max(lower, distance))
        let excess = distance - bounded
        let rubber = excess / (1 + abs(excess) * 8) * 0.4
        return CGFloat(origin) + bounded + rubber
    }

    func target(height: CGFloat, count: Int, time: TimeInterval) -> Int {
        guard vertical else { return origin }
        let speed = time - lastTime < 0.12 ? velocity : 0
        let step: Int
        if abs(speed) >= 450 {
            // A fast reversal first returns to the origin; don't reveal two neighbours at once.
            step = speed * travel < 0 ? 0 : (speed > 0 ? 1 : -1)
        }
        else { step = min(1, max(-1, Int((travel / max(1, height)).rounded()))) }
        return min(max(0, count - 1), max(0, origin + step))
    }

    mutating func end() { active = false }
}
