import AVFoundation
import UIKit

// TODO: Import MediaPipeTasksVision once the SPM package is added to the Xcode project.
// import MediaPipeTasksVision

/// Wraps the MediaPipe Pose Landmarker iOS SDK.
/// Call `detect(pixelBuffer:timestampMs:)` for each video frame.
final class PoseLandmarkerService {

    enum ModelType: String {
        case lite = "pose_landmarker_lite"
        case full = "pose_landmarker_full"
        case heavy = "pose_landmarker_heavy"
    }

    private let modelType: ModelType
    // private var poseLandmarker: PoseLandmarker?

    init(modelType: ModelType = .full) {
        self.modelType = modelType
        setupLandmarker()
    }

    // MARK: - Setup

    private func setupLandmarker() {
        // TODO: Uncomment once MediaPipeTasksVision is linked.
        //
        // guard let modelPath = Bundle.main.path(
        //     forResource: modelType.rawValue,
        //     ofType: "task"
        // ) else {
        //     fatalError("Missing \(modelType.rawValue).task in bundle. Download from: "
        //         + "https://storage.googleapis.com/mediapipe-models/pose_landmarker/"
        //         + "\(modelType.rawValue)/float16/latest/\(modelType.rawValue).task")
        // }
        //
        // let options = PoseLandmarkerOptions()
        // options.baseOptions.modelAssetPath = modelPath
        // options.runningMode = .video
        // options.minPoseDetectionConfidence = 0.5
        // options.minTrackingConfidence = 0.5
        // options.numPoses = 1
        //
        // poseLandmarker = try? PoseLandmarker(options: options)
    }

    // MARK: - Detection

    /// Run pose detection on a single video frame.
    /// - Parameters:
    ///   - pixelBuffer: The CVPixelBuffer from AVAssetReader or AVCaptureSession.
    ///   - timestampMs: Frame timestamp in milliseconds (required for .video running mode).
    /// - Returns: A `PoseResult` with all detected landmarks, or `nil` if detection failed.
    func detect(pixelBuffer: CVPixelBuffer, timestampMs: Int) -> PoseResult? {
        // TODO: Uncomment once MediaPipeTasksVision is linked.
        //
        // let mpImage = try? MPImage(pixelBuffer: pixelBuffer)
        // guard let mpImage else { return nil }
        //
        // let result = try? poseLandmarker?.detect(videoFrame: mpImage, timestampInMilliseconds: timestampMs)
        // guard let poseLandmarks = result?.landmarks.first else { return nil }
        //
        // var landmarks: [PoseLandmarkType: NormalizedLandmark] = [:]
        // for (index, lm) in poseLandmarks.enumerated() {
        //     guard let type = PoseLandmarkType(rawValue: index) else { continue }
        //     landmarks[type] = NormalizedLandmark(
        //         position: SIMD2<Float>(lm.x, lm.y),
        //         z: lm.z,
        //         visibility: lm.visibility?.floatValue ?? 0
        //     )
        // }
        //
        // return PoseResult(
        //     landmarks: landmarks,
        //     timestamp: Double(timestampMs) / 1000.0
        // )

        return nil  // placeholder
    }
}
