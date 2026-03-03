import AVFoundation
import CoreVideo

/// Hardware-accelerated video writer using AVAssetWriter.
/// Replaces cv2.VideoWriter + ffmpeg re-encode with a single VideoToolbox pass.
final class VideoWriter {

    private let writer: AVAssetWriter
    private let videoInput: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor

    init(outputURL: URL, width: Int, height: Int, fps: Float) throws {
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
    }

    /// Append a processed frame at the given presentation time.
    func append(pixelBuffer: CVPixelBuffer, at time: CMTime) {
        while !videoInput.isReadyForMoreMediaData {
            Thread.sleep(forTimeInterval: 0.01)
        }
        adaptor.append(pixelBuffer, withPresentationTime: time)
    }

    /// Finalize the video file. Must be called when all frames are written.
    func finalize() async throws {
        videoInput.markAsFinished()
        await writer.finishWriting()
        if let error = writer.error {
            throw error
        }
    }
}
