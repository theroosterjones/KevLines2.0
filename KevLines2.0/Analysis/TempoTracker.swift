import Foundation
import CoreMedia

/// Tracks exercise tempo by classifying the primary joint angle's movement into phases:
///   eccentric → pauseBottom → concentric → pauseTop → (repeat)
///
/// Uses angular velocity (first derivative of angle over time) to determine direction of movement.
final class TempoTracker {

    /// Degrees-per-second below which we consider movement "paused".
    let velocityThreshold: Float

    /// Number of samples to use for velocity smoothing.
    let windowSize: Int

    private(set) var currentPhase: TempoPhase = .pauseTop

    private struct Sample {
        let angle: Float
        let time: Double  // seconds
    }

    private var samples: [Sample] = []

    init(velocityThreshold: Float = 15.0, windowSize: Int = 5) {
        self.velocityThreshold = velocityThreshold
        self.windowSize = windowSize
    }

    /// Feed the current primary angle and frame timestamp. Returns the detected phase.
    @discardableResult
    func update(angle: Float, time: CMTime) -> TempoPhase {
        let timeSec = CMTimeGetSeconds(time)
        samples.append(Sample(angle: angle, time: timeSec))

        // Keep only the most recent samples
        if samples.count > windowSize {
            samples.removeFirst(samples.count - windowSize)
        }

        guard samples.count >= 2 else { return currentPhase }

        let velocity = computeAngularVelocity()

        if velocity < -velocityThreshold {
            // Angle decreasing = joint closing = eccentric (e.g., lowering into squat)
            currentPhase = .eccentric
        } else if velocity > velocityThreshold {
            // Angle increasing = joint opening = concentric (e.g., standing up)
            currentPhase = .concentric
        } else {
            // Near-zero velocity = pause. Classify as bottom or top based on last moving phase.
            switch currentPhase {
            case .eccentric:
                currentPhase = .pauseBottom
            case .concentric:
                currentPhase = .pauseTop
            default:
                break  // stay in current pause phase
            }
        }

        return currentPhase
    }

    func reset() {
        samples.removeAll()
        currentPhase = .pauseTop
    }

    // MARK: - Private

    /// Linear regression slope of angle over time (degrees per second).
    private func computeAngularVelocity() -> Float {
        guard samples.count >= 2 else { return 0 }

        let n = Float(samples.count)
        var sumT: Float = 0, sumA: Float = 0, sumTA: Float = 0, sumTT: Float = 0
        let t0 = samples[0].time

        for s in samples {
            let t = Float(s.time - t0)
            sumT += t
            sumA += s.angle
            sumTA += t * s.angle
            sumTT += t * t
        }

        let denom = n * sumTT - sumT * sumT
        guard abs(denom) > 1e-6 else { return 0 }

        return (n * sumTA - sumT * sumA) / denom
    }
}
