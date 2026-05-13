# KevLines 3.3.5 — On-Device Exercise Form Analysis & Movement Assessment

A fully local iOS app that analyzes exercise videos and movement screens, overlaying biomechanical feedback (joint angles, skeleton, rep counts, tempo phases, letter-graded postural assessments) in real time using the device camera or saved videos. No server, no cloud, no network dependency.

## Documentation map

| Doc | Audience |
|-----|----------|
| **[AGENTS.md](AGENTS.md)** | AI assistants / developers — condensed architecture, version pins, pitfalls, links |
| **[docs/README.md](docs/README.md)** | Index of technical notes in `docs/` |
| **[docs/VideoOrientation.md](docs/VideoOrientation.md)** | **Required before editing saved-video decode** (`VideoReader`) — orientation vs Photos/QuickTime; why CI tricks failed; **video composition** solution (v3.3.2+) |
| **[docs/Troubleshooting.md](docs/Troubleshooting.md)** | **Active issues & investigation notes** (e.g. squat/hinge export overlays, saved-video exercise crashes) — version-stamped in the doc |

**Saved-video orientation:** Do not change decode/export without reading **docs/VideoOrientation.md**. Use **`AVMutableVideoComposition` + `AVAssetReaderVideoCompositionOutput`** as in `VideoReader`—not ad-hoc Core Image + `preferredTransform` (upside-down / mirror / left–right bugs).

## Changelog

### v3.3.5 — Lunge hip angle, pause-bottom rounding, deep squat lean grading

- **Hip angle in lunge overlay** — "Hip: X°" (shoulder→hip→knee, cyan) label added to the lunge exercise overlay. Uses 3D world landmarks with 2D fallback. Display-only; no effect on rep counting or tempo.
- **Pause-at-bottom rounding** — the second number in the `ecc-pauseBottom-con-pauseTop` tempo string now rounds **down** (floor) instead of nearest across all exercises. A brief touch-and-go that measures 0.9 s no longer displays as 1. Applies to both completed-rep history and the in-progress live tempo readout.
- **Squat sagittal assessment — depth-aware torso lean grading** — when the knee angle drops below 90° (deep squat), lean thresholds switch to a more forgiving band: ≤ 50° → A, 51–60° → B, 61–70° → C, 71–80° → D. The standard thresholds (≤ 25° → A) still apply for shallow squats. Depth and knee flexion grades are unaffected.
- **Marketing / build** — `3.3.5` (14).

### v3.3.4 — Squat rep counting fix, hip angle HUD, pose tracking diagnostic

- **Squat extended threshold 160° → 150°** — the rep counter previously required the knee angle to exceed 160° at lockout to register "standing." Real-world side-profile footage (especially at a slight camera angle) typically reads 145–158° at full extension, causing most reps to be silently missed. The 150° threshold accommodates this without over-counting.
- **Hip angle in squat overlay** — a "Hip: X°" label (shoulder→hip→knee, cyan) now appears next to the hip joint on every squat analysis frame. Uses 3D world landmarks when MediaPipe provides them, falls back to 2D. Display-only; no effect on rep counting or tempo.
- **Pose tracking rate in results UI** — `AnalysisSummary` now carries `poseDetectionRate` (0–1). Both the exercise and assessment results cards show "Pose tracked: X% of frames" color-coded green/yellow/red. This surfaces the poseMiss rate directly in the app without requiring Xcode or Console.
- **Fix: 0% pose detection on second+ analysis run** — `PoseLandmarkerService.resetForNewSession()` tears down and re-creates the `PoseLandmarker` instance before each saved-video run. MediaPipe's video mode requires strictly increasing timestamps; re-using one instance across multiple analyses caused every subsequent run to show 0% detection because video timestamps restart from 0.
- **Deadlift camera tip** — setup guidance and low-tracking warning now advise filming at 15–30° off a strict side profile so the barbell doesn't occlude the hip and break person detection.
- **Marketing / build** — `3.3.4` (13).

### v3.3.2 — Saved-video orientation (AVFoundation composition)
- **`VideoReader` uses `AVMutableVideoComposition` + `AVAssetReaderVideoCompositionOutput`** — applies `preferredTransform` the same way as QuickTime / Photos / `AVPlayer`, then reads BGRA frames. Replaces hand-rolled Core Image transforms (which mixed CI vs pixel-buffer coordinate systems and caused upside-down, mirrored, or left/right–swapped video vs the source clip). Side selection and overlays again align with how the imported video appears in the library.
- **Marketing / build** — `3.3.2` (9).
- **Overlay reliability (follow-up)** — angle HUD strings now use `AngleCalculator.displayDegrees` because **`Int(Float.nan)` traps at runtime** in Swift (could crash Row/Deadlift/saved-video analysis when 3D angles degenerate). `angle3D` and `extendLineToFrame` guard zero-length edges. Open UX issues (squat/hinge assessment overlays on export) are tracked in **[docs/Troubleshooting.md](docs/Troubleshooting.md)**.

### v3.3.1 — Saved-video orientation (mirror fix)
- **`VideoReader` coordinate order** — replace the post-rotation vertical flip (v3.3.0) with a **CV→Core Image vertical flip applied before `preferredTransform`**. Flipping after rotation corrected upside-down exports but composed incorrectly with the rotation matrix and produced a **left–right mirror** vs the source. Front-loading the flip matches how CI and AVFoundation compose orientation and restores reliable pose + overlays (frontal assessments are sensitive to consistent left/right semantics).
- **Marketing / build** — `3.3.1` (8).

### v3.3.0 — Saved-video export orientation
- **`VideoReader` vertical alignment** — after baking `preferredTransform` with Core Image, apply one vertical flip into top-first bitmap layout. Core Image uses a bottom-left origin while decoded video buffers are top-first; without this, analyzed exports (and in-app preview of the output) could appear upside down relative to the source clip in Photos / QuickTime. Affects both **Exercises** and **Assessments** (shared `VideoProcessor` path).
- **Marketing / build** — `3.3.0` (7).

### v3.2.0 — Plane-aware Movement Assessments
- **Front/Back vs Side picker per assessment** — every movement assessment now ships in two camera-plane variants. The picker UI surfaces only the planes a given assessment supports, snaps the side picker on/off automatically (sagittal needs a side, frontal is bilateral), and rewrites both the camera-setup tip and low-tracking warning per plane.
- **Sagittal Squat Assessment** — strict 90° side profile of the working leg. Grades depth (hip→knee→ankle), exposes peak knee flexion as a clinically familiar number, and grades torso lean against a band rather than purely lower-is-better. Captures lean *at* the bottom (not the worst lean across the clip) so descent/ascent transients don't bias the score.
- **Frontal Hip Hinge Assessment** — bilateral rear-view hinge screen. Grades hip tilt, shoulder tilt, and worst-knee tracking deviation as a percentage of hip width. Sticky "high-side" labels (e.g. "L hip high 6.4°") so the summary names the asymmetric side, not just its magnitude.
- **Sagittal Shoulder Flexion** — single-arm side-profile ROM analyzer with automatic side fallback when the user accidentally films the wrong profile (driven by mean per-landmark visibility with hysteresis to prevent flapping).

### v3.0.0 — Assessments, HUD modes, Spine landmarks
- **Movement Assessments** — a new analysis category alongside Exercises. Implements `AssessmentAnalyzer` with letter-graded sub-metrics (A–F), a "weakest-link" overall grade, and a colored skeleton driven by per-frame grade with hysteresis to prevent flicker. Initial set: **Shoulder Flexion** (bilateral overhead ROM with asymmetry detection), **Squat Assessment** (rear-view depth + trunk lean + knee tracking), **Hip Hinge Assessment** (side-view depth + spine neutrality).
- **Simple / Full HUD overlay modes** — toggleable via the gauge button in Live and the picker in Saved Video. `HUDOverlayBuilder` adds a right-anchored column with a large rep counter, current consistency score (0–100), live in-progress tempo, and the last six reps' tempo history.
- **Per-rep metrics + consistency score** — `RepMetricsCollector` captures peak ROM angle and per-phase tempo durations for every completed rep, then derives a 0–100 score (60% ROM stddev, 40% tempo stddev). Outlier-gated against frames with a >30° single-step jump so one bad MediaPipe snap can't tank the score.
- **Spine overlay** — derived ear → shoulder → mid-thoracic → hip polyline drawn behind every analyzer's joint markers. MediaPipe ships no explicit spine landmarks; `SpineOverlay` interpolates one and uses a single canonical color (`OverlayColor.spine`) so spine lines are immediately readable across every screen.
- **Confidence-gated rep counting** — Squat / Deadlift / similar analyzers now gate rep counting, tempo classification, and peak-angle tracking behind a per-vertex visibility threshold (`minVertexVisibility = 0.5`). Low-confidence frames emit `.nan` for the angle so the metrics collector skips them, while overlay drawing falls back to the last trusted angle to avoid label flicker.
- **Live tracking-quality warning** — non-blocking yellow banner appears when 20+ consecutive frames return no usable pose, with exercise/assessment-specific repositioning hints.

### v2.3.0 — Exercise Library Expansion
- **Deadlift** (side view) — tracks hip angle (shoulder→hip→knee) as the primary rep driver with secondary knee angle; tempo tracking on the hip hinge.
- **Lunge** (side view) — tracks front knee angle with trunk lean shown in HUD to flag excessive forward lean.
- **Hip Hinge (Side)** — focused hinge pattern for RDL, good mornings, and KB deadlift drills; overlays a vertical plumb line through the hip as a hinge cue.
- **Hip Hinge (Back)** — bilateral assessment-style mode tracking hip tilt, shoulder tilt, and knee valgus/varus per side; no rep counting.
- **Overhead Press** (front or back view, bilateral) — tracks both elbow angles independently with average-driven rep counting; torso lean shown in HUD and highlighted red if >15°.

### v2.2.0 — Camera Switching
- **Front/back camera toggle** — tap the camera flip button in the live analysis top bar to switch between front and back camera at any time; mirroring is applied automatically for the front camera.

### v2.1.0 — Live Camera, 3D Angles, Adaptive Smoothing
- **Live camera mode** — real-time skeleton overlay via Metal (`MTKView` + `CVMetalTextureCache`), SwiftUI Canvas on top for joint labels; record and export the annotated video without leaving the app.
- **Two new exercises** — Elbow (Bicep/Tricep) and Shoulder Assessment.
- **Shoulder Assessment** — posterior-plane bilateral analysis measuring left/right shoulder elevation from true 3D world coordinates; uses hip level as a baseline reference.
- **3D world landmark angles** — all joint angle measurements now use MediaPipe's metric world coordinates (metres, y-up, hip-centred origin) via `result.worldLandmarks`; 2D screen coordinates are still used for overlay drawing only.
- **1€ adaptive smoothing** — replaced fixed-alpha EMA with the one-euro filter; cutoff frequency adapts to signal speed so the skeleton is smooth at rest and responsive during reps without retuning per exercise.
- **Exercise consolidation** — removed Back Squat and Hack Squat; kept a single generic Squat analyzer.

### v2.0.0 — On-Device Foundation
- Full port of the Python/Flask backend to a native iOS pipeline.
- Hardware-accelerated video I/O via `AVAssetReader` / `AVAssetWriter`.
- MediaPipe Pose Landmarker on-device (iOS SDK, GPU delegate).
- Tempo phase classification (eccentric / pause / concentric / pause) via angular velocity.
- Saved video analysis with annotated video export.

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

**KevLines 2.0 eliminated all of these.** Everything runs on-device using Apple's hardware video pipeline and MediaPipe's iOS GPU delegate. The 3.x line builds on that foundation with assessments, HUD, and plane-aware analysis.

---

## Architecture

### Saved Video Mode
```
┌──────────────────────────────────────────────────────────────────────┐
│                         SAVED VIDEO PIPELINE                          │
│                                                                       │
│  VideoReader ──► MediaPipe Pose ──► Frame Analyzer ──► Overlay       │
│  AVMutableComposition +          Landmarker         • Exercise /    │
│  AVAssetReaderVideoCompositionOutput (GPU)            Assessment    │
│  (display-oriented BGRA,                              • LandmarkSmoother│
│   matches Photos / QuickTime)                         • RepCounter … │
│                                                                  ▼   │
│                                                          AVAssetWriter│
│                                                          (HW encode) │
└──────────────────────────────────────────────────────────────────────┘
```

### Live Camera Mode
```
┌──────────────────────────────────────────────────────────────────────┐
│                         LIVE CAMERA PIPELINE                          │
│                                                                       │
│  AVCaptureSession ──► MediaPipe Pose ──► Frame Analyzer              │
│  (BGRA, portrait)     Landmarker         (Exercise or Assessment)    │
│         │             (GPU)                                          │
│         │                                                            │
│         ├──► MetalCameraRenderer (MTKView) ◄─── Camera feed         │
│         │    + SwiftUI Canvas overlay (OverlayInstructions)          │
│         │                                                            │
│         └──► (when recording) OverlayRenderer ──► LiveVideoRecorder │
│                                (CoreGFX)           (AVAssetWriter)   │
└──────────────────────────────────────────────────────────────────────┘
```

The same `OverlayInstruction` enum (`.line / .extendedLine / .circle / .text`) is consumed by both `OverlayRenderer` (Core Graphics, used for saved-video export and live recording) and `OverlayCanvas` (SwiftUI Canvas, used for live preview), so analyzers stay rendering-agnostic.

---

## Supported Exercises

Rep-counted analyzers driven by an angle-threshold state machine + tempo classification. All angle measurements use 3D world coordinates with a 2D fallback.

| Exercise | View | Tracked Joints | Rep Driver | Notes |
|---|---|---|---|---|
| Squat | Side | Knee, Hip, Spine | Knee 100°/160° | Confidence-gated rep counting (vertex visibility ≥ 0.5) |
| Deadlift | Side | Hip, Knee, Spine | Hip 80°/160° | Same gating; secondary knee-angle readout |
| Lunge | Side | Front knee, Hip | Knee 100°/155° | Trunk-lean readout in HUD |
| Hip Hinge (Side) | Side | Hip, Knee | Hip 65°/155° | Vertical plumb line through hip as hinge cue |
| Hip Hinge (Back) | Rear | Hips, Shoulders, Knees | None (postural) | Bilateral tilt + valgus/varus screen |
| Barbell Row | Side | Elbow, Shoulder | Elbow 100°/150° | |
| Lat Pulldown | Side | Elbow, Shoulder | Elbow 90°/150° | |
| Overhead Press | Front/Back | Both elbows (bilateral) | Avg elbow | Torso lean flagged red if >15° |
| Elbow (Bicep/Tricep) | Side | Elbow | Elbow 60°/155° | Covers curl + extension |
| Shoulder Assessment | Front/Back | Shoulder girdle tilt | None (postural) | L/R shoulder elevation comparison |

---

## Movement Assessments

Letter-graded postural / movement screens with no rep counting. Each surfaces an overall grade plus per-metric sub-grades using a "weakest-link" model (overall grade = worst sub-grade). Each assessment ships in two camera-plane variants; the picker auto-hides the side selector for frontal-plane (bilateral) variants.

| Assessment | Frontal (Front/Back) | Sagittal (Side) |
|---|---|---|
| Shoulder Flexion | Bilateral overhead ROM, L/R asymmetry flag (>15° diff) | Single-arm ROM with auto side-fallback when the wrong profile is filmed |
| Squat Assessment | Depth (avg knee), Trunk Lean, Knee Tracking (% of hip width) | Depth + Knee Flexion + Torso Lean (graded vs. an expected band) |
| Hip Hinge Assessment | Hip Level, Shoulder Level, Knee Tracking (sticky high-side label) | Hinge Depth + Spine Neutrality (mid-spine deviation from ear-hip line) |

Coloring uses `OverlayColor.romQuality(grade:)` (green→red across A–F) and runs through `GradeHysteresis` (5-frame default) so the colored skeleton doesn't flicker between adjacent grades during live preview.

---

## Technical Details

### Live Camera (Metal)
`CameraService` wraps `AVCaptureSession` with `kCVPixelFormatType_32BGRA` output, a 90° rotation for portrait orientation, and front-camera mirroring. `MetalCameraRenderer` converts each `CVPixelBuffer` to an `MTLTexture` via `CVMetalTextureCache` (zero-copy) and renders it as a textured full-screen quad. A `SwiftUI.Canvas` overlay draws the skeleton instructions in normalized coordinates on top. When recording, `OverlayRenderer` composites the overlay onto a cloned pixel buffer and writes it via `LiveVideoRecorder` (`AVAssetWriter`, `expectsMediaDataInRealTime = true`).

### 3D World Landmark Angles
`PoseLandmarkerService` extracts both `result.landmarks` (normalised 2D, for overlay drawing) and `result.worldLandmarks` (metric 3D, for angle calculations). `AngleCalculator.angle3D(a:b:c:)` computes the interior angle using `simd_normalize` + `simd_dot` + `acos` with a `[-1, 1]` clamp. Each analyzer tries world positions first and falls back to 2D screen positions if unavailable. `LandmarkSmoother` has independent `smooth()` (2D) and `smooth3D()` channels so overlay and angle smoothing don't interfere.

### 1€ Adaptive Filter
`LandmarkSmoother` is a 1€ filter. At rest the cutoff is `minCutoff = 1.0 Hz` (smooth). During movement the cutoff rises proportionally to `beta × |smoothed_speed|` (`beta = 0.5`), keeping the skeleton responsive during reps without jitter at lockout. The `timestamp` parameter accepts `landmarks.timestamp` (actual frame time) so the filter uses correct `dt` in both live and offline modes — without this, offline video processed faster than real time would give a near-zero alpha and freeze the filter.

### Plane-aware Assessment Routing
`AssessmentConfig.makeAnalyzer(side:plane:)` switches over a `(AssessmentType, ViewPlane)` tuple to instantiate the correct analyzer. Each assessment declares its `supportedPlanes` and `defaultPlane`; the picker UI in both `ExerciseView` and `LiveAnalysisView` only shows the segmented plane control when `supportedPlanes.count > 1`, snaps the plane back to the default on assessment change, and toggles the side selector on/off based on `requiresSideSelection(plane:)`. Camera-setup tips and low-tracking warnings are also plane-aware.

### Per-rep Metrics + Consistency Score
`RepMetricsCollector` consumes `(phase, angle, repCount, timestamp)` once per frame. When `repCount` increments, it finalizes the rep with peak flexion angle (gated against >30° single-step jumps so one bad frame can't poison ROM stats) and per-phase durations, then resets. The 0–100 score weighs ROM stddev (60%) and tempo stddev (40%) and is only emitted after at least 3 completed reps. `HUDOverlayBuilder` renders the score, the live in-progress tempo, and the last six completed reps as a scrolling history.

### Spine Polyline
MediaPipe doesn't ship spine landmarks. `SpineOverlay.instructions(ear:shoulder:hip:)` derives a four-point polyline (ear → shoulder → midpoint → hip), uses a single canonical color (`OverlayColor.spine`), and is drawn first by every analyzer so the limb skeleton and joint markers paint over it. Sagittal-plane assessments tint the spine with the lean / neutrality grade so spine quality is immediately legible.

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
│   │   │   └── LandmarkSmoother.swift       # 1€ adaptive filter (2D + 3D channels)
│   │   ├── Metal/
│   │   │   ├── MetalCameraRenderer.swift    # MTKViewDelegate, CVMetalTextureCache, draw loop
│   │   │   └── Shaders.metal                # cameraVertex / cameraFragment (BGRA full-screen quad)
│   │   ├── Pose/
│   │   │   ├── PoseLandmarkerService.swift  # MediaPipe wrapper; extracts 2D + 3D landmarks
│   │   │   └── LandmarkTypes.swift          # PoseLandmarkType, NormalizedLandmark, PoseResult
│   │   └── Video/
│   │       ├── VideoReader.swift
│   │       ├── VideoWriter.swift
│   │       ├── VideoProcessor.swift         # Offline pipeline orchestrator
│   │       └── LiveVideoRecorder.swift      # Real-time AVAssetWriter
│   ├── Analysis/
│   │   ├── ExerciseAnalyzer.swift           # Protocol + ExerciseType + FrameAnalysis + HUDOverlayBuilder
│   │   ├── AssessmentAnalyzer.swift         # Protocol + AssessmentType + ViewPlane + LetterGrade + GradeHysteresis
│   │   ├── RepCounter.swift
│   │   ├── TempoTracker.swift
│   │   ├── RepMetrics.swift                 # RepMetric + RepMetricsCollector + score
│   │   ├── SpineOverlay.swift               # Derived ear→shoulder→mid→hip polyline
│   │   ├── AnalysisResult.swift             # Persistable WorkoutResult
│   │   └── Analyzers/
│   │       ├── SquatAnalyzer.swift
│   │       ├── DeadliftAnalyzer.swift
│   │       ├── LungeAnalyzer.swift
│   │       ├── HipHingeSideAnalyzer.swift
│   │       ├── HipHingeBackAnalyzer.swift
│   │       ├── RowAnalyzer.swift
│   │       ├── LatPulldownAnalyzer.swift
│   │       ├── OverheadPressAnalyzer.swift
│   │       ├── ElbowAnalyzer.swift
│   │       ├── ShoulderAnalyzer.swift
│   │       ├── ShoulderFlexionAssessment.swift          # Frontal (bilateral)
│   │       ├── ShoulderFlexionSagittalAssessment.swift  # Sagittal (single-arm + side fallback)
│   │       ├── SquatAssessmentAnalyzer.swift            # Frontal
│   │       ├── SquatSagittalAssessment.swift            # Sagittal
│   │       ├── HipHingeFrontalAssessment.swift          # Frontal
│   │       └── HipHingeAssessmentAnalyzer.swift         # Sagittal
│   ├── Overlay/
│   │   └── OverlayRenderer.swift            # Core Graphics renderer (saved video + live recording)
│   ├── Views/
│   │   ├── ExerciseView.swift               # Saved Video / Live Camera mode picker, assessments + plane picker
│   │   ├── LiveAnalysisView.swift           # Full-screen camera + Metal preview + SwiftUI overlay
│   │   ├── WorkoutHistoryView.swift
│   │   └── SettingsView.swift
│   ├── Models/
│   │   ├── Exercise.swift                   # ExerciseConfig + AssessmentConfig (plane routing) + camera tips
│   │   └── AnalysisConfig.swift
│   └── pose_landmarker_full.task
├── Tests/
│   ├── AngleCalculatorTests.swift
│   ├── RepCounterTests.swift
│   ├── RepMetricsTests.swift
│   ├── RowAnalyzerTests.swift
│   └── AssessmentPlanesTests.swift          # Plane routing + sagittal/frontal analyzer behavior
├── docs/
│   ├── README.md                            # Index of technical notes
│   └── VideoOrientation.md                  # Saved-video decode — do not regress
├── AGENTS.md                                # AI/developer handoff (start here)
├── project.yml                              # XcodeGen spec (incl. MediaPipe plist patch scripts)
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

The SPM dependency ([SwiftTasksVision](https://github.com/paescebu/SwiftTasksVision)) and model bundling are already configured in `project.yml`, including pre/post-build scripts that patch MediaPipe's framework `Info.plist` for App Store validation. Build, select your iPhone as the target, and run.

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
| Video decode | `VideoReader`: composition + `AVAssetReaderVideoCompositionOutput` | Display-oriented frames match system players; see docs/VideoOrientation.md |
| Video encode | AVAssetWriter / VideoToolbox | H.264, single pass |
| Angle math | simd (Accelerate) | `angle()` 2D screen, `angle3D()` metric world |
| Smoothing | 1€ filter | Adaptive cutoff: smooth at rest, responsive during reps |
| Grading | Custom (`LetterGrade` + `GradeHysteresis`) | A–F with frame-count hysteresis to prevent color flicker |
| UI | SwiftUI | iOS 17+ |

---

## Performance

| Stage | KevLines 1.x | KevLines 2.0+ |
|---|---|---|
| Video decode | cv2 CPU software | AVAssetReader HW |
| Pose estimation | MediaPipe CPU (server) | MediaPipe GPU (device) |
| Overlay rendering | OpenCV CPU | Metal (live) / Core Graphics (saved) |
| Video encode | cv2 + ffmpeg re-encode | AVAssetWriter HW |
| Network transfer | Upload + download | None |
| Angle accuracy | 2D projected (camera-dependent) | 3D world metric |
| **30s video total** | **2-5 minutes** | **5-15 seconds** |
| **Live camera** | **Not supported** | **Real-time** |

---

## Adding a New Exercise

1. Create `Sources/Analysis/Analyzers/NewExerciseAnalyzer.swift` conforming to `ExerciseAnalyzer`.
2. Guard on 2D positions (needed for overlay), then fetch 3D world positions for angle calculation.
3. Use `AngleCalculator.angle3D()` with an `AngleCalculator.angle()` fallback.
4. Pass `timestamp: landmarks.timestamp` to every `smoother.smooth()` / `smoother.smooth3D()` call.
5. (Recommended) Apply confidence gating à la `SquatAnalyzer` — skip rep counting / tempo / peak tracking when `min(visibility...) < 0.5` and emit `.nan` for the angle so `RepMetricsCollector` excludes the frame.
6. Add the case to `ExerciseType`, then add an entry to `ExerciseConfig.all` in `Models/Exercise.swift` (+ camera tip + tracking warning copy).

## Adding a New Assessment

1. Create one analyzer per supported plane (`AssessmentAnalyzer`), e.g. `MyAssessment.swift` (frontal) and `MyAssessmentSagittal.swift` (sagittal).
2. Implement `currentMetrics()` returning sub-grades + an overall grade (use `LetterGrade.gradeLowerIsBetter` / `gradeHigherIsBetter`).
3. Wrap per-frame grading in `GradeHysteresis` so the colored skeleton stays stable.
4. Add the case to `AssessmentType`, then add an entry to `AssessmentConfig.all` declaring `supportedPlanes` + `defaultPlane`.
5. Wire the case into `AssessmentConfig.makeAnalyzer(side:plane:)`.
6. Add plane-aware copy to `AssessmentType.cameraSetupTip(for:)` and `lowTrackingWarning(for:)`.

No server changes, no API updates, no deployment.

---

## Roadmap

- [x] Wire up MediaPipe iOS SDK
- [x] Create Xcode project with SPM dependency
- [x] Live camera analysis (real-time overlay via Metal)
- [x] 3D angle calculations using MediaPipe world landmarks
- [x] Advanced smoothing filters (1€ one-euro filter)
- [x] Exercise library expansion — deadlift, lunge, hip hinge, overhead press
- [x] Movement assessments — shoulder flexion, squat, hip hinge
- [x] Plane-aware assessments — frontal vs sagittal variants per assessment type
- [x] Per-rep metrics + form-quality consistency score (0–100)
- [ ] Wire live assessment grade into the Live mode bottom bar (currently shows "—")
- [ ] Apple Watch companion (rep counting via CoreMotion)
- [ ] SwiftData persistence for workout + assessment history
- [ ] Trends view — score / grade progression over time
- [ ] Video export with audio track preservation
- [ ] Single-leg balance, thoracic rotation, overhead squat screens

---

## License

MIT License
