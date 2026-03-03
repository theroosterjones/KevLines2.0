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
        case .row:         return RowAnalyzer(side: side)
        case .backSquat:   return BackSquatAnalyzer(side: side)
        case .hackSquat:   return HackSquatAnalyzer(side: side)
        case .latPulldown: return LatPulldownAnalyzer(side: side)
        case .squat:       return SquatAnalyzer(side: side)
        }
    }

    static let all: [ExerciseConfig] = [
        ExerciseConfig(type: .row, displayName: "Barbell Row",
                       requiresSideSelection: true, defaultSide: .left),
        ExerciseConfig(type: .backSquat, displayName: "Back Squat",
                       requiresSideSelection: true, defaultSide: .left),
        ExerciseConfig(type: .hackSquat, displayName: "Hack Squat",
                       requiresSideSelection: true, defaultSide: .left),
        ExerciseConfig(type: .latPulldown, displayName: "Lat Pulldown",
                       requiresSideSelection: true, defaultSide: .left),
        ExerciseConfig(type: .squat, displayName: "Squat",
                       requiresSideSelection: true, defaultSide: .left),
    ]
}
