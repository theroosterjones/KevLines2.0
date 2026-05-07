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

## Changelog & product history

User-facing history lives in **[README.md — Changelog](README.md)**. Major milestones: on-device 2.0, live Metal + 3D + 1€ filter 2.1, exercise expansion 2.3, assessments + HUD 3.0, plane-aware assessments 3.2, **video composition decode 3.3.2**.

## Related docs

| Document | Content |
|----------|---------|
| [README.md](README.md) | Full user/dev doc, architecture diagrams, how to add exercises/assessments |
| [docs/VideoOrientation.md](docs/VideoOrientation.md) | Saved-video decode — CI traps, composition solution, regression table |
| [docs/Troubleshooting.md](docs/Troubleshooting.md) | Open bugs / investigation checklist (e.g. assessment export overlays, exercise analyze crashes) |
| [docs/README.md](docs/README.md) | Index of `docs/` |
| [PRIVACY.md](PRIVACY.md) | Privacy policy text |
| [TESTFLIGHT_APPSTORE_NOTES.md](TESTFLIGHT_APPSTORE_NOTES.md) | Store / TestFlight copy |

Last updated: aligned with **KevLines 3.3.2** (marketing) / build **9** per `project.yml`.
