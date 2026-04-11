import Foundation
import simd

/// Tracks hip angle (shoulder→hip→knee) and knee angle (hip→knee→ankle) for the deadlift.
/// Film from a strict side profile with the full body visible, shoulder to foot.
/// Primary rep-counting drive: hip extension (hinge opens from ~70° bent to ~170° standing).
final class DeadliftAnalyzer: ExerciseAnalyzer {

    let exerciseType: ExerciseType = .deadlift
    let side: BodySide

    var requiredLandmarks: [PoseLandmarkType] {
        [.shoulder(side), .hip(side), .knee(side), .ankle(side)]
    }

    private let smoother     = LandmarkSmoother()
    private let repCounter   = RepCounter(extendedThreshold: 160, flexedThreshold: 80)
    private let tempoTracker = TempoTracker()

    init(side: BodySide) {
        self.side = side
    }

    func analyze(landmarks: PoseResult) -> FrameAnalysis {
        guard let rawShoulder = landmarks.position(for: .shoulder(side)),
              let rawHip      = landmarks.position(for: .hip(side)),
              let rawKnee     = landmarks.position(for: .knee(side)),
              let rawAnkle    = landmarks.position(for: .ankle(side)) else {
            return .empty
        }

        let ts       = landmarks.timestamp
        let shoulder = smoother.smooth(key: "\(side)_shoulder", position: rawShoulder, timestamp: ts)
        let hip      = smoother.smooth(key: "\(side)_hip",      position: rawHip,      timestamp: ts)
        let knee     = smoother.smooth(key: "\(side)_knee",     position: rawKnee,     timestamp: ts)
        let ankle    = smoother.smooth(key: "\(side)_ankle",    position: rawAnkle,    timestamp: ts)

        let w_shoulder = landmarks.worldPosition(for: .shoulder(side)).map { smoother.smooth3D(key: "\(side)_shoulder", position: $0, timestamp: ts) }
        let w_hip      = landmarks.worldPosition(for: .hip(side))     .map { smoother.smooth3D(key: "\(side)_hip",      position: $0, timestamp: ts) }
        let w_knee     = landmarks.worldPosition(for: .knee(side))    .map { smoother.smooth3D(key: "\(side)_knee",     position: $0, timestamp: ts) }
        let w_ankle    = landmarks.worldPosition(for: .ankle(side))   .map { smoother.smooth3D(key: "\(side)_ankle",    position: $0, timestamp: ts) }

        let hipAngle: Float
        if let ws = w_shoulder, let wh = w_hip, let wk = w_knee {
            hipAngle = AngleCalculator.angle3D(a: ws, b: wh, c: wk)
        } else {
            hipAngle = AngleCalculator.angle(a: shoulder, b: hip, c: knee)
        }

        let kneeAngle: Float
        if let wh = w_hip, let wk = w_knee, let wa = w_ankle {
            kneeAngle = AngleCalculator.angle3D(a: wh, b: wk, c: wa)
        } else {
            kneeAngle = AngleCalculator.angle(a: hip, b: knee, c: ankle)
        }

        repCounter.update(angle: hipAngle, timestamp: ts)

        var instructions: [OverlayInstruction] = []

        // Spine and leg skeleton
        instructions.append(.line(from: shoulder, to: hip,   color: .green,  width: 3))
        instructions.append(.line(from: hip,      to: knee,  color: .green,  width: 3))
        instructions.append(.line(from: knee,     to: ankle, color: .green,  width: 3))

        // Key joints
        instructions.append(.circle(at: hip,      radius: 12, color: .red,    filled: true))
        instructions.append(.circle(at: knee,     radius: 10, color: .yellow, filled: true))
        instructions.append(.circle(at: shoulder, radius: 10, color: .yellow, filled: true))
        instructions.append(.circle(at: ankle,    radius: 8,  color: .orange, filled: true))

        // Angle labels
        let hipLabelX = hip.x + 0.02
        instructions.append(.text("Hip: \(Int(hipAngle))\u{00B0}",
            at: SIMD2(hipLabelX, hip.y - 0.04), color: .white, size: 20))
        instructions.append(.text("Knee: \(Int(kneeAngle))\u{00B0}",
            at: SIMD2(knee.x + 0.02, knee.y - 0.04), color: .cyan, size: 18))

        // HUD
        instructions.append(.text("Reps: \(repCounter.count)",
            at: SIMD2(0.02, 0.05), color: .white, size: 24))

        return FrameAnalysis(
            angles: [
                JointAngle(joint: .hip,  degrees: hipAngle),
                JointAngle(joint: .knee, degrees: kneeAngle)
            ],
            repCount: repCounter.count,
            repState: repCounter.state,
            tempoPhase: tempoTracker.update(angle: hipAngle, timestamp: ts),
            overlayInstructions: instructions
        )
    }

    func reset() {
        smoother.reset()
        repCounter.reset()
        tempoTracker.reset()
    }
}
