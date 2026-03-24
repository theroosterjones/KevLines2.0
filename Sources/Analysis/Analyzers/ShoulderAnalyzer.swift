import Foundation
import simd

/// Bilateral shoulder elevation/depression assessment filmed from behind (posterior/frontal plane).
///
/// Measures the tilt of the shoulder girdle relative to horizontal, identifying which side is
/// elevated or depressed, and compares against the pelvis as a reference baseline.
/// No rep counting — this is a postural assessment, not a rep-based exercise.
final class ShoulderAnalyzer: ExerciseAnalyzer {

    let exerciseType: ExerciseType = .shoulderAssessment
    // Bilateral — side is not applicable, stored as .left to satisfy the protocol.
    let side: BodySide = .left

    var requiredLandmarks: [PoseLandmarkType] {
        [.shoulder(.left), .shoulder(.right), .hip(.left), .hip(.right)]
    }

    private let smoother = LandmarkSmoother()

    init(side: BodySide) {
        // side parameter ignored — this analyzer always uses both sides
    }

    func analyze(landmarks: PoseResult) -> FrameAnalysis {
        guard let rawLeftShoulder  = landmarks.position(for: .shoulder(.left)),
              let rawRightShoulder = landmarks.position(for: .shoulder(.right)),
              let rawLeftHip       = landmarks.position(for: .hip(.left)),
              let rawRightHip      = landmarks.position(for: .hip(.right)) else {
            return .empty
        }

        let ts = landmarks.timestamp
        let leftShoulder  = smoother.smooth(key: "left_shoulder",  position: rawLeftShoulder,  timestamp: ts)
        let rightShoulder = smoother.smooth(key: "right_shoulder", position: rawRightShoulder, timestamp: ts)
        let leftHip       = smoother.smooth(key: "left_hip",       position: rawLeftHip,       timestamp: ts)
        let rightHip      = smoother.smooth(key: "right_hip",      position: rawRightHip,      timestamp: ts)

        let wLeftShoulder  = landmarks.worldPosition(for: .shoulder(.left)) .map { smoother.smooth3D(key: "left_shoulder",  position: $0, timestamp: ts) }
        let wRightShoulder = landmarks.worldPosition(for: .shoulder(.right)).map { smoother.smooth3D(key: "right_shoulder", position: $0, timestamp: ts) }
        let wLeftHip       = landmarks.worldPosition(for: .hip(.left))      .map { smoother.smooth3D(key: "left_hip",       position: $0, timestamp: ts) }
        let wRightHip      = landmarks.worldPosition(for: .hip(.right))     .map { smoother.smooth3D(key: "right_hip",      position: $0, timestamp: ts) }

        // Shoulder tilt angle from horizontal.
        // 3D version: uses metric y (up = positive) and accounts for depth (z).
        //   Positive = right shoulder higher; negative = left shoulder higher.
        // 2D fallback: screen-space atan2 (y-down), sign convention flipped for label consistency.
        let shoulderTiltDeg: Float
        let using3D: Bool
        if let wl = wLeftShoulder, let wr = wRightShoulder {
            let dy = wr.y - wl.y
            let horizontalDist = sqrt(pow(wr.x - wl.x, 2) + pow(wr.z - wl.z, 2))
            shoulderTiltDeg = atan2(dy, horizontalDist) * (180.0 / .pi)
            using3D = true
        } else {
            // Screen-space fallback: positive = left elevated (y-down coords)
            shoulderTiltDeg = -(atan2(rightShoulder.y - leftShoulder.y,
                                      rightShoulder.x - leftShoulder.x) * (180.0 / .pi))
            using3D = false
        }

        // Hip tilt for baseline reference (same 3D/2D logic)
        let hipTiltDeg: Float
        if let wl = wLeftHip, let wr = wRightHip {
            let dy = wr.y - wl.y
            let horizontalDist = sqrt(pow(wr.x - wl.x, 2) + pow(wr.z - wl.z, 2))
            hipTiltDeg = atan2(dy, horizontalDist) * (180.0 / .pi)
        } else {
            hipTiltDeg = -(atan2(rightHip.y - leftHip.y,
                                  rightHip.x - leftHip.x) * (180.0 / .pi))
        }

        let shoulderMid = (leftShoulder + rightShoulder) / 2.0
        let hipMid      = (leftHip + rightHip) / 2.0

        var instructions: [OverlayInstruction] = []

        // Horizontal reference line through shoulder midpoint
        let refLeft  = SIMD2<Float>(shoulderMid.x - 0.18, shoulderMid.y)
        let refRight = SIMD2<Float>(shoulderMid.x + 0.18, shoulderMid.y)
        instructions.append(.line(from: refLeft, to: refRight, color: .white, width: 1))

        // Pelvis / hip level line (reference baseline)
        instructions.append(.line(from: leftHip, to: rightHip, color: .cyan, width: 2))

        // Spine reference line (shoulder midpoint → hip midpoint)
        instructions.append(.line(from: shoulderMid, to: hipMid, color: .green, width: 2))

        // Shoulder girdle line (primary measurement)
        instructions.append(.line(from: leftShoulder, to: rightShoulder, color: .yellow, width: 4))

        // Joint circles — left shoulder red, right shoulder blue, hips orange
        instructions.append(.circle(at: leftShoulder,  radius: 12, color: .red,    filled: true))
        instructions.append(.circle(at: rightShoulder, radius: 12, color: .blue,   filled: true))
        instructions.append(.circle(at: leftHip,       radius: 8,  color: .orange, filled: true))
        instructions.append(.circle(at: rightHip,      radius: 8,  color: .orange, filled: true))

        // Side labels
        instructions.append(.text("L", at: SIMD2(leftShoulder.x  - 0.05, leftShoulder.y  - 0.05), color: .red,  size: 20))
        instructions.append(.text("R", at: SIMD2(rightShoulder.x + 0.02, rightShoulder.y - 0.05), color: .blue, size: 20))

        // HUD — which side is elevated and by how much
        // Positive = right elevated (both 3D and normalised-2D fallback share this convention now)
        let absTilt = abs(shoulderTiltDeg)
        let elevatedSide = shoulderTiltDeg >= 0 ? "R elevated" : "L elevated"
        let modeTag = using3D ? "" : " (2D)"
        instructions.append(.text("\(elevatedSide)  \(String(format: "%.1f", absTilt))\u{00B0}\(modeTag)",
                                  at: SIMD2(0.02, 0.05), color: .white, size: 22))
        instructions.append(.text("Hip ref: \(String(format: "%.1f", hipTiltDeg))\u{00B0}",
                                  at: SIMD2(0.02, 0.11), color: .cyan,  size: 18))

        return FrameAnalysis(
            angles: [JointAngle(joint: .shoulder, degrees: shoulderTiltDeg)],
            repCount: 0,
            repState: .extended,
            tempoPhase: nil,
            overlayInstructions: instructions
        )
    }

    func reset() {
        smoother.reset()
    }
}
