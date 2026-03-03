import AVFoundation
import CoreVideo

/// Hardware-accelerated video frame reader using AVAssetReader.
/// Replaces cv2.VideoCapture with VideoToolbox-backed decoding.
final class VideoReader {

    let width: Int
    let height: Int
    let fps: Float
    let duration: CMTime
    let estimatedFrameCount: Int

    private let reader: AVAssetReader
    private let output: AVAssetReaderTrackOutput
    private(set) var currentTime: CMTime = .zero
    private var frameIndex: Int = 0

    init(url: URL) throws {
        let asset = AVURLAsset(url: url, options: [
            AVURLAssetPreferPreciseDurationAndTimingKey: true
        ])

        guard let track = asset.tracks(withMediaType: .video).first else {
            throw VideoReaderError.noVideoTrack
        }

        let size = track.naturalSize.applying(track.preferredTransform)
        width = Int(abs(size.width))
        height = Int(abs(size.height))
        fps = track.nominalFrameRate
        duration = asset.duration
        estimatedFrameCount = Int(Float(CMTimeGetSeconds(duration)) * fps)

        reader = try AVAssetReader(asset: asset)

        output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ])
        output.alwaysCopiesSampleData = false

        reader.add(output)
        reader.startReading()
    }

    /// Pull the next decoded frame. Returns nil at end of video or on error.
    func nextFrame() -> (pixelBuffer: CVPixelBuffer, time: CMTime)? {
        guard reader.status == .reading,
              let sampleBuffer = output.copyNextSampleBuffer(),
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return nil
        }
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
