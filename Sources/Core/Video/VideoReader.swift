import AVFoundation
import CoreImage
import CoreVideo
import os.log

private let logger = Logger(subsystem: "com.kevinjones.KevLines2-0", category: "VideoReader")

/// Hardware-accelerated video frame reader using AVAssetReader.
///
/// iPhone-recorded videos store their pixel buffers in a fixed native orientation
/// (typically 1920×1080 landscape) and rely on a `preferredTransform` rotation tag
/// to display upright. MediaPipe's pose model, however, ignores container metadata
/// and operates directly on pixels — so feeding it the raw landscape buffer for a
/// portrait-recorded clip means the model sees a horizontal-lying human and very
/// often fails to detect a pose at all (returning zero overlays, reps, and tempo
/// downstream).
///
/// To avoid that, this reader bakes the `preferredTransform` into the pixel buffer
/// before returning it. Callers receive an upright buffer of size
/// `outputWidth × outputHeight` and can pair it with `outputTransform` (always
/// `.identity`) when configuring downstream writers.
final class VideoReader {

    /// Native pixel dimensions (before applying `preferredTransform`). Kept for
    /// debugging / logging; downstream code should use `outputWidth/Height`.
    let nativeWidth: Int
    let nativeHeight: Int

    /// Display dimensions (after applying `preferredTransform`).
    let displayWidth: Int
    let displayHeight: Int

    /// Dimensions of the pixel buffer returned by `nextFrame()`. After rotation
    /// these equal `displayWidth/displayHeight`.
    var outputWidth: Int { displayWidth }
    var outputHeight: Int { displayHeight }

    /// The transform downstream writers should apply. Always `.identity` because
    /// the rotation has already been baked into the pixel buffer.
    var outputTransform: CGAffineTransform { .identity }

    let fps: Float
    let duration: CMTime
    let estimatedFrameCount: Int

    /// The track's preferred transform (rotation metadata from the camera).
    /// Exposed for diagnostics; downstream writers should use `outputTransform`.
    let preferredTransform: CGAffineTransform

    private let reader: AVAssetReader
    private let output: AVAssetReaderTrackOutput
    private(set) var currentTime: CMTime = .zero
    private var frameIndex: Int = 0

    /// Retains the current sample buffer so the pixel buffer stays valid
    /// until the next call to nextFrame().
    private var retainedSampleBuffer: CMSampleBuffer?

    // Rotation pipeline. When `needsRotation` is false we pass through the
    // decoder's buffer unchanged; otherwise we render a rotated copy via
    // `ciContext` into buffers vended from `bufferPool`.
    private let needsRotation: Bool
    private let translationToOrigin: CGAffineTransform
    private let ciContext: CIContext
    private let bufferPool: CVPixelBufferPool?

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

        let transform = track.preferredTransform
        preferredTransform = transform

        let displaySize = nativeSize.applying(transform)
        displayWidth = Int(abs(displaySize.width))
        displayHeight = Int(abs(displaySize.height))

        fps = track.nominalFrameRate
        duration = asset.duration
        estimatedFrameCount = Int(Float(CMTimeGetSeconds(duration)) * fps)

        // A non-identity transform means the encoded pixels disagree with the
        // intended display orientation; we'll need to rotate every frame.
        needsRotation = !transform.isIdentity

        // After applying `transform` the resulting CIImage extent's origin can be
        // negative (e.g. y = -height for a 90° rotation); we translate it back
        // into the [0, displayWidth] × [0, displayHeight] range so the rendered
        // buffer is fully populated.
        let probeRect = CGRect(x: 0, y: 0, width: nativeSize.width, height: nativeSize.height)
            .applying(transform)
        translationToOrigin = CGAffineTransform(
            translationX: -probeRect.origin.x,
            y: -probeRect.origin.y
        )

        ciContext = CIContext(options: [.useSoftwareRenderer: false])

        if needsRotation {
            let attrs: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: displayWidth,
                kCVPixelBufferHeightKey as String: displayHeight,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any]
            ]
            var pool: CVPixelBufferPool?
            CVPixelBufferPoolCreate(nil, nil, attrs as CFDictionary, &pool)
            bufferPool = pool
            if pool == nil {
                logger.error("Failed to create rotation buffer pool (\(self.displayWidth)x\(self.displayHeight))")
            }
        } else {
            bufferPool = nil
        }

        logger.info("Video: \(self.nativeWidth)x\(self.nativeHeight) native, \(self.displayWidth)x\(self.displayHeight) display, rotated=\(self.needsRotation), \(self.fps) fps, \(CMTimeGetSeconds(self.duration))s, ~\(self.estimatedFrameCount) frames")

        reader = try AVAssetReader(asset: asset)

        output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ])
        output.alwaysCopiesSampleData = true

        reader.add(output)
        reader.startReading()
    }

    /// Pull the next decoded frame, with `preferredTransform` already applied.
    /// Returns nil at end of video or on error. The returned pixel buffer stays
    /// valid until the next call to `nextFrame()`.
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

        guard let rawBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            logger.warning("Frame \(self.frameIndex): no image buffer in sample")
            return nil
        }

        retainedSampleBuffer = sampleBuffer
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        currentTime = pts
        frameIndex += 1

        if !needsRotation {
            return (rawBuffer, pts)
        }

        guard let pool = bufferPool else {
            // Pool failed to initialize — fall back to the un-rotated buffer so
            // the pipeline at least produces output, even if MediaPipe will be
            // unhappy with the orientation.
            return (rawBuffer, pts)
        }

        var rotated: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(nil, pool, &rotated)
        guard status == kCVReturnSuccess, let outBuf = rotated else {
            logger.warning("Frame \(self.frameIndex): pool buffer allocation failed (status=\(status)); falling back to un-rotated input")
            return (rawBuffer, pts)
        }

        let oriented = CIImage(cvPixelBuffer: rawBuffer)
            .transformed(by: preferredTransform)
            .transformed(by: translationToOrigin)
        ciContext.render(oriented, to: outBuf)

        return (outBuf, pts)
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
