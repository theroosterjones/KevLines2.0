import Foundation
import simd

/// Exponential moving average filter for landmark positions.
/// Ports the Python `smooth_landmark()` with configurable alpha.
final class LandmarkSmoother {

    /// Smoothing factor. 0 = full smoothing (frozen), 1 = no smoothing (raw input).
    let alpha: Float

    private var history: [String: SIMD2<Float>] = [:]

    init(alpha: Float = 0.7) {
        self.alpha = alpha
    }

    func smooth(key: String, position: SIMD2<Float>) -> SIMD2<Float> {
        guard let prev = history[key] else {
            history[key] = position
            return position
        }
        let smoothed = alpha * position + (1 - alpha) * prev
        history[key] = smoothed
        return smoothed
    }

    func reset() {
        history.removeAll()
    }
}
