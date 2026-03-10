import AVFoundation
import CoreVideo
import os.log

private let logger = Logger(subsystem: "com.kevinjones.KevLines2-0", category: "VideoReader")

/// Hardware-accelerated video frame reader using AVAssetReader.
/// Replaces cv2.VideoCapture with VideoToolbox-backed decoding.
final class VideoReader {

    /// Native pixel dimensions (before any rotation transform).
    let nativeWidth: Int
    let nativeHeight: Int

    /// Display dimensions (after applying preferredTransform).
    let displayWidth: Int
    let displayHeight: Int

    let fps: Float
    let duration: CMTime
    let estimatedFrameCount: Int

    /// The track's preferred transform (rotation metadata from the camera).
    let preferredTransform: CGAffineTransform

    private let reader: AVAssetReader
    private let output: AVAssetReaderTrackOutput
    private(set) var currentTime: CMTime = .zero
    private var frameIndex: Int = 0

    /// Retains the current sample buffer so the pixel buffer stays valid
    /// until the next call to nextFrame().
    private var retainedSampleBuffer: CMSampleBuffer?

    init(url: URL) throws {
        let asset = AVURLAsset(url: url, options: [
            AVURLAssetPreferPreciseDurationAndTimingKey: true
        ])

        guard let track = asset.tracks(withMediaType: .video).first else {
            throw VideoReaderError.noVideoTrack
        }

        let nativeSize = track.naturalSize
        nativeWidth = Int(nativeSize.width)
        nativeHeight = Int(nativeSize.height)

        let displaySize = nativeSize.applying(track.preferredTransform)
        displayWidth = Int(abs(displaySize.width))
        displayHeight = Int(abs(displaySize.height))

        preferredTransform = track.preferredTransform
        fps = track.nominalFrameRate
        duration = asset.duration
        estimatedFrameCount = Int(Float(CMTimeGetSeconds(duration)) * fps)

        logger.info("Video: \(self.nativeWidth)x\(self.nativeHeight) native, \(self.displayWidth)x\(self.displayHeight) display, \(self.fps) fps, \(CMTimeGetSeconds(self.duration))s, ~\(self.estimatedFrameCount) frames")

        reader = try AVAssetReader(asset: asset)

        output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ])
        output.alwaysCopiesSampleData = true

        reader.add(output)
        reader.startReading()
    }

    /// Pull the next decoded frame. Returns nil at end of video or on error.
    /// The returned pixel buffer stays valid until the next call to nextFrame().
    func nextFrame() -> (pixelBuffer: CVPixelBuffer, time: CMTime)? {
        guard reader.status == .reading else {
            if reader.status == .failed {
                logger.error("AVAssetReader failed at frame \(self.frameIndex): \(self.reader.error?.localizedDescription ?? "unknown")")
            } else {
                logger.info("Reader status \(String(describing: self.reader.status)) at frame \(self.frameIndex)")
            }
            return nil
        }

        guard let sampleBuffer = output.copyNextSampleBuffer() else {
            if reader.status == .failed {
                logger.error("Reader failed after \(self.frameIndex) frames: \(self.reader.error?.localizedDescription ?? "unknown")")
            } else {
                logger.info("Finished reading: \(self.frameIndex) frames")
            }
            return nil
        }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            logger.warning("Frame \(self.frameIndex): no image buffer in sample")
            return nil
        }

        retainedSampleBuffer = sampleBuffer

        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        currentTime = pts
        frameIndex += 1
        return (pixelBuffer, pts)
    }

    var progress: Float {
        guard estimatedFrameCount > 0 else { return 0 }
        return Float(frameIndex) / Float(estimatedFrameCount)
    }

    enum VideoReaderError: Error, LocalizedError {
        case noVideoTrack

        var errorDescription: String? {
            switch self {
            case .noVideoTrack: return "No video track found in asset."
            }
        }
    }
}
