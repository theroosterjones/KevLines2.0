import Foundation
import simd

// MARK: - Assessment Types

enum AssessmentType: String, CaseIterable, Identifiable, Codable {
    case shoulderFlexion    = "Shoulder Flexion"
    case squatAssessment    = "Squat Assessment"
    case hipHingeAssessment = "Hip Hinge Assessment"

    var id: String { rawValue }
}

// MARK: - Letter Grade

enum LetterGrade: String, Codable, Comparable, CaseIterable {
    case A, B, C, D, F

    static func < (lhs: LetterGrade, rhs: LetterGrade) -> Bool {
        let order: [LetterGrade] = [.A, .B, .C, .D, .F]
        guard let li = order.firstIndex(of: lhs),
              let ri = order.firstIndex(of: rhs) else { return false }
        return li < ri
    }

    /// Grade a value where lower is better (e.g. knee angle for squat depth).
    /// Thresholds are inclusive upper bounds for each grade: A <= t0, B <= t1, etc.
    static func gradeLowerIsBetter(value: Float, a: Float, b: Float, c: Float, d: Float) -> LetterGrade {
        if value <= a { return .A }
        if value <= b { return .B }
        if value <= c { return .C }
        if value <= d { return .D }
        return .F
    }

    /// Grade a value where higher is better (e.g. ROM).
    /// Thresholds are inclusive lower bounds for each grade: A >= t0, B >= t1, etc.
    static func gradeHigherIsBetter(value: Float, a: Float, b: Float, c: Float, d: Float) -> LetterGrade {
        if value >= a { return .A }
        if value >= b { return .B }
        if value >= c { return .C }
        if value >= d { return .D }
        return .F
    }
}

// MARK: - Assessment Metrics

struct AssessmentMetrics {
    let grade: LetterGrade
    let subGrades: [(label: String, grade: LetterGrade)]
    let leftROM: Float?
    let rightROM: Float?
    let asymmetryDeg: Float?
    let asymmetryFlag: Bool
    let details: [String]
}

// MARK: - Assessment Analyzer Protocol

protocol AssessmentAnalyzer: FrameAnalyzerProtocol {
    var assessmentType: AssessmentType { get }
    func currentMetrics() -> AssessmentMetrics
}

// MARK: - Dynamic Color Helpers

extension OverlayColor {
    static func romQuality(grade: LetterGrade) -> OverlayColor {
        switch grade {
        case .A: return .green
        case .B: return .custom(r: 0.6, g: 1.0, b: 0.2, a: 1.0)
        case .C: return .yellow
        case .D: return .orange
        case .F: return .red
        }
    }
}

// MARK: - Assessment Camera Tips

extension AssessmentType {
    var cameraSetupTip: String {
        switch self {
        case .shoulderFlexion:
            return "Film from the side. Keep the full arm and torso visible. Raise both arms overhead slowly."
        case .squatAssessment:
            return "Film from behind. Keep both hips, knees, and ankles visible. Perform a slow bodyweight squat."
        case .hipHingeAssessment:
            return "Film from the side. Keep shoulder to ankle visible. Perform a slow hip hinge with straight arms."
        }
    }

    var lowTrackingWarning: String {
        switch self {
        case .shoulderFlexion:
            return "Tracking is unstable. Reposition to a side profile with full arm and torso visible."
        case .squatAssessment:
            return "Tracking is unstable. Film from behind with hips, knees, and ankles all visible."
        case .hipHingeAssessment:
            return "Tracking is unstable. Reposition to a strict side profile with full body visible."
        }
    }
}
