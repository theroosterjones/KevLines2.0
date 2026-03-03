import Foundation

/// Generic angle-threshold state machine for counting reps.
/// Ported from the Python row_analyzer rep counting logic.
///
/// A rep completes when the tracked angle transitions:
///   extended (above extendedThreshold) → flexed (below flexedThreshold) → extended
final class RepCounter {

    let extendedThreshold: Float
    let flexedThreshold: Float

    private(set) var count: Int = 0
    private(set) var state: RepState = .extended

    init(extendedThreshold: Float, flexedThreshold: Float) {
        self.extendedThreshold = extendedThreshold
        self.flexedThreshold = flexedThreshold
    }

    /// Feed the current angle value. Returns true if a rep just completed.
    @discardableResult
    func update(angle: Float) -> Bool {
        switch state {
        case .extended where angle < flexedThreshold:
            state = .flexed
            return false
        case .flexed where angle > extendedThreshold:
            count += 1
            state = .extended
            return true
        default:
            return false
        }
    }

    func reset() {
        count = 0
        state = .extended
    }
}
