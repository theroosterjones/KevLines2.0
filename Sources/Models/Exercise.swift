import Foundation

/// Configuration for each exercise type, centralizing thresholds and landmark requirements.
struct ExerciseConfig {
    let type: ExerciseType
    let displayName: String
    let requiresSideSelection: Bool
    let defaultSide: BodySide

    /// Create the appropriate analyzer for this exercise.
    func makeAnalyzer(side: BodySide) -> ExerciseAnalyzer {
        switch type {
        case .squat:              return SquatAnalyzer(side: side)
        case .row:                return RowAnalyzer(side: side)
        case .latPulldown:        return LatPulldownAnalyzer(side: side)
        case .elbowCurl:          return ElbowAnalyzer(side: side)
        case .shoulderAssessment: return ShoulderAnalyzer(side: side)
        }
    }

    static let all: [ExerciseConfig] = [
        ExerciseConfig(type: .squat, displayName: "Squat",
                       requiresSideSelection: true, defaultSide: .left),
        ExerciseConfig(type: .row, displayName: "Barbell Row",
                       requiresSideSelection: true, defaultSide: .left),
        ExerciseConfig(type: .latPulldown, displayName: "Lat Pulldown",
                       requiresSideSelection: true, defaultSide: .left),
        ExerciseConfig(type: .elbowCurl, displayName: "Elbow (Bicep/Tricep)",
                       requiresSideSelection: true, defaultSide: .left),
        ExerciseConfig(type: .shoulderAssessment, displayName: "Shoulder Assessment",
                       requiresSideSelection: false, defaultSide: .left),
    ]
}

// MARK: - Camera Setup Guidance

extension ExerciseType {
    /// Short setup guidance shown before analysis starts.
    var cameraSetupTip: String {
        switch self {
        case .squat, .row, .latPulldown, .elbowCurl:
            return "Use a strict side profile (about 90 deg). Keep the full working side visible from shoulder to ankle."
        case .shoulderAssessment:
            return "Use a strict front or back profile. Keep both shoulders and both hips fully visible and level in frame."
        }
    }

    /// Non-blocking warning shown when pose tracking quality is persistently low.
    var lowTrackingWarning: String {
        switch self {
        case .squat, .row, .latPulldown, .elbowCurl:
            return "Tracking is unstable. Reposition camera to a strict side profile and keep your full body in frame."
        case .shoulderAssessment:
            return "Tracking is unstable. Use a strict front/back profile with both shoulders and hips clearly visible."
        }
    }
}
