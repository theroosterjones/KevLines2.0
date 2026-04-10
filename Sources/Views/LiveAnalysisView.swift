import SwiftUI
import MetalKit
import AVKit
import UIKit
import os.log

private let logger = Logger(subsystem: "com.kevinjones.KevLines2-0", category: "LiveAnalysisView")

// MARK: - Live Analysis ViewModel

/// Owns the camera service, pose landmarker, and analyzer for the live pipeline.
/// Heavy processing runs on the camera's serial capture queue; UI state is dispatched to main.
final class LiveAnalysisViewModel: ObservableObject {

    @Published private(set) var currentInstructions: [OverlayInstruction] = []
    @Published private(set) var repCount: Int = 0
    @Published private(set) var currentPhase: TempoPhase?
    @Published private(set) var isRecording = false
    @Published private(set) var isAuthorized = false
    @Published private(set) var trackingWarningVisible = false
    @Published private(set) var cameraPosition: AVCaptureDevice.Position = .back

    let metalRenderer = MetalCameraRenderer()

    private let cameraService = CameraService()
    // Separate PoseLandmarkerService instance for live use (fresh timestamp sequence)
    private let poseLandmarker = PoseLandmarkerService()
    private let overlayRenderer = OverlayRenderer()

    private var _analyzer: ExerciseAnalyzer?
    private var _recorder: LiveVideoRecorder?
    private let recorderLock = NSLock()
    private var lowTrackingStreak = 0

    init() {
        cameraService.onFrame = { [weak self] pixelBuffer, time in
            self?.processFrame(pixelBuffer: pixelBuffer, time: time)
        }
    }

    // MARK: - Public Interface (called from main thread)

    func setAnalyzer(_ analyzer: ExerciseAnalyzer) {
        _analyzer?.reset()
        _analyzer = analyzer
        lowTrackingStreak = 0
        DispatchQueue.main.async { self.trackingWarningVisible = false }
    }

    func checkAuthorization() async {
        await cameraService.checkAndRequestAuthorization()
        await MainActor.run { isAuthorized = cameraService.isAuthorized }
    }

    func start(position: AVCaptureDevice.Position = .back) {
        cameraService.configure(position: position)
        cameraService.start()
    }

    func stop() {
        cameraService.stop()
    }

    func switchCamera() {
        let newPosition: AVCaptureDevice.Position = (cameraPosition == .back) ? .front : .back
        cameraPosition = newPosition
        cameraService.configure(position: newPosition)
    }

    func startRecording() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("live_\(UUID().uuidString).mp4")
        do {
            let rec = try LiveVideoRecorder(
                outputURL: url,
                width: cameraService.captureWidth,
                height: cameraService.captureHeight
            )
            recorderLock.withLock { _recorder = rec }
            DispatchQueue.main.async { self.isRecording = true }
        } catch {
            logger.error("Failed to start recorder: \(error.localizedDescription)")
        }
    }

    func stopRecording() async -> URL? {
        let rec: LiveVideoRecorder? = recorderLock.withLock {
            let r = _recorder
            _recorder = nil
            return r
        }
        DispatchQueue.main.async { self.isRecording = false }
        guard let rec else { return nil }
        return try? await rec.finalize()
    }

    // MARK: - Frame Processing (runs on camera capture queue)

    private func processFrame(pixelBuffer: CVPixelBuffer, time: CMTime) {
        let timestampMs = Int(CMTimeGetSeconds(time) * 1000)

        let poseResult = poseLandmarker.detect(pixelBuffer: pixelBuffer, timestampMs: timestampMs)

        let frameAnalysis: FrameAnalysis
        if let poseResult, let analyzer = _analyzer {
            frameAnalysis = analyzer.analyze(landmarks: poseResult)
        } else {
            frameAnalysis = .empty
        }

        // Recording path: apply overlay to a copy, write to file
        let rec: LiveVideoRecorder? = recorderLock.withLock { _recorder }
        if let rec, let copy = clonePixelBuffer(pixelBuffer) {
            overlayRenderer.render(instructions: frameAnalysis.overlayInstructions, onto: copy)
            rec.append(pixelBuffer: copy, at: time)
        }

        // Display path: push raw frame to Metal; SwiftUI Canvas draws overlay
        metalRenderer.update(pixelBuffer: pixelBuffer)

        let instructions = frameAnalysis.overlayInstructions
        let reps         = frameAnalysis.repCount
        let phase        = frameAnalysis.tempoPhase
        let hasTracking = poseResult != nil && !instructions.isEmpty

        if hasTracking {
            lowTrackingStreak = 0
        } else {
            lowTrackingStreak += 1
        }
        let shouldShowTrackingWarning = lowTrackingStreak >= 20

        DispatchQueue.main.async { [weak self] in
            self?.currentInstructions = instructions
            self?.repCount = reps
            self?.currentPhase = phase
            self?.trackingWarningVisible = shouldShowTrackingWarning
        }
    }

    // MARK: - Pixel Buffer Clone

    private func clonePixelBuffer(_ src: CVPixelBuffer) -> CVPixelBuffer? {
        let w = CVPixelBufferGetWidth(src)
        let h = CVPixelBufferGetHeight(src)
        let fmt = CVPixelBufferGetPixelFormatType(src)
        var dst: CVPixelBuffer?
        guard CVPixelBufferCreate(nil, w, h, fmt, nil, &dst) == kCVReturnSuccess,
              let dst else { return nil }

        CVPixelBufferLockBaseAddress(src, .readOnly)
        CVPixelBufferLockBaseAddress(dst, [])
        defer {
            CVPixelBufferUnlockBaseAddress(src, .readOnly)
            CVPixelBufferUnlockBaseAddress(dst, [])
        }
        if let s = CVPixelBufferGetBaseAddress(src),
           let d = CVPixelBufferGetBaseAddress(dst) {
            memcpy(d, s, CVPixelBufferGetDataSize(src))
        }
        return dst
    }
}

// MARK: - Metal Camera View (UIViewRepresentable)

struct MetalCameraView: UIViewRepresentable {
    let renderer: MetalCameraRenderer

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView()
        view.backgroundColor = .black
        renderer.setup(view: view)
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {}
}

// MARK: - Overlay Canvas (SwiftUI Canvas drawing OverlayInstructions)

extension OverlayColor {
    var swiftUIColor: Color {
        let (r, g, b, a) = rgba
        return Color(red: Double(r), green: Double(g), blue: Double(b), opacity: Double(a))
    }
}

struct OverlayCanvas: View {
    let instructions: [OverlayInstruction]

    var body: some View {
        Canvas { context, size in
            for instruction in instructions {
                draw(instruction, in: context, size: size)
            }
        }
        .allowsHitTesting(false)
    }

    private func draw(_ instruction: OverlayInstruction,
                      in context: GraphicsContext,
                      size: CGSize) {
        switch instruction {

        case let .line(from, to, color, width):
            var path = Path()
            path.move(to: point(from, size))
            path.addLine(to: point(to, size))
            context.stroke(path, with: .color(color.swiftUIColor), lineWidth: CGFloat(width))

        case let .extendedLine(from, through, color, width):
            // Extend from 'from' through 'through' to frame boundary
            let p1 = point(from, size)
            let p2 = point(through, size)
            let dx = p2.x - p1.x
            let dy = p2.y - p1.y
            let len = sqrt(dx * dx + dy * dy)
            guard len > 0.5 else { break }
            let scale = max(size.width, size.height) * 2
            let end = CGPoint(x: p2.x + dx / len * scale, y: p2.y + dy / len * scale)
            var path = Path()
            path.move(to: p2)
            path.addLine(to: end)
            context.stroke(path, with: .color(color.swiftUIColor), lineWidth: CGFloat(width))

        case let .circle(at, radius, color, filled):
            let center = point(at, size)
            let r = CGFloat(radius)
            let rect = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
            if filled {
                context.fill(Path(ellipseIn: rect), with: .color(color.swiftUIColor))
            } else {
                context.stroke(Path(ellipseIn: rect), with: .color(color.swiftUIColor),
                               lineWidth: 2)
            }

        case let .text(str, at, color, fontSize):
            let pos = point(at, size)
            context.draw(
                Text(str)
                    .font(.system(size: CGFloat(fontSize), weight: .bold, design: .monospaced))
                    .foregroundStyle(color.swiftUIColor),
                at: pos,
                anchor: .topLeading
            )
        }
    }

    private func point(_ normalized: SIMD2<Float>, _ size: CGSize) -> CGPoint {
        CGPoint(x: CGFloat(normalized.x) * size.width,
                y: CGFloat(normalized.y) * size.height)
    }
}

// MARK: - Live Analysis View

struct LiveAnalysisView: View {

    @StateObject private var viewModel = LiveAnalysisViewModel()

    @State private var selectedExerciseType: ExerciseType = .squat
    @State private var selectedSide: BodySide = .left
    @State private var showPermissionAlert = false
    @State private var savedVideoURL: URL?
    @State private var showShareSheet = false

    private var selectedExercise: ExerciseConfig {
        ExerciseConfig.all.first { $0.type == selectedExerciseType } ?? ExerciseConfig.all[0]
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Metal camera feed (full screen)
            MetalCameraView(renderer: viewModel.metalRenderer)
                .ignoresSafeArea()

            // Skeleton overlay drawn via SwiftUI Canvas
            OverlayCanvas(instructions: viewModel.currentInstructions)
                .ignoresSafeArea()

            // HUD controls
            VStack(spacing: 0) {
                topBar
                Spacer()
                trackingWarningBanner
                bottomBar
            }
        }
        .navigationTitle("Live Analysis")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { setup() }
        .onDisappear { viewModel.stop() }
        .alert("Camera Access Required", isPresented: $showPermissionAlert) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Allow camera access in Settings to use live form analysis.")
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = savedVideoURL { ShareSheet(items: [url]) }
        }
        .onChange(of: selectedExerciseType) { _, _ in reconfigure() }
        .onChange(of: selectedSide)         { _, _ in reconfigure() }
    }

    // MARK: - Sub-views

    private var topBar: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Picker("Exercise", selection: $selectedExerciseType) {
                    ForEach(ExerciseType.allCases) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .pickerStyle(.menu)
                .tint(.white)
                .frame(maxWidth: .infinity, alignment: .leading)

                if selectedExercise.requiresSideSelection {
                    Picker("Side", selection: $selectedSide) {
                        Text("Left").tag(BodySide.left)
                        Text("Right").tag(BodySide.right)
                    }
                    .pickerStyle(.segmented)
                }

                if !viewModel.isRecording {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Before recording")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(selectedExerciseType.cameraSetupTip)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 2)
                }
            }

            Button {
                viewModel.switchCamera()
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath.camera.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(12)
                    .background(.white.opacity(0.25))
                    .clipShape(Circle())
            }
            .accessibilityLabel(viewModel.cameraPosition == .back ? "Switch to front camera" : "Switch to back camera")
        }
        .padding()
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private var trackingWarningBanner: some View {
        if viewModel.trackingWarningVisible {
            Text(selectedExerciseType.lowTrackingWarning)
                .font(.caption.weight(.medium))
                .foregroundStyle(.black)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.yellow.opacity(0.9))
                .clipShape(Capsule())
                .padding(.bottom, 8)
        }
    }

    private var bottomBar: some View {
        HStack(alignment: .center) {
            // Rep counter
            VStack(alignment: .leading, spacing: 2) {
                Text("REPS")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("\(viewModel.repCount)")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .frame(minWidth: 80, alignment: .leading)

            Spacer()

            // Record / Stop button
            Button {
                Task { await toggleRecording() }
            } label: {
                ZStack {
                    Circle()
                        .strokeBorder(.white, lineWidth: 3)
                        .frame(width: 72, height: 72)
                    if viewModel.isRecording {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(.red)
                            .frame(width: 26, height: 26)
                    } else {
                        Circle()
                            .fill(.red)
                            .frame(width: 54, height: 54)
                    }
                }
            }

            Spacer()

            // Tempo phase
            VStack(alignment: .trailing, spacing: 2) {
                Text("PHASE")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(viewModel.currentPhase?.rawValue.capitalized ?? "—")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.cyan)
                    .multilineTextAlignment(.trailing)
            }
            .frame(minWidth: 80, alignment: .trailing)
        }
        .padding()
        .background(.ultraThinMaterial)
    }

    // MARK: - Actions

    private func setup() {
        Task {
            await viewModel.checkAuthorization()
            guard viewModel.isAuthorized else {
                showPermissionAlert = true
                return
            }
            reconfigure()
            viewModel.start()
        }
    }

    private func reconfigure() {
        let analyzer = selectedExercise.makeAnalyzer(side: selectedSide)
        viewModel.setAnalyzer(analyzer)
    }

    private func toggleRecording() async {
        if viewModel.isRecording {
            if let url = await viewModel.stopRecording() {
                savedVideoURL = url
                showShareSheet = true
            }
        } else {
            viewModel.startRecording()
        }
    }
}
