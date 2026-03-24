import AVFoundation
import UIKit
import MediaPipeTasksVision
import os.log

private let logger = Logger(subsystem: "com.kevinjones.KevLines2-0", category: "PoseLandmarker")

/// Wraps the MediaPipe Pose Landmarker iOS SDK.
/// Call `detect(pixelBuffer:timestampMs:)` for each video frame.
final class PoseLandmarkerService {

    enum ModelType: String {
        case lite = "pose_landmarker_lite"
        case full = "pose_landmarker_full"
        case heavy = "pose_landmarker_heavy"
    }

    private let modelType: ModelType
    private var poseLandmarker: PoseLandmarker?

    init(modelType: ModelType = .full) {
        self.modelType = modelType
        setupLandmarker()
    }

    // MARK: - Setup

    private func setupLandmarker() {
        guard let modelPath = Bundle.main.path(
            forResource: modelType.rawValue,
            ofType: "task"
        ) else {
            logger.error("Missing \(self.modelType.rawValue).task in app bundle")
            return
        }

        logger.info("Found model at: \(modelPath)")

        let options = PoseLandmarkerOptions()
        options.baseOptions.modelAssetPath = modelPath
        options.runningMode = .video
        options.minPoseDetectionConfidence = 0.5
        options.minTrackingConfidence = 0.5
        options.numPoses = 1

        do {
            poseLandmarker = try PoseLandmarker(options: options)
            logger.info("PoseLandmarker initialized successfully")
        } catch {
            logger.error("Failed to create PoseLandmarker: \(error.localizedDescription)")
        }
    }

    // MARK: - Detection

    /// Run pose detection on a single video frame.
    func detect(pixelBuffer: CVPixelBuffer, timestampMs: Int) -> PoseResult? {
        guard let poseLandmarker else {
            logger.warning("PoseLandmarker is nil — model failed to load")
            return nil
        }

        let mpImage: MPImage
        do {
            mpImage = try MPImage(pixelBuffer: pixelBuffer)
        } catch {
            logger.error("MPImage creation failed: \(error.localizedDescription)")
            return nil
        }

        let result: PoseLandmarkerResult
        do {
            result = try poseLandmarker.detect(videoFrame: mpImage, timestampInMilliseconds: timestampMs)
        } catch {
            logger.error("Pose detection failed at \(timestampMs)ms: \(error.localizedDescription)")
            return nil
        }

        guard let poseLandmarks = result.landmarks.first else { return nil }

        // 2D normalized landmarks (for overlay drawing)
        var landmarks: [PoseLandmarkType: NormalizedLandmark] = [:]
        for (index, lm) in poseLandmarks.enumerated() {
            guard let type = PoseLandmarkType(rawValue: index) else { continue }
            landmarks[type] = NormalizedLandmark(
                position: SIMD2<Float>(lm.x, lm.y),
                z: lm.z,
                visibility: lm.visibility?.floatValue ?? 0
            )
        }

        // 3D world landmarks in metric space (for accurate angle calculations)
        var worldLandmarks: [PoseLandmarkType: SIMD3<Float>] = [:]
        if let worldList = result.worldLandmarks.first {
            for (index, wlm) in worldList.enumerated() {
                guard let type = PoseLandmarkType(rawValue: index) else { continue }
                worldLandmarks[type] = SIMD3<Float>(wlm.x, wlm.y, wlm.z)
            }
        }

        return PoseResult(
            landmarks: landmarks,
            worldLandmarks: worldLandmarks,
            timestamp: Double(timestampMs) / 1000.0
        )
    }
}
