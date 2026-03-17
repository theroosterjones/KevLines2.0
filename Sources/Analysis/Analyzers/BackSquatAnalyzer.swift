import Foundation
import simd

/// Ported from backsquat_analyzer.py.
/// Tracks knee angle, hip angle, extended spine and leg lines.
final class BackSquatAnalyzer: ExerciseAnalyzer {

    let exerciseType: ExerciseType = .backSquat
    let side: BodySide

    var requiredLandmarks: [PoseLandmarkType] {
        [.ankle(side), .knee(side), .hip(side), .shoulder(side)]
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
              let rawShoulder = landmarks.position(for: .shoulder(side)) else {
            return .empty
        }

        let ankle    = smoother.smooth(key: "\(side)_ankle", position: rawAnkle)
        let knee     = smoother.smooth(key: "\(side)_knee", position: rawKnee)
        let hip      = smoother.smooth(key: "\(side)_hip", position: rawHip)
        let shoulder = smoother.smooth(key: "\(side)_shoulder", position: rawShoulder)

        let kneeAngle = AngleCalculator.angle(a: ankle, b: knee, c: hip)
        let hipAngle  = AngleCalculator.angle(a: knee, b: hip, c: shoulder)

        repCounter.update(angle: kneeAngle)

        var instructions: [OverlayInstruction] = []

        // Extended reference lines
        instructions.append(.extendedLine(from: hip, through: shoulder, color: .cyan, width: 2))
        instructions.append(.extendedLine(from: knee, through: hip, color: .cyan, width: 2))

        // Skeleton
        instructions.append(.line(from: ankle, to: knee, color: .green, width: 3))
        instructions.append(.line(from: knee, to: hip, color: .green, width: 3))
        instructions.append(.line(from: hip, to: shoulder, color: .red, width: 3))

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

        // HUD
        instructions.append(.text("Reps: \(repCounter.count)",
            at: SIMD2(0.02, 0.05), color: .white, size: 24))

        return FrameAnalysis(
            angles: [
                JointAngle(joint: .knee, degrees: kneeAngle),
                JointAngle(joint: .hip, degrees: hipAngle)
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
}
