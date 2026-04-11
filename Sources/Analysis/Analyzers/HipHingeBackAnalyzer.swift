import Foundation
import simd

/// Bilateral hip hinge assessment filmed from behind.
/// No rep counting — evaluates left/right symmetry of the hip hinge:
///   • Hip tilt (lateral pelvic shift / drop)
///   • Shoulder tilt (upper-body lateral lean)
///   • Knee tracking symmetry (inward vs outward collapse)
/// Useful for RDL, KB deadlift, and hinge-pattern screening.
final class HipHingeBackAnalyzer: ExerciseAnalyzer {

    let exerciseType: ExerciseType = .hipHingeBack
    let side: BodySide = .left  // bilateral — side parameter unused

    var requiredLandmarks: [PoseLandmarkType] {
        [
            .shoulder(.left), .shoulder(.right),
            .hip(.left),      .hip(.right),
            .knee(.left),     .knee(.right),
            .ankle(.left),    .ankle(.right)
        ]
    }

    private let smoother = LandmarkSmoother()

    init(side: BodySide) {
        // side ignored
    }

    func analyze(landmarks: PoseResult) -> FrameAnalysis {
        guard let rawLS = landmarks.position(for: .shoulder(.left)),
              let rawRS = landmarks.position(for: .shoulder(.right)),
              let rawLH = landmarks.position(for: .hip(.left)),
              let rawRH = landmarks.position(for: .hip(.right)),
              let rawLK = landmarks.position(for: .knee(.left)),
              let rawRK = landmarks.position(for: .knee(.right)),
              let rawLA = landmarks.position(for: .ankle(.left)),
              let rawRA = landmarks.position(for: .ankle(.right)) else {
            return .empty
        }

        let ts = landmarks.timestamp
        let lShoulder = smoother.smooth(key: "left_shoulder",  position: rawLS, timestamp: ts)
        let rShoulder = smoother.smooth(key: "right_shoulder", position: rawRS, timestamp: ts)
        let lHip      = smoother.smooth(key: "left_hip",       position: rawLH, timestamp: ts)
        let rHip      = smoother.smooth(key: "right_hip",      position: rawRH, timestamp: ts)
        let lKnee     = smoother.smooth(key: "left_knee",      position: rawLK, timestamp: ts)
        let rKnee     = smoother.smooth(key: "right_knee",     position: rawRK, timestamp: ts)
        let lAnkle    = smoother.smooth(key: "left_ankle",     position: rawLA, timestamp: ts)
        let rAnkle    = smoother.smooth(key: "right_ankle",    position: rawRA, timestamp: ts)

        let wLS = landmarks.worldPosition(for: .shoulder(.left)) .map { smoother.smooth3D(key: "left_shoulder",  position: $0, timestamp: ts) }
        let wRS = landmarks.worldPosition(for: .shoulder(.right)).map { smoother.smooth3D(key: "right_shoulder", position: $0, timestamp: ts) }
        let wLH = landmarks.worldPosition(for: .hip(.left))      .map { smoother.smooth3D(key: "left_hip",       position: $0, timestamp: ts) }
        let wRH = landmarks.worldPosition(for: .hip(.right))     .map { smoother.smooth3D(key: "right_hip",      position: $0, timestamp: ts) }

        // Hip tilt (lateral pelvic shift in the frontal plane)
        let hipTiltDeg: Float
        if let wl = wLH, let wr = wRH {
            let dy = wr.y - wl.y
            let hDist = sqrt(pow(wr.x - wl.x, 2) + pow(wr.z - wl.z, 2))
            hipTiltDeg = atan2(dy, hDist) * (180.0 / .pi)
        } else {
            hipTiltDeg = -(atan2(rHip.y - lHip.y, rHip.x - lHip.x) * (180.0 / .pi))
        }

        // Shoulder tilt — upper-body lateral lean
        let shoulderTiltDeg: Float
        if let wl = wLS, let wr = wRS {
            let dy = wr.y - wl.y
            let hDist = sqrt(pow(wr.x - wl.x, 2) + pow(wr.z - wl.z, 2))
            shoulderTiltDeg = atan2(dy, hDist) * (180.0 / .pi)
        } else {
            shoulderTiltDeg = -(atan2(rShoulder.y - lShoulder.y,
                                      rShoulder.x - lShoulder.x) * (180.0 / .pi))
        }

        // Knee tracking: compare each knee's x offset relative to its hip and ankle midpoint.
        // Negative = knee caves inward (valgus); positive = knee flares outward (varus).
        func kneeOffset(hip: SIMD2<Float>, knee: SIMD2<Float>, ankle: SIMD2<Float>) -> Float {
            let mid = (hip + ankle) / 2.0
            return (knee.x - mid.x)
        }
        let lKneeOff = kneeOffset(hip: lHip, knee: lKnee, ankle: lAnkle)
        let rKneeOff = kneeOffset(hip: rHip, knee: rKnee, ankle: rAnkle)

        // Normalise by hip width so the metric is scale-independent (as % of hip width)
        let hipWidth = abs(rHip.x - lHip.x)
        let lKneePct = hipWidth > 1e-4 ? (lKneeOff / hipWidth) * 100.0 : 0
        let rKneePct = hipWidth > 1e-4 ? (rKneeOff / hipWidth) * 100.0 : 0

        let shoulderMid = (lShoulder + rShoulder) / 2.0
        let hipMid      = (lHip + rHip) / 2.0

        var instructions: [OverlayInstruction] = []

        // Horizontal reference through hip midpoint
        let refLeft  = SIMD2<Float>(hipMid.x - 0.18, hipMid.y)
        let refRight = SIMD2<Float>(hipMid.x + 0.18, hipMid.y)
        instructions.append(.line(from: refLeft, to: refRight, color: .white, width: 1))

        // Shoulder girdle
        instructions.append(.line(from: lShoulder, to: rShoulder, color: .yellow, width: 4))

        // Spine reference
        instructions.append(.line(from: shoulderMid, to: hipMid, color: .green, width: 2))

        // Hip level line (primary tilt assessment)
        instructions.append(.line(from: lHip, to: rHip, color: .cyan, width: 4))

        // Leg lines
        instructions.append(.line(from: lHip,  to: lKnee,  color: .green, width: 3))
        instructions.append(.line(from: lKnee, to: lAnkle, color: .green, width: 3))
        instructions.append(.line(from: rHip,  to: rKnee,  color: .green, width: 3))
        instructions.append(.line(from: rKnee, to: rAnkle, color: .green, width: 3))

        // Knee tracking guide lines (hip→ankle plumb)
        instructions.append(.line(from: lHip, to: lAnkle, color: .magenta, width: 1))
        instructions.append(.line(from: rHip, to: rAnkle, color: .magenta, width: 1))

        // Joint circles
        instructions.append(.circle(at: lShoulder, radius: 10, color: .red,    filled: true))
        instructions.append(.circle(at: rShoulder, radius: 10, color: .blue,   filled: true))
        instructions.append(.circle(at: lHip,      radius: 12, color: .cyan,   filled: true))
        instructions.append(.circle(at: rHip,      radius: 12, color: .cyan,   filled: true))
        instructions.append(.circle(at: lKnee,     radius: 10, color: .yellow, filled: true))
        instructions.append(.circle(at: rKnee,     radius: 10, color: .yellow, filled: true))
        instructions.append(.circle(at: lAnkle,    radius: 8,  color: .orange, filled: true))
        instructions.append(.circle(at: rAnkle,    radius: 8,  color: .orange, filled: true))

        // Side labels
        instructions.append(.text("L", at: SIMD2(lShoulder.x - 0.05, lShoulder.y - 0.05), color: .red,  size: 20))
        instructions.append(.text("R", at: SIMD2(rShoulder.x + 0.02, rShoulder.y - 0.05), color: .blue, size: 20))

        // HUD
        let hipElevated   = hipTiltDeg >= 0 ? "R hip high" : "L hip high"
        let shoulderNote  = shoulderTiltDeg >= 0 ? "R shoulder high" : "L shoulder high"
        instructions.append(.text("Hip: \(hipElevated)  \(String(format: "%.1f", abs(hipTiltDeg)))\u{00B0}",
            at: SIMD2(0.02, 0.05), color: .white,   size: 20))
        instructions.append(.text("Shoulder: \(String(format: "%.1f", abs(shoulderTiltDeg)))\u{00B0}  \(shoulderNote)",
            at: SIMD2(0.02, 0.11), color: .yellow,  size: 18))

        let lKneeTag  = lKneePct < -8 ? "valgus" : (lKneePct > 8 ? "varus" : "OK")
        let rKneeTag  = rKneePct < -8 ? "valgus" : (rKneePct > 8 ? "varus" : "OK")
        instructions.append(.text("L knee: \(lKneeTag)   R knee: \(rKneeTag)",
            at: SIMD2(0.02, 0.17), color: .cyan, size: 18))

        return FrameAnalysis(
            angles: [JointAngle(joint: .hip, degrees: hipTiltDeg)],
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
