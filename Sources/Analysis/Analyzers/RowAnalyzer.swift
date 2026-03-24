import Foundation
import simd

/// Ported from row_analyzer.py.
/// Tracks elbow angle, shoulder angle, spine line, back line, chest marker, and rep count.
final class RowAnalyzer: ExerciseAnalyzer {

    let exerciseType: ExerciseType = .row
    let side: BodySide

    var requiredLandmarks: [PoseLandmarkType] {
        [
            .shoulder(side), .elbow(side), .wrist(side), .hip(side),
            .shoulder(side.opposite), .ear(side), .ear(side.opposite)
        ]
    }

    private let smoother = LandmarkSmoother(alpha: 0.7)
    private let repCounter = RepCounter(extendedThreshold: 150, flexedThreshold: 100)
    private let tempoTracker = TempoTracker()

    init(side: BodySide) {
        self.side = side
    }

    func analyze(landmarks: PoseResult) -> FrameAnalysis {
        guard let rawShoulder = landmarks.position(for: .shoulder(side)),
              let rawElbow    = landmarks.position(for: .elbow(side)),
              let rawWrist    = landmarks.position(for: .wrist(side)),
              let rawHip      = landmarks.position(for: .hip(side)),
              let rawOppShoulder = landmarks.position(for: .shoulder(side.opposite)) else {
            return .empty
        }

        let shoulder    = smoother.smooth(key: "\(side)_shoulder",          position: rawShoulder)
        let elbow       = smoother.smooth(key: "\(side)_elbow",             position: rawElbow)
        let wrist       = smoother.smooth(key: "\(side)_wrist",             position: rawWrist)
        let hip         = smoother.smooth(key: "\(side)_hip",               position: rawHip)
        let oppShoulder = smoother.smooth(key: "\(side.opposite)_shoulder", position: rawOppShoulder)

        let w_shoulder = landmarks.worldPosition(for: .shoulder(side)).map { smoother.smooth3D(key: "\(side)_shoulder", position: $0) }
        let w_elbow    = landmarks.worldPosition(for: .elbow(side))   .map { smoother.smooth3D(key: "\(side)_elbow",    position: $0) }
        let w_wrist    = landmarks.worldPosition(for: .wrist(side))   .map { smoother.smooth3D(key: "\(side)_wrist",    position: $0) }
        let w_hip      = landmarks.worldPosition(for: .hip(side))     .map { smoother.smooth3D(key: "\(side)_hip",      position: $0) }

        let elbowAngle: Float
        if let ws = w_shoulder, let we = w_elbow, let ww = w_wrist {
            elbowAngle = AngleCalculator.angle3D(a: ws, b: we, c: ww)
        } else {
            elbowAngle = AngleCalculator.angle(a: shoulder, b: elbow, c: wrist)
        }

        let shoulderAngle: Float
        if let wh = w_hip, let ws = w_shoulder, let we = w_elbow {
            shoulderAngle = AngleCalculator.angle3D(a: wh, b: ws, c: we)
        } else {
            shoulderAngle = AngleCalculator.angle(a: hip, b: shoulder, c: elbow)
        }

        repCounter.update(angle: elbowAngle)

        let chest = (shoulder + oppShoulder) / 2.0

        var instructions: [OverlayInstruction] = []

        // Extended forearm line (background)
        instructions.append(.extendedLine(from: wrist, through: elbow, color: .cyan, width: 2))

        // Arm skeleton
        instructions.append(.line(from: shoulder, to: elbow, color: .yellow, width: 3))
        instructions.append(.line(from: elbow, to: wrist, color: .yellow, width: 3))

        // Back line (shoulder to opposite shoulder)
        instructions.append(.line(from: shoulder, to: oppShoulder, color: .magenta, width: 3))

        // Key joints
        instructions.append(.circle(at: elbow, radius: 10, color: .red, filled: true))
        instructions.append(.circle(at: shoulder, radius: 10, color: .red, filled: true))
        instructions.append(.circle(at: chest, radius: 10, color: .orange, filled: true))
        instructions.append(.circle(at: oppShoulder, radius: 8, color: .green, filled: true))

        // Angle labels
        let elbowLabel = SIMD2<Float>(elbow.x - 0.05, elbow.y + 0.05)
        let shoulderLabel = SIMD2<Float>(shoulder.x - 0.05, shoulder.y - 0.03)
        let chestLabel = SIMD2<Float>(chest.x - 0.03, chest.y - 0.02)

        instructions.append(.text("Elbow: \(Int(elbowAngle))", at: elbowLabel, color: .white, size: 20))
        instructions.append(.text("Shoulder: \(Int(shoulderAngle))", at: shoulderLabel, color: .white, size: 20))
        instructions.append(.text("Chest", at: chestLabel, color: .white, size: 20))

        // HUD
        instructions.append(.text("Reps: \(repCounter.count)", at: SIMD2(0.02, 0.05), color: .white, size: 24))

        return FrameAnalysis(
            angles: [
                JointAngle(joint: .elbow, degrees: elbowAngle),
                JointAngle(joint: .shoulder, degrees: shoulderAngle)
            ],
            repCount: repCounter.count,
            repState: repCounter.state,
            tempoPhase: nil,  // TODO: wire up tempoTracker once primary angle is decided
            overlayInstructions: instructions
        )
    }

    func reset() {
        smoother.reset()
        repCounter.reset()
        tempoTracker.reset()
    }
}
