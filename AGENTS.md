# Guidance for AI coding agents — KevLines 2.0

Use this file when picking up work on this repo (new chat, different agent, or onboarding). It summarizes architecture, conventions, and pitfalls **without replacing** the full [README](README.md).

## Product

**KevLines** — iOS 17+ SwiftUI app for **on-device** exercise form analysis and movement assessments: pose (MediaPipe), joint angles, rep counting, tempo, optional HUD/score, letter-graded assessments. **No backend** — camera + photo library only.

## Current release metadata (source of truth)

| Field | Location |
|--------|-----------|
| Marketing version | `project.yml` → `MARKETING_VERSION` (sync to `ExerciseView` navigation title, e.g. `KevLines 3.3.2`) |
| Build number | `project.yml` → `CURRENT_PROJECT_VERSION` |
| Xcode project | Generated — run **`xcodegen generate`** after editing `project.yml` |

Bundle id: `com.kevinjones.KevLines2-0`, module name `KevLines2_0`, SPM product imports `@testable import KevLines2_0` in tests.

## Repo layout (high level)

| Path | Purpose |
|------|---------|
| `project.yml` | XcodeGen spec, versions, MediaPipe plist patch scripts, SPM `SwiftTasksVision` |
| `Sources/` | All app code + `pose_landmarker_full.task` (see `.gitignore` — `*.task` may be local only; README has curl to download) |
| `Tests/` | Unit tests |
| `docs/` | Deep-dive technical notes (see [docs/README.md](docs/README.md)) |
| `AGENTS.md` | This file |
| `PythonReference/` | Legacy reference, not the runtime app |

## Pipelines (two modes)

1. **Saved video:** `VideoReader` → `PoseLandmarkerService` → `FrameAnalyzerProtocol` → `OverlayRenderer` on pixel buffer → `VideoWriter`. Orchestrated by `VideoProcessor`.
2. **Live camera:** `CameraService` → same pose + analyzer → `MetalCameraRenderer` + SwiftUI `OverlayCanvas` for preview; when recording, `OverlayRenderer` + `LiveVideoRecorder`.

Analyzers implement **`ExerciseAnalyzer`** or **`AssessmentAnalyzer`** (both conform to **`FrameAnalyzerProtocol`**). Same analyzer types run in live and offline flows.

## Critical implementation notes

### Saved-video decode orientation (do not regress)

**Do not** reconstruct orientation with raw `AVAssetReaderTrackOutput` + Core Image + `preferredTransform` + ad-hoc vertical flips — this caused upside-down, mirror, and left/right mismatch vs Photos.

**Do** use **`AVMutableVideoComposition` + `AVAssetReaderVideoCompositionOutput`** as in `Sources/Core/Video/VideoReader.swift` (stable since **v3.3.2**).

Full rationale and history: **[docs/VideoOrientation.md](docs/VideoOrientation.md)**.

### Angles and smoothing

- **Overlay:** normalized 2D `landmarks` for drawing.
- **Angles:** prefer **`worldLandmarks`** + `AngleCalculator.angle3D`, fallback to 2D `angle()`.
- **Smoothing:** `LandmarkSmoother` — separate **`smooth`** (2D) and **`smooth3D`** (3D); always pass **`landmarks.timestamp`** for correct Δt offline.

### Overlay rendering

- **`OverlayInstruction`** enum — analyzers stay renderer-agnostic.
- **`OverlayRenderer`** — Core Graphics on `CVPixelBuffer` (export paths); assumes buffers match normalized coords **after** correct decode (orientation is not fixed here).

### Exercises vs assessments

- **Routing:** `ExerciseConfig` / `AssessmentConfig` in `Sources/Models/Exercise.swift`; assessments use **`ViewPlane`** (frontal vs sagittal) via **`AssessmentConfig.makeAnalyzer(side:plane:)`**.
- **UI:** `ExerciseView`, `LiveAnalysisView` — category picker, plane picker, side picker when required.

### SPM / App Store

- Dependency: **SwiftTasksVision** → MediaPipe Tasks Vision XCFramework.
- `project.yml` includes pre/post-build **PlistBuddy** scripts to patch embedded MediaPipe `Info.plist` for validation — keep when regenerating the project.

### Analysis diagnostics (logging)

- **`AnalysisLog`** (`Sources/Core/Diagnostics/AnalysisLog.swift`) — single subsystem (`com.kevinjones.KevLines2-0`) with categories **Pipeline**, **Pose**, **VideoReader**, **VideoWriter**, **ExerciseUI**. Uses **`Logger` only** (no on-disk log during decode/analyze). End-of-run **Pipeline** summary includes `poseMiss` vs `poseOkEmptyOverlay` to distinguish failed pose from strict analyzer guards. How to read Console output: **[docs/Troubleshooting.md](docs/Troubleshooting.md)**.

## Testing

- Target: **KevLines2.0Tests**; physical **iPhone** for anything involving Metal live preview.
- Notable: `AssessmentPlanesTests.swift`, `AngleCalculatorTests.swift`, `RepCounterTests`, etc.

## What to avoid

- Drive-by refactors unrelated to the task; keep diffs focused.
- Editing `*.task` model binaries in git unless intentional.
- Changing `VideoReader` without reading **docs/VideoOrientation.md** first.
- Forgetting **`xcodegen generate`** after `project.yml` changes.

### MediaPipe timestamp reset (critical — do not regress)

`PoseLandmarkerService` runs in `.video` mode which requires **strictly increasing timestamps** across all `detect()` calls on the same instance. `VideoProcessor` is a `@StateObject` that lives for the entire app session. Every new analysis must call **`poseLandmarker.resetForNewSession()`** (which destroys and re-creates the `PoseLandmarker` instance) before the read loop begins. Skipping this causes 0% pose detection on every analysis after the first.

### Pose tracking rate diagnostic

`AnalysisSummary.poseDetectionRate` (Float 0–1) is computed in `VideoProcessor` and surfaced in the results UI as "Pose tracked: X% of frames". Green ≥ 70%, yellow 40–69%, red < 40%. Blank overlays with a low tracking rate = `poseMiss` (MediaPipe not detecting a person); blank overlays with a high tracking rate = `poseOkEmptyOverlay` (analyzer guard failing despite detection).

### Rep counting conventions

- Standard analyzers use **`RepCounter(extendedThreshold:flexedThreshold:)`** — a simple state machine driven by a joint angle. Larger angle = extended.
- **`HipHingeBackAnalyzer`** uses a **self-calibrating trunk-height signal** (`hipMid.y − shoulderMid.y`) because the hinge is a depth-axis movement invisible as a 2D angle from behind. Dynamic 65%/35% thresholds bootstrap counting; they lock to the avg of the first 3 reps' observed extremes.
- `RepCounter.extendedThreshold` for Squat is **150°** (not 160°) to accommodate real-world camera angles where lockout reads 145–158°.

### Pause-at-bottom tempo rounding

`RepMetric.tempoString` and `RepMetricsCollector.currentTempoString()` use **`.rounded(.down)` for the pause-bottom slot only** (the 2nd number). All other phases use nearest rounding. This prevents a 0.9 s touch-and-go from inflating to "1".

### Exercise library (current)

| Type | Analyzer | View | Notes |
|------|----------|------|-------|
| Squat | `SquatAnalyzer` | Side | Hip angle added to HUD (display-only) |
| Deadlift | `DeadliftAnalyzer` | Side | Film 15–30° off strict side to avoid bar-over-hip occlusion |
| Lunge | `LungeAnalyzer` | Side | Hip angle added to HUD (display-only) |
| Hip Hinge (Side) | `HipHingeSideAnalyzer` | Side | |
| Hip Hinge (Back) | `HipHingeBackAnalyzer` | Rear | Self-calibrating rep count & tempo |
| Barbell Row | `RowAnalyzer` | Side | Auto-side fallback |
| Lat Pulldown/Chin Up (Side) | `LatPulldownAnalyzer` | Side | |
| Lat Pulldown/Chin Up (Front) | `LatPulldownFrontAnalyzer` | Front/Back | Bilateral, no side select |
| Overhead Press | `OverheadPressAnalyzer` | Front/Back | Bilateral |
| Elbow (Bicep/Tricep) | `ElbowAnalyzer` | Side | |
| Shoulder Assessment | `ShoulderAnalyzer` | Front/Back | |

### Assessment library (current)

| Type | Planes | Notes |
|------|--------|-------|
| Shoulder Flexion | Frontal, Sagittal | |
| Squat Assessment | Frontal, Sagittal | Sagittal uses depth-aware lean grading (< 90° knee angle = more forgiving thresholds) |
| Hip Hinge Assessment | Frontal, Sagittal | |

## Changelog & product history

User-facing history lives in **[README.md — Changelog](README.md)**. Major milestones: on-device 2.0, live Metal + 3D + 1€ filter 2.1, exercise expansion 2.3, assessments + HUD 3.0, plane-aware assessments 3.2, video composition decode 3.3.2, stability + diagnostics 3.3.3–3.3.4, analyzer improvements 3.3.5–3.3.7.

## Related docs

| Document | Content |
|----------|---------|
| [README.md](README.md) | Full user/dev doc, architecture diagrams, how to add exercises/assessments |
| [docs/VideoOrientation.md](docs/VideoOrientation.md) | Saved-video decode — CI traps, composition solution, regression table |
| [docs/Troubleshooting.md](docs/Troubleshooting.md) | Open bugs / investigation checklist (e.g. assessment export overlays, exercise analyze crashes) |
| [docs/README.md](docs/README.md) | Index of `docs/` |
| [PRIVACY.md](PRIVACY.md) | Privacy policy text |
| [TESTFLIGHT_APPSTORE_NOTES.md](TESTFLIGHT_APPSTORE_NOTES.md) | Store / TestFlight copy |

Last updated: aligned with **KevLines 3.3.7** (marketing) / build **16** per `project.yml`.
