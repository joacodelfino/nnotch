import Foundation

/// Counts deliberate horizontal reversals, ignoring small pointer jitter.
struct DragShakeDetector {
    private var anchor: CGFloat?
    private var direction = 0
    private var reversals = 0
    private var started: TimeInterval = 0

    mutating func reset() { self = Self() }

    mutating func sample(x: CGFloat, time: TimeInterval) -> Bool {
        if anchor == nil || time - started > 0.8 {
            reset()
            anchor = x
            started = time
            return false
        }
        let delta = x - anchor!
        guard abs(delta) >= 18 else { return false }
        let next = delta > 0 ? 1 : -1
        if direction != 0 && next != direction { reversals += 1 }
        direction = next
        anchor = x
        if reversals >= 3 {
            reset()
            return true
        }
        return false
    }
}
