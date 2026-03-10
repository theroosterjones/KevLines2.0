# KevLines 2.0 - On-Device Exercise Form Analysis

A fully local iOS app that analyzes exercise videos and overlays biomechanical feedback (joint angles, skeleton, rep counts, tempo phases) in real time. No server, no cloud, no network dependency.

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

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                    FULLY LOCAL PIPELINE                              │
│                                                                     │
│  AVAssetReader ──► MediaPipe Pose ──► Analysis Engine ──► Overlay   │
│  (HW decode)       Landmarker         • AngleCalculator    Renderer │
│                    (GPU)              • LandmarkSmoother   (CoreGFX) │
│                                       • RepCounter              │   │
│                                       • TempoTracker            │   │
│                                                                 ▼   │
│                                                          AVAssetWriter│
│                                                          (HW encode) │
│                                                              │      │
│                                                              ▼      │
│                                                         Photos /    │
│                                                         Files.app   │
└─────────────────────────────────────────────────────────────────────┘
```

## Supported Exercises

| Exercise | Tracked Angles | Rep Counting | Ported From |
|---|---|---|---|
| Barbell Row | Elbow, Shoulder | Elbow angle thresholds (100°/150°) | `row_analyzer.py` |
| Back Squat | Knee, Hip | Knee angle thresholds | `backsquat_analyzer.py` |
| Hack Squat | Knee, Hip, Spine | Knee angle thresholds | `hacksquat_analyzer.py` |
| Lat Pulldown | Elbow, Shoulder | Elbow angle thresholds | `pose_analyzer.py` |
| Squat | Knee | Knee angle thresholds | `app.py` (FitnessAnalyzer) |

## New in 2.0

- **Tempo tracking**: Classifies each frame into eccentric / pause / concentric / pause phases using angular velocity
- **Shared math modules**: `AngleCalculator` and `LandmarkSmoother` used by all analyzers (no more copy-paste)
- **Modular overlay system**: Analyzers emit `OverlayInstruction` values; `OverlayRenderer` draws them
- **Hardware-accelerated video I/O**: `AVAssetReader`/`AVAssetWriter` replace OpenCV + ffmpeg

## Project Structure

```
KevLines2.0/
├── Sources/
│   ├── App/
│   │   ├── KevLines2App.swift              # @main entry point
│   │   └── ContentView.swift               # Tab navigation
│   ├── Core/
│   │   ├── Math/
│   │   │   ├── AngleCalculator.swift        # 2D angle + line extension (ports calculate_angle)
│   │   │   └── LandmarkSmoother.swift       # EMA filter (ports smooth_landmark)
│   │   ├── Pose/
│   │   │   ├── PoseLandmarkerService.swift  # MediaPipe iOS SDK wrapper
│   │   │   └── LandmarkTypes.swift          # 33-landmark enum, NormalizedLandmark, PoseResult
│   │   └── Video/
│   │       ├── VideoReader.swift            # AVAssetReader (HW decode)
│   │       ├── VideoWriter.swift            # AVAssetWriter (HW encode, H.264)
│   │       └── VideoProcessor.swift         # Pipeline orchestrator
│   ├── Analysis/
│   │   ├── ExerciseAnalyzer.swift           # Protocol + shared types
│   │   ├── RepCounter.swift                 # Generic angle-threshold state machine
│   │   ├── TempoTracker.swift               # Angular velocity phase classifier
│   │   ├── AnalysisResult.swift             # WorkoutResult for persistence
│   │   └── Analyzers/
│   │       ├── RowAnalyzer.swift
│   │       ├── BackSquatAnalyzer.swift
│   │       ├── HackSquatAnalyzer.swift
│   │       ├── LatPulldownAnalyzer.swift
│   │       └── SquatAnalyzer.swift
│   ├── Overlay/
│   │   └── OverlayRenderer.swift            # Core Graphics drawing on CVPixelBuffer
│   ├── Views/
│   │   ├── ExerciseView.swift               # Video selection + local analysis
│   │   ├── WorkoutHistoryView.swift
│   │   └── SettingsView.swift
│   ├── Models/
│   │   ├── Exercise.swift                   # ExerciseConfig + factory
│   │   └── AnalysisConfig.swift             # Tunable thresholds
│   └── pose_landmarker_full.task            # MediaPipe model (bundle resource)
├── Tests/
│   ├── AngleCalculatorTests.swift
│   └── RepCounterTests.swift
├── PythonReference/                          # Original Python analyzers (read-only reference)
│   ├── row_analyzer.py
│   ├── backsquat_analyzer.py
│   ├── hacksquat_analyzer.py
│   ├── pose_analyzer.py
│   └── app.py
├── project.yml                              # XcodeGen spec
└── README.md
```

## Getting Started

### Prerequisites

- Xcode 15.0+
- iOS 17.0+ deployment target
- MediaPipe Tasks Vision iOS SDK (via SPM)
- Pose Landmarker model file (`.task` bundle)

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

The SPM dependency ([SwiftTasksVision](https://github.com/paescebu/SwiftTasksVision)) and model bundling are already configured in `project.yml`. Just build and run.

## Tech Stack

| Layer | Technology | Why |
|---|---|---|
| Pose estimation | MediaPipe Tasks Vision (iOS) | Same 33 landmarks as Python, GPU delegate |
| Video decode | AVAssetReader / VideoToolbox | Hardware-accelerated, zero-copy buffers |
| Video encode | AVAssetWriter / VideoToolbox | Single-pass H.264, no codec guessing |
| Overlay rendering | Core Graphics (CGContext) | Draw directly on CVPixelBuffer |
| Angle math | simd (Accelerate) | SIMD-optimized vector operations |
| Smoothing | Custom EMA | Matches Python's exponential moving average |
| UI | SwiftUI | Declarative, modern |
| Future persistence | SwiftData | Workout history storage |

## Performance Target

| Stage | KevLines 1.x | KevLines 2.0 |
|---|---|---|
| Video decode | cv2 CPU software | AVAssetReader HW |
| Pose estimation | MediaPipe CPU (server) | MediaPipe GPU (device) |
| Overlay rendering | OpenCV CPU | Core Graphics |
| Video encode | cv2 + ffmpeg re-encode | AVAssetWriter HW |
| Network transfer | Upload + download | None |
| **30s video total** | **2-5 minutes** | **5-15 seconds** |

## Adding a New Exercise

1. Create `Analysis/Analyzers/NewExerciseAnalyzer.swift` conforming to `ExerciseAnalyzer`
2. Define `requiredLandmarks`, implement `analyze(landmarks:)`, emit `OverlayInstruction` values
3. Add the exercise to `ExerciseType` enum and `ExerciseConfig.all`
4. That's it. No server changes, no API updates, no deployment.

## Roadmap

- [x] Wire up MediaPipe iOS SDK (uncomment `PoseLandmarkerService`)
- [x] Create Xcode project with SPM dependency
- [ ] Live camera analysis (real-time overlay via Metal)
- [ ] SwiftData persistence for workout history
- [ ] 3D angle calculations using MediaPipe world landmarks
- [ ] Advanced smoothing filters (Kalman, one-euro)
- [ ] Video export with audio track preservation
- [ ] Form scoring algorithm
- [ ] Apple Watch companion (rep counting via CoreMotion)

## License

MIT License
