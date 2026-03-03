import AVFoundation
import CoreVideo

/// Orchestrates the full local pipeline: read → pose → analyze → overlay → write.
/// This replaces the entire upload → cloud process → download flow from 1.x.
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

    /// Process a video file locally. All work runs on a background thread.
    /// - Parameters:
    ///   - inputURL: Source video file URL.
    ///   - outputURL: Destination for the analyzed video with overlays.
    ///   - analyzer: The exercise-specific analyzer to use.
    /// - Returns: The final analysis summary (total reps, form score, etc.).
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
            width: reader.width,
            height: reader.height,
            fps: reader.fps
        )

        analyzer.reset()
        var allFrameResults: [FrameAnalysis] = []

        while let (pixelBuffer, time) = reader.nextFrame() {
            let timestampMs = Int(CMTimeGetSeconds(time) * 1000)

            // 1. Pose estimation (GPU-accelerated via MediaPipe)
            let poseResult = poseLandmarker.detect(
                pixelBuffer: pixelBuffer,
                timestampMs: timestampMs
            )

            // 2. Exercise analysis (pure math, microseconds)
            var frameResult: FrameAnalysis
            if let poseResult {
                frameResult = analyzer.analyze(landmarks: poseResult)
            } else {
                frameResult = FrameAnalysis.empty
            }
            allFrameResults.append(frameResult)

            // 3. Render overlays onto the pixel buffer
            overlayRenderer.render(
                instructions: frameResult.overlayInstructions,
                onto: pixelBuffer
            )

            // 4. Write processed frame
            writer.append(pixelBuffer: pixelBuffer, at: time)

            // 5. Update progress
            let currentProgress = reader.progress
            await MainActor.run {
                progress = currentProgress
            }
        }

        try await writer.finalize()

        await MainActor.run {
            progress = 1.0
        }

        return AnalysisSummary(from: allFrameResults, duration: CMTimeGetSeconds(reader.duration))
    }
}
