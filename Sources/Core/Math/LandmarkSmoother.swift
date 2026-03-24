import Foundation
import simd

/// Exponential moving average filter for landmark positions.
/// Ports the Python `smooth_landmark()` with configurable alpha.
final class LandmarkSmoother {

    /// Smoothing factor. 0 = full smoothing (frozen), 1 = no smoothing (raw input).
    let alpha: Float

    private var history2D: [String: SIMD2<Float>] = [:]
    private var history3D: [String: SIMD3<Float>] = [:]

    init(alpha: Float = 0.7) {
        self.alpha = alpha
    }

    /// Smooth a 2D normalized screen position (used for overlay drawing).
    func smooth(key: String, position: SIMD2<Float>) -> SIMD2<Float> {
        guard let prev = history2D[key] else {
            history2D[key] = position
            return position
        }
        let smoothed = alpha * position + (1 - alpha) * prev
        history2D[key] = smoothed
        return smoothed
    }

    /// Smooth a 3D world position (used for angle calculations).
    func smooth3D(key: String, position: SIMD3<Float>) -> SIMD3<Float> {
        guard let prev = history3D[key] else {
            history3D[key] = position
            return position
        }
        let smoothed = alpha * position + (1 - alpha) * prev
        history3D[key] = smoothed
        return smoothed
    }

    func reset() {
        history2D.removeAll()
        history3D.removeAll()
    }
}
