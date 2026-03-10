import AVFoundation
import CoreVideo
import os.log

private let logger = Logger(subsystem: "com.kevinjones.KevLines2-0", category: "VideoWriter")

/// Hardware-accelerated video writer using AVAssetWriter.
/// Replaces cv2.VideoWriter + ffmpeg re-encode with a single VideoToolbox pass.
final class VideoWriter {

    private let writer: AVAssetWriter
    private let videoInput: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private var framesWritten: Int = 0

    init(outputURL: URL, width: Int, height: Int, fps: Float,
         transform: CGAffineTransform = .identity) throws {
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)

        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: width * height * 4,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoExpectedSourceFrameRateKey: fps
            ]
        ]

        videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        videoInput.expectsMediaDataInRealTime = false
        videoInput.transform = transform

        let sourceAttrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height
        ]

        adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: sourceAttrs
        )

        writer.add(videoInput)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        logger.info("Writer ready: \(width)x\(height) @ \(fps)fps")
    }

    /// Append a processed frame at the given presentation time.
    /// Returns false if the writer has entered an error state.
    @discardableResult
    func append(pixelBuffer: CVPixelBuffer, at time: CMTime) -> Bool {
        guard writer.status == .writing else {
            if framesWritten == 0 || framesWritten % 100 == 0 {
                logger.error("Writer not writing (status=\(self.writer.status.rawValue)) after \(self.framesWritten) frames: \(self.writer.error?.localizedDescription ?? "none")")
            }
            return false
        }

        var waitCount = 0
        while !videoInput.isReadyForMoreMediaData {
            Thread.sleep(forTimeInterval: 0.005)
            waitCount += 1
            if waitCount > 200 {
                logger.error("Writer timed out waiting for readiness at frame \(self.framesWritten)")
                return false
            }
        }

        let success = adaptor.append(pixelBuffer, withPresentationTime: time)
        if success {
            framesWritten += 1
        } else {
            logger.error("Append failed at frame \(self.framesWritten), time=\(CMTimeGetSeconds(time))s: \(self.writer.error?.localizedDescription ?? "unknown")")
        }
        return success
    }

    /// Finalize the video file. Must be called when all frames are written.
    func finalize() async throws {
        videoInput.markAsFinished()
        await writer.finishWriting()
        if let error = writer.error {
            logger.error("Finalize failed: \(error.localizedDescription)")
            throw error
        }
        logger.info("Finalized: \(self.framesWritten) frames written")
    }
}
