import Foundation
import simd

/// Ported from FitnessAnalyzer.analyze_squat() in app.py.
/// Tracks knee angle with rep counting.
final class SquatAnalyzer: ExerciseAnalyzer {

    let exerciseType: ExerciseType = .squat
    let side: BodySide

    var requiredLandmarks: [PoseLandmarkType] {
        [.hip(side), .knee(side), .ankle(side)]
    }

    private let smoother = LandmarkSmoother(alpha: 0.7)
    private let repCounter = RepCounter(extendedThreshold: 160, flexedThreshold: 100)
    private let tempoTracker = TempoTracker()

    init(side: BodySide) {
        self.side = side
    }

    func analyze(landmarks: PoseResult) -> FrameAnalysis {
        guard let rawHip   = landmarks.position(for: .hip(side)),
              let rawKnee  = landmarks.position(for: .knee(side)),
              let rawAnkle = landmarks.position(for: .ankle(side)) else {
            return .empty
        }

        let hip   = smoother.smooth(key: "\(side)_hip", position: rawHip)
        let knee  = smoother.smooth(key: "\(side)_knee", position: rawKnee)
        let ankle = smoother.smooth(key: "\(side)_ankle", position: rawAnkle)

        let kneeAngle = AngleCalculator.angle(a: hip, b: knee, c: ankle)

        repCounter.update(angle: kneeAngle)

        var instructions: [OverlayInstruction] = []

        // Skeleton
        instructions.append(.line(from: hip, to: knee, color: .green, width: 3))
        instructions.append(.line(from: knee, to: ankle, color: .green, width: 3))

        // Key joints
        instructions.append(.circle(at: knee, radius: 12, color: .red, filled: true))
        instructions.append(.circle(at: hip, radius: 10, color: .yellow, filled: true))
        instructions.append(.circle(at: ankle, radius: 10, color: .yellow, filled: true))

        // Angle label
        instructions.append(.text("Knee: \(Int(kneeAngle))",
            at: SIMD2(knee.x - 0.05, knee.y + 0.05), color: .white, size: 20))

        // HUD
        instructions.append(.text("Reps: \(repCounter.count)",
            at: SIMD2(0.02, 0.05), color: .white, size: 24))

        return FrameAnalysis(
            angles: [JointAngle(joint: .knee, degrees: kneeAngle)],
            repCount: repCounter.count,
            repState: repCounter.state,
            tempoPhase: tempoTracker.update(angle: kneeAngle, time: .zero),
            overlayInstructions: instructions
        )
    }

    func reset() {
        smoother.reset()
        repCounter.reset()
        tempoTracker.reset()
    }
}
