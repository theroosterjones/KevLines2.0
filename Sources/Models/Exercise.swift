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
        case .deadlift:           return DeadliftAnalyzer(side: side)
        case .lunge:              return LungeAnalyzer(side: side)
        case .hipHingeSide:       return HipHingeSideAnalyzer(side: side)
        case .hipHingeBack:       return HipHingeBackAnalyzer(side: side)
        case .row:                return RowAnalyzer(side: side)
        case .latPulldown:        return LatPulldownAnalyzer(side: side)
        case .overheadPress:      return OverheadPressAnalyzer(side: side)
        case .elbowCurl:          return ElbowAnalyzer(side: side)
        case .shoulderAssessment: return ShoulderAnalyzer(side: side)
        }
    }

    static let all: [ExerciseConfig] = [
        ExerciseConfig(type: .squat,              displayName: "Squat",
                       requiresSideSelection: true,  defaultSide: .left),
        ExerciseConfig(type: .deadlift,           displayName: "Deadlift",
                       requiresSideSelection: true,  defaultSide: .left),
        ExerciseConfig(type: .lunge,              displayName: "Lunge",
                       requiresSideSelection: true,  defaultSide: .left),
        ExerciseConfig(type: .hipHingeSide,       displayName: "Hip Hinge (Side)",
                       requiresSideSelection: true,  defaultSide: .left),
        ExerciseConfig(type: .hipHingeBack,       displayName: "Hip Hinge (Back)",
                       requiresSideSelection: false, defaultSide: .left),
        ExerciseConfig(type: .row,                displayName: "Barbell Row",
                       requiresSideSelection: true,  defaultSide: .left),
        ExerciseConfig(type: .latPulldown,        displayName: "Lat Pulldown",
                       requiresSideSelection: true,  defaultSide: .left),
        ExerciseConfig(type: .overheadPress,      displayName: "Overhead Press",
                       requiresSideSelection: false, defaultSide: .left),
        ExerciseConfig(type: .elbowCurl,          displayName: "Elbow (Bicep/Tricep)",
                       requiresSideSelection: true,  defaultSide: .left),
        ExerciseConfig(type: .shoulderAssessment, displayName: "Shoulder Assessment",
                       requiresSideSelection: false, defaultSide: .left),
    ]
}

// MARK: - Camera Setup Guidance

extension ExerciseType {
    /// Short setup guidance shown before analysis starts.
    var cameraSetupTip: String {
        switch self {
        case .squat, .deadlift, .lunge, .hipHingeSide:
            return "Use a strict side profile (about 90°). Keep the full working side visible from shoulder to ankle."
        case .row, .latPulldown, .elbowCurl:
            return "Use a strict side profile (about 90°). Keep the full working side visible from shoulder to ankle."
        case .overheadPress:
            return "Use a front or back profile. Keep both arms and hips fully visible in frame throughout the lift."
        case .hipHingeBack:
            return "Film from directly behind. Keep both hips, knees, and ankles fully visible. Stand centred in frame."
        case .shoulderAssessment:
            return "Use a strict front or back profile. Keep both shoulders and both hips fully visible and level in frame."
        }
    }

    /// Non-blocking warning shown when pose tracking quality is persistently low.
    var lowTrackingWarning: String {
        switch self {
        case .squat, .deadlift, .lunge, .hipHingeSide:
            return "Tracking is unstable. Reposition camera to a strict side profile and keep your full body in frame."
        case .row, .latPulldown, .elbowCurl:
            return "Tracking is unstable. Reposition camera to a strict side profile and keep your full body in frame."
        case .overheadPress:
            return "Tracking is unstable. Use a front or back profile and ensure both arms stay within the camera frame."
        case .hipHingeBack:
            return "Tracking is unstable. Film from directly behind with hips, knees, and ankles all visible."
        case .shoulderAssessment:
            return "Tracking is unstable. Use a strict front/back profile with both shoulders and hips clearly visible."
        }
    }
}
