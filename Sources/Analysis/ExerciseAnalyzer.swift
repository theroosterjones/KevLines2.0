import Foundation
import simd

// MARK: - Exercise Types

enum ExerciseType: String, CaseIterable, Identifiable, Codable {
    case squat = "Squat"
    case deadlift = "Deadlift"
    case lunge = "Lunge"
    case hipHingeSide = "Hip Hinge (Side)"
    case hipHingeBack = "Hip Hinge (Back)"
    case row = "Row"
    case latPulldown = "Lat Pulldown"
    case overheadPress = "Overhead Press"
    case elbowCurl = "Elbow (Bicep/Tricep)"
    case shoulderAssessment = "Shoulder Assessment"

    var id: String { rawValue }
}

// MARK: - Rep State

enum RepState: String {
    case extended
    case flexed
}

// MARK: - Tempo Phase

enum TempoPhase: String, Codable {
    case eccentric    // lowering / lengthening
    case pauseBottom  // hold at bottom
    case concentric   // lifting / shortening
    case pauseTop     // hold at top
}

// MARK: - Joint Angle

enum JointType: String, Codable {
    case knee, hip, elbow, shoulder, spine
}

struct JointAngle: Codable {
    let joint: JointType
    let degrees: Float
}

// MARK: - Overlay Instructions

enum OverlayInstruction {
    case line(from: SIMD2<Float>, to: SIMD2<Float>, color: OverlayColor, width: Float)
    case extendedLine(from: SIMD2<Float>, through: SIMD2<Float>, color: OverlayColor, width: Float)
    case circle(at: SIMD2<Float>, radius: Float, color: OverlayColor, filled: Bool)
    case text(String, at: SIMD2<Float>, color: OverlayColor, size: Float)
}

enum OverlayColor {
    case white, red, green, blue, yellow, cyan, magenta, orange

    var rgba: (Float, Float, Float, Float) {
        switch self {
        case .white:   return (1, 1, 1, 1)
        case .red:     return (1, 0, 0, 1)
        case .green:   return (0, 1, 0, 1)
        case .blue:    return (0, 0, 1, 1)
        case .yellow:  return (1, 1, 0, 1)
        case .cyan:    return (0, 1, 1, 1)
        case .magenta: return (1, 0, 1, 1)
        case .orange:  return (1, 0.65, 0, 1)
        }
    }
}

// MARK: - Frame Analysis Result

struct FrameAnalysis {
    let angles: [JointAngle]
    let repCount: Int
    let repState: RepState
    let tempoPhase: TempoPhase?
    let overlayInstructions: [OverlayInstruction]

    static let empty = FrameAnalysis(
        angles: [],
        repCount: 0,
        repState: .extended,
        tempoPhase: nil,
        overlayInstructions: []
    )
}

// MARK: - Analysis Summary (per-video)

struct AnalysisSummary {
    let totalReps: Int
    let averageAngles: [JointAngle]
    let duration: Double
    let tempoBreakdown: [TempoPhase: Double]  // seconds spent in each phase

    init(from frames: [FrameAnalysis], duration: Double) {
        totalReps = frames.last?.repCount ?? 0
        self.duration = duration

        // Average each joint angle across all frames that have it
        var angleSums: [JointType: (sum: Float, count: Int)] = [:]
        for frame in frames {
            for angle in frame.angles {
                let existing = angleSums[angle.joint, default: (0, 0)]
                angleSums[angle.joint] = (existing.sum + angle.degrees, existing.count + 1)
            }
        }
        averageAngles = angleSums.map { JointAngle(joint: $0.key, degrees: $0.value.sum / Float($0.value.count)) }

        // Approximate tempo breakdown (frames per phase × frame duration)
        let frameDuration = frames.isEmpty ? 0 : duration / Double(frames.count)
        var breakdown: [TempoPhase: Double] = [:]
        for frame in frames {
            if let phase = frame.tempoPhase {
                breakdown[phase, default: 0] += frameDuration
            }
        }
        tempoBreakdown = breakdown
    }
}

// MARK: - Analyzer Protocol

protocol ExerciseAnalyzer: AnyObject {
    var exerciseType: ExerciseType { get }
    var side: BodySide { get }
    var requiredLandmarks: [PoseLandmarkType] { get }

    func analyze(landmarks: PoseResult) -> FrameAnalysis
    func reset()
}
