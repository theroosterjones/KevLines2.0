import Foundation
import simd

/// Ported from hacksquat_analyzer.py.
/// Tracks knee angle, hip angle, spine angle (relative to vertical), extended spine line.
final class HackSquatAnalyzer: ExerciseAnalyzer {

    let exerciseType: ExerciseType = .hackSquat
    let side: BodySide

    var requiredLandmarks: [PoseLandmarkType] {
        [.ankle(side), .knee(side), .hip(side), .shoulder(side), .nose]
    }

    private let smoother = LandmarkSmoother(alpha: 0.7)
    private let repCounter = RepCounter(extendedThreshold: 160, flexedThreshold: 100)
    private let tempoTracker = TempoTracker()

    init(side: BodySide) {
        self.side = side
    }

    func analyze(landmarks: PoseResult) -> FrameAnalysis {
        guard let rawAnkle    = landmarks.position(for: .ankle(side)),
              let rawKnee     = landmarks.position(for: .knee(side)),
              let rawHip      = landmarks.position(for: .hip(side)),
              let rawShoulder = landmarks.position(for: .shoulder(side)),
              let rawNose     = landmarks.position(for: .nose) else {
            return .empty
        }

        let ankle    = smoother.smooth(key: "\(side)_ankle", position: rawAnkle)
        let knee     = smoother.smooth(key: "\(side)_knee", position: rawKnee)
        let hip      = smoother.smooth(key: "\(side)_hip", position: rawHip)
        let shoulder = smoother.smooth(key: "\(side)_shoulder", position: rawShoulder)
        let nose     = smoother.smooth(key: "nose", position: rawNose)

        let kneeAngle  = AngleCalculator.angle(a: ankle, b: knee, c: hip)
        let hipAngle   = AngleCalculator.angle(a: knee, b: hip, c: shoulder)
        let spineAngle = calculateSpineAngle(hip: hip, shoulder: shoulder)

        repCounter.update(angle: kneeAngle)

        var instructions: [OverlayInstruction] = []

        // Extended spine line
        instructions.append(.extendedLine(from: hip, through: shoulder, color: .cyan, width: 2))

        // Skeleton
        instructions.append(.line(from: ankle, to: knee, color: .green, width: 3))
        instructions.append(.line(from: knee, to: hip, color: .green, width: 3))
        instructions.append(.line(from: hip, to: shoulder, color: .red, width: 3))
        instructions.append(.line(from: shoulder, to: nose, color: .red, width: 2))

        // Key joints
        instructions.append(.circle(at: knee, radius: 12, color: .red, filled: true))
        instructions.append(.circle(at: hip, radius: 12, color: .red, filled: true))
        instructions.append(.circle(at: ankle, radius: 10, color: .yellow, filled: true))
        instructions.append(.circle(at: shoulder, radius: 10, color: .yellow, filled: true))

        // Angle labels
        instructions.append(.text("Knee: \(Int(kneeAngle))",
            at: SIMD2(knee.x - 0.05, knee.y + 0.05), color: .white, size: 18))
        instructions.append(.text("Hip: \(Int(hipAngle))",
            at: SIMD2(hip.x - 0.05, hip.y - 0.03), color: .white, size: 18))
        instructions.append(.text("Spine: \(Int(spineAngle))",
            at: SIMD2(shoulder.x - 0.05, shoulder.y - 0.03), color: .white, size: 18))

        // HUD
        instructions.append(.text("Reps: \(repCounter.count)",
            at: SIMD2(0.02, 0.05), color: .white, size: 24))

        return FrameAnalysis(
            angles: [
                JointAngle(joint: .knee, degrees: kneeAngle),
                JointAngle(joint: .hip, degrees: hipAngle),
                JointAngle(joint: .spine, degrees: spineAngle)
            ],
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

    /// Spine angle relative to vertical, matching Python's calculate_spine_angle.
    private func calculateSpineAngle(hip: SIMD2<Float>, shoulder: SIMD2<Float>) -> Float {
        let verticalPoint = SIMD2<Float>(hip.x, hip.y - 0.5)
        return AngleCalculator.angle(a: verticalPoint, b: hip, c: shoulder)
    }
}
