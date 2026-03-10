import AVFoundation
import CoreVideo
import os.log

private let logger = Logger(subsystem: "com.kevinjones.KevLines2-0", category: "VideoProcessor")

/// Orchestrates the full local pipeline: read -> pose -> analyze -> overlay -> write.
final class VideoProcessor: ObservableObject {

    @Published var progress: Float = 0
    @Published var isProcessing = false

    private let poseLandmarker: PoseLandmarkerService
    private let overlayRenderer: OverlayRenderer

    init(
        poseLandmarker: PoseLandmarkerService = PoseLandmarkerService(),
        overlayRenderer: OverlayRenderer = OverlayRenderer()
    ) {
        self.poseLandmarker = poseLandmarker
        self.overlayRenderer = overlayRenderer
    }

    func process(
        inputURL: URL,
        outputURL: URL,
        analyzer: ExerciseAnalyzer
    ) async throws -> AnalysisSummary {
        await MainActor.run {
            isProcessing = true
            progress = 0
        }

        defer {
            Task { @MainActor in
                isProcessing = false
            }
        }

        let reader = try VideoReader(url: inputURL)

        let writer = try VideoWriter(
            outputURL: outputURL,
            width: reader.nativeWidth,
            height: reader.nativeHeight,
            fps: reader.fps,
            transform: reader.preferredTransform
        )

        logger.info("Pipeline start: \(reader.nativeWidth)x\(reader.nativeHeight), ~\(reader.estimatedFrameCount) frames, \(CMTimeGetSeconds(reader.duration))s")

        analyzer.reset()

        let result: AnalysisSummary = try await Task.detached(priority: .userInitiated) {
            [poseLandmarker, overlayRenderer] in

            var allFrameResults: [FrameAnalysis] = []
            var poseDetections = 0
            var writeFailures = 0

            while let (pixelBuffer, time) = reader.nextFrame() {
                let timestampMs = Int(CMTimeGetSeconds(time) * 1000)

                let poseResult = poseLandmarker.detect(
                    pixelBuffer: pixelBuffer,
                    timestampMs: timestampMs
                )

                let frameResult: FrameAnalysis
                if let poseResult {
                    frameResult = analyzer.analyze(landmarks: poseResult)
                    poseDetections += 1
                } else {
                    frameResult = FrameAnalysis.empty
                }
                allFrameResults.append(frameResult)

                overlayRenderer.render(
                    instructions: frameResult.overlayInstructions,
                    onto: pixelBuffer
                )

                if !writer.append(pixelBuffer: pixelBuffer, at: time) {
                    writeFailures += 1
                    if writeFailures > 5 {
                        logger.error("Too many write failures, stopping pipeline")
                        break
                    }
                }

                if allFrameResults.count % 10 == 0 {
                    let p = reader.progress
                    await MainActor.run { [p] in
                        self.progress = p
                    }
                }
            }

            try await writer.finalize()

            let totalFrames = allFrameResults.count
            logger.info("Pipeline done: \(totalFrames) frames, \(poseDetections) detections (\(totalFrames > 0 ? Int(Float(poseDetections) / Float(totalFrames) * 100) : 0)%), \(writeFailures) write failures")

            await MainActor.run {
                self.progress = 1.0
            }

            return AnalysisSummary(from: allFrameResults, duration: CMTimeGetSeconds(reader.duration))
        }.value

        return result
    }
}
