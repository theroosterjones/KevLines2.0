# KevLines 2.1 — On-Device Exercise Form Analysis

A fully local iOS app that analyzes exercise videos and overlays biomechanical feedback (joint angles, skeleton, rep counts, tempo phases) in real time using the device camera or saved videos. No server, no cloud, no network dependency.

## Changelog

### v2.1.0 — Live Camera, 3D Angles, Adaptive Smoothing
- **Live camera mode** — real-time skeleton overlay via Metal (`MTKView` + `CVMetalTextureCache`), SwiftUI Canvas on top for joint labels; record and export the annotated video without leaving the app
- **Two new exercises** — Elbow (Bicep/Tricep) and Shoulder Assessment
- **Shoulder Assessment** — posterior-plane bilateral analysis measuring left/right shoulder elevation from true 3D world coordinates; uses hip level as a baseline reference
- **3D world landmark angles** — all joint angle measurements now use MediaPipe's metric world coordinates (metres, y-up, hip-centred origin) via `result.worldLandmarks`; 2D screen coordinates are still used for overlay drawing only
- **1€ adaptive smoothing** — replaced fixed-alpha EMA with the one-euro filter; cutoff frequency adapts to signal speed so the skeleton is smooth at rest and responsive during reps without retuning per exercise
- **Exercise consolidation** — removed Back Squat and Hack Squat; kept a single generic Squat analyzer

### v2.0.0 — On-Device Foundation
- Full port of the Python/Flask backend to a native iOS pipeline
- Hardware-accelerated video I/O via `AVAssetReader` / `AVAssetWriter`
- MediaPipe Pose Landmarker on-device (iOS SDK, GPU delegate)
- Tempo phase classification (eccentric / pause / concentric / pause) via angular velocity
- Saved video analysis with annotated video export

---

## Why 2.0 Exists

KevLines 1.x ([repository](https://github.com/theroosterjones/KevLines)) used a hybrid architecture: an iOS frontend uploaded videos to a Python/Flask backend on Render for MediaPipe processing, then downloaded the annotated result. This worked but had critical performance problems:

| Problem | Impact |
|---|---|
| Full video uploaded/downloaded over HTTPS | 2-5 min round trip on cellular |
| `cv2.VideoCapture` software decode on server | No hardware acceleration |
| MediaPipe CPU-only on server | Every frame CPU-bound |
| 5-codec fallback cascade per export | Unpredictable encode path |
| Second ffmpeg re-encode for color fidelity | Double processing time |
| Render free-tier cold starts | 30-60s delay before processing begins |
| No real-time capability | Can't process live camera feed |

**KevLines 2.0 eliminates all of these.** Everything runs on-device using Apple's hardware video pipeline and MediaPipe's iOS GPU delegate.

---

## Architecture

### Saved Video Mode
```
┌──────────────────────────────────────────────────────────────────────┐
│                         SAVED VIDEO PIPELINE                          │
│                                                                       │
│  AVAssetReader ──► MediaPipe Pose ──► Analysis Engine ──► Overlay    │
│  (HW decode)       Landmarker         • AngleCalculator   Renderer   │
│                    (GPU)              • LandmarkSmoother  (CoreGFX)  │
│                                       • RepCounter             │     │
│                                       • TempoTracker            │    │
│                                                                  ▼   │
│                                                          AVAssetWriter│
│                                                          (HW encode) │
└──────────────────────────────────────────────────────────────────────┘
```

### Live Camera Mode (v2.1)
```
┌──────────────────────────────────────────────────────────────────────┐
│                         LIVE CAMERA PIPELINE                          │
│                                                                       │
│  AVCaptureSession ──► MediaPipe Pose ──► Analysis Engine             │
│  (BGRA, portrait)     Landmarker         • AngleCalculator           │
│         │             (GPU)              • LandmarkSmoother (1€)     │
│         │                                • RepCounter                │
│         │                                                            │
│         ├──► MetalCameraRenderer (MTKView) ◄─── Camera feed         │
│         │    + SwiftUI Canvas overlay (OverlayInstructions)          │
│         │                                                            │
│         └──► (when recording) OverlayRenderer ──► LiveVideoRecorder │
│                                (CoreGFX)           (AVAssetWriter)   │
└──────────────────────────────────────────────────────────────────────┘
```

---

## Supported Exercises

| Exercise | Tracked Joints | Rep Counting | Notes |
|---|---|---|---|
| Squat | Knee, Hip | Knee angle (100°/160°) | Side view |
| Barbell Row | Elbow, Shoulder | Elbow angle (100°/150°) | Side view |
| Lat Pulldown | Elbow, Shoulder | Elbow angle (90°/150°) | Side view |
| Elbow (Bicep/Tricep) | Elbow | Elbow angle (60°/155°) | Side view; covers curl, extension |
| Shoulder Assessment | Shoulder girdle tilt | None (postural) | Posterior view; left/right elevation comparison |

All angle measurements use **3D world coordinates** (camera-position-independent) with 2D screen coordinates as a fallback.

---

## New in 2.1: Technical Details

### Live Camera (Metal)
`CameraService` wraps `AVCaptureSession` with `kCVPixelFormatType_32BGRA` output, a 90° rotation for portrait orientation, and front-camera mirroring. `MetalCameraRenderer` converts each `CVPixelBuffer` to an `MTLTexture` via `CVMetalTextureCache` (zero-copy) and renders it as a textured full-screen quad. A `SwiftUI.Canvas` overlay draws the skeleton instructions in normalized coordinates on top. When recording, `OverlayRenderer` composites the overlay onto a cloned pixel buffer and writes it via `LiveVideoRecorder` (`AVAssetWriter`, `expectsMediaDataInRealTime = true`).

### 3D World Landmark Angles
`PoseLandmarkerService` now extracts both `result.landmarks` (normalised 2D, for overlay drawing) and `result.worldLandmarks` (metric 3D, for angle calculations). `AngleCalculator.angle3D(a:b:c:)` computes the interior angle using `simd_normalize` + `simd_dot` + `acos` with a `[-1, 1]` clamp. Each analyzer tries world positions first and falls back to 2D screen positions if unavailable. `LandmarkSmoother` has independent `smooth()` (2D) and `smooth3D()` channels so overlay and angle smoothing don't interfere.

### 1€ Adaptive Filter
`LandmarkSmoother` is now a 1€ filter. At rest the cutoff is `minCutoff = 1.0 Hz` (smooth). During movement the cutoff rises proportionally to `beta × |smoothed_speed|` (`beta = 0.5`), keeping the skeleton responsive during reps without jitter at lockout. The `timestamp` parameter accepts `landmarks.timestamp` (actual frame time) so the filter uses correct `dt` in both live and offline modes — without this, offline video processed faster than real time would give a near-zero alpha and freeze the filter.

---

## Project Structure

```
KevLines2.0/
├── Sources/
│   ├── App/
│   │   ├── KevLines2App.swift
│   │   └── ContentView.swift               # Three-tab navigation
│   ├── Core/
│   │   ├── Camera/
│   │   │   └── CameraService.swift         # AVCaptureSession, BGRA output, portrait rotation
│   │   ├── Math/
│   │   │   ├── AngleCalculator.swift        # angle() 2D, angle3D() metric, extendLineToFrame()
│   │   │   └── LandmarkSmoother.swift       # 1€ adaptive filter (replaced EMA)
│   │   ├── Metal/
│   │   │   ├── MetalCameraRenderer.swift    # MTKViewDelegate, CVMetalTextureCache, draw loop
│   │   │   └── Shaders.metal               # cameraVertex / cameraFragment (BGRA full-screen quad)
│   │   ├── Pose/
│   │   │   ├── PoseLandmarkerService.swift  # MediaPipe wrapper; extracts 2D + 3D landmarks
│   │   │   └── LandmarkTypes.swift          # PoseLandmarkType, NormalizedLandmark, PoseResult
│   │   └── Video/
│   │       ├── VideoReader.swift
│   │       ├── VideoWriter.swift
│   │       ├── VideoProcessor.swift         # Offline pipeline orchestrator
│   │       └── LiveVideoRecorder.swift      # Real-time AVAssetWriter
│   ├── Analysis/
│   │   ├── ExerciseAnalyzer.swift           # Protocol + ExerciseType + shared value types
│   │   ├── RepCounter.swift
│   │   ├── TempoTracker.swift
│   │   ├── AnalysisResult.swift
│   │   └── Analyzers/
│   │       ├── SquatAnalyzer.swift
│   │       ├── RowAnalyzer.swift
│   │       ├── LatPulldownAnalyzer.swift
│   │       ├── ElbowAnalyzer.swift          # New in 2.1
│   │       └── ShoulderAnalyzer.swift       # New in 2.1
│   ├── Overlay/
│   │   └── OverlayRenderer.swift
│   ├── Views/
│   │   ├── ExerciseView.swift               # Saved Video / Live Camera mode picker
│   │   ├── LiveAnalysisView.swift           # New in 2.1 — full-screen camera + overlay UI
│   │   ├── WorkoutHistoryView.swift
│   │   └── SettingsView.swift
│   ├── Models/
│   │   ├── Exercise.swift
│   │   └── AnalysisConfig.swift
│   └── pose_landmarker_full.task
├── Tests/
│   ├── AngleCalculatorTests.swift
│   └── RepCounterTests.swift
├── project.yml                              # XcodeGen spec
└── README.md
```

---

## Getting Started

### Prerequisites

- Xcode 15.0+
- iOS 17.0+ deployment target
- Physical iPhone (Metal is required; the iOS Simulator does not support Metal rendering)

### Setup

```bash
# Clone
git clone https://github.com/theroosterjones/KevLines2.0.git
cd KevLines2.0

# Download the MediaPipe pose model
curl -L -o Sources/pose_landmarker_full.task \
  https://storage.googleapis.com/mediapipe-models/pose_landmarker/pose_landmarker_full/float16/latest/pose_landmarker_full.task

# Generate the Xcode project (requires xcodegen: brew install xcodegen)
xcodegen generate

# Open in Xcode
open KevLines2.0.xcodeproj
```

The SPM dependency ([SwiftTasksVision](https://github.com/paescebu/SwiftTasksVision)) and model bundling are already configured in `project.yml`. Build, select your iPhone as the target, and run.

> **First launch:** the app will request camera access when you switch to Live Camera mode. Grant it in the system prompt or via Settings → Privacy → Camera.

---

## Tech Stack

| Layer | Technology | Notes |
|---|---|---|
| Pose estimation | MediaPipe Tasks Vision (iOS) | GPU delegate; 33 landmarks + world landmarks |
| Live camera | AVCaptureSession | BGRA output, portrait rotation via `videoRotationAngle` |
| Live display | Metal (`MTKView`) | `CVMetalTextureCache` for zero-copy GPU upload |
| Overlay (live) | SwiftUI Canvas | GPU-accelerated; draws `OverlayInstruction` in norm. coords |
| Overlay (recorded) | Core Graphics (`CGContext`) | Composites directly onto `CVPixelBuffer` |
| Video decode | AVAssetReader / VideoToolbox | Hardware-accelerated |
| Video encode | AVAssetWriter / VideoToolbox | H.264, single pass |
| Angle math | simd (Accelerate) | `angle()` 2D screen, `angle3D()` metric world |
| Smoothing | 1€ filter | Adaptive cutoff: smooth at rest, responsive during reps |
| UI | SwiftUI | iOS 17+ |

---

## Performance

| Stage | KevLines 1.x | KevLines 2.0 | KevLines 2.1 |
|---|---|---|---|
| Video decode | cv2 CPU software | AVAssetReader HW | AVAssetReader HW |
| Pose estimation | MediaPipe CPU (server) | MediaPipe GPU (device) | MediaPipe GPU (device) |
| Overlay rendering | OpenCV CPU | Core Graphics | Metal (live) / Core Graphics (saved) |
| Video encode | cv2 + ffmpeg re-encode | AVAssetWriter HW | AVAssetWriter HW |
| Network transfer | Upload + download | None | None |
| Angle accuracy | 2D projected (camera-dependent) | 2D projected | 3D world metric |
| **30s video total** | **2-5 minutes** | **5-15 seconds** | **5-15 seconds** |
| **Live camera** | **Not supported** | **Not supported** | **Real-time** |

---

## Adding a New Exercise

1. Create `Sources/Analysis/Analyzers/NewExerciseAnalyzer.swift` conforming to `ExerciseAnalyzer`
2. Guard on 2D positions (needed for overlay), then fetch 3D world positions for angle calculation
3. Use `AngleCalculator.angle3D()` with a `AngleCalculator.angle()` fallback
4. Pass `timestamp: landmarks.timestamp` to every `smoother.smooth()` call
5. Add the case to `ExerciseType` and `ExerciseConfig.all` in `Exercise.swift`

No server changes, no API updates, no deployment.

---

## Roadmap

- [x] Wire up MediaPipe iOS SDK
- [x] Create Xcode project with SPM dependency
- [x] Live camera analysis (real-time overlay via Metal)
- [x] 3D angle calculations using MediaPipe world landmarks
- [x] Advanced smoothing filters (1€ one-euro filter)
- [ ] SwiftData persistence for workout history
- [ ] Video export with audio track preservation
- [ ] Form scoring algorithm (per-rep quality score)
- [ ] Apple Watch companion (rep counting via CoreMotion)

---

## License

MIT License
