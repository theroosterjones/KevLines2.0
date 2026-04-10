import Foundation
import CoreMedia
import simd

/// Tracks elbow flexion/extension angle (shoulder → elbow → wrist) for bicep curls,
/// tricep extensions, and any elbow-dominant movement. Filmed from the side.
final class ElbowAnalyzer: ExerciseAnalyzer {

    let exerciseType: ExerciseType = .elbowCurl
    let side: BodySide

    var requiredLandmarks: [PoseLandmarkType] {
        [.shoulder(side), .elbow(side), .wrist(side)]
    }

    private let smoother = LandmarkSmoother()
    private let repCounter = RepCounter(extendedThreshold: 155, flexedThreshold: 60)
    private let tempoTracker = TempoTracker()

    init(side: BodySide) {
        self.side = side
    }

    func analyze(landmarks: PoseResult) -> FrameAnalysis {
        guard let rawShoulder = landmarks.position(for: .shoulder(side)),
              let rawElbow    = landmarks.position(for: .elbow(side)),
              let rawWrist    = landmarks.position(for: .wrist(side)) else {
            return .empty
        }

        let ts = landmarks.timestamp
        let shoulder = smoother.smooth(key: "\(side)_shoulder", position: rawShoulder, timestamp: ts)
        let elbow    = smoother.smooth(key: "\(side)_elbow",    position: rawElbow,    timestamp: ts)
        let wrist    = smoother.smooth(key: "\(side)_wrist",    position: rawWrist,    timestamp: ts)

        let w_shoulder = landmarks.worldPosition(for: .shoulder(side)).map { smoother.smooth3D(key: "\(side)_shoulder", position: $0, timestamp: ts) }
        let w_elbow    = landmarks.worldPosition(for: .elbow(side))   .map { smoother.smooth3D(key: "\(side)_elbow",    position: $0, timestamp: ts) }
        let w_wrist    = landmarks.worldPosition(for: .wrist(side))   .map { smoother.smooth3D(key: "\(side)_wrist",    position: $0, timestamp: ts) }

        let elbowAngle: Float
        if let ws = w_shoulder, let we = w_elbow, let ww = w_wrist {
            elbowAngle = AngleCalculator.angle3D(a: ws, b: we, c: ww)
        } else {
            elbowAngle = AngleCalculator.angle(a: shoulder, b: elbow, c: wrist)
        }

        repCounter.update(angle: elbowAngle, timestamp: ts)
        let frameTime = CMTimeMakeWithSeconds(landmarks.timestamp, preferredTimescale: 600)
        let phase = tempoTracker.update(angle: elbowAngle, time: frameTime)

        var instructions: [OverlayInstruction] = []

        // Forearm extension reference line (background reference)
        instructions.append(.extendedLine(from: elbow, through: wrist, color: .cyan, width: 2))

        // Upper arm and forearm
        instructions.append(.line(from: shoulder, to: elbow, color: .yellow, width: 3))
        instructions.append(.line(from: elbow, to: wrist, color: .yellow, width: 3))

        // Joints
        instructions.append(.circle(at: shoulder, radius: 10, color: .red,    filled: true))
        instructions.append(.circle(at: elbow,    radius: 12, color: .red,    filled: true))
        instructions.append(.circle(at: wrist,    radius: 8,  color: .orange, filled: true))

        // Angle label near elbow
        let elbowLabel = SIMD2<Float>(elbow.x + 0.03, elbow.y)
        instructions.append(.text("Elbow: \(Int(elbowAngle))\u{00B0}", at: elbowLabel, color: .white, size: 20))

        // HUD
        instructions.append(.text("Reps: \(repCounter.count)", at: SIMD2(0.02, 0.05), color: .white, size: 24))
        instructions.append(.text(phase.rawValue,               at: SIMD2(0.02, 0.11), color: .cyan,  size: 18))

        return FrameAnalysis(
            angles: [JointAngle(joint: .elbow, degrees: elbowAngle)],
            repCount: repCounter.count,
            repState: repCounter.state,
            tempoPhase: phase,
            overlayInstructions: instructions
        )
    }

    func reset() {
        smoother.reset()
        repCounter.reset()
        tempoTracker.reset()
    }
}
