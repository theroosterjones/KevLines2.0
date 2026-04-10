import SwiftUI
import PhotosUI
import AVKit
import os.log

private let logger = Logger(subsystem: "com.kevinjones.KevLines2-0", category: "ExerciseView")

/// Transferable wrapper so PhotosPicker can hand us a video file URL.
struct PickedMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let dest = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(received.file.pathExtension)
            try FileManager.default.copyItem(at: received.file, to: dest)
            return Self(url: dest)
        }
    }
}

private enum AnalysisMode: String, CaseIterable {
    case savedVideo  = "Saved Video"
    case liveCamera  = "Live Camera"
}

struct ExerciseView: View {
    @StateObject private var processor = VideoProcessor()

    @State private var analysisMode: AnalysisMode = .savedVideo
    @State private var selectedExerciseType: ExerciseType = .squat
    @State private var selectedSide: BodySide = .left
    @State private var selectedVideoItem: PhotosPickerItem?
    @State private var selectedVideoURL: URL?
    @State private var analyzedVideoURL: URL?
    @State private var analysisSummary: AnalysisSummary?
    @State private var player: AVPlayer?
    @State private var isLoadingSelectedVideo = false

    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var showingShareSheet = false

    private var selectedExercise: ExerciseConfig {
        ExerciseConfig.all.first { $0.type == selectedExerciseType } ?? ExerciseConfig.all[0]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    modePicker

                    if analysisMode == .savedVideo {
                        exercisePicker
                        cameraSetupTipCard
                        sidePicker
                        videoPickerButton
                        loadingVideoSection
                        videoPreview
                        analyzeSection
                        resultsSection
                        exportSection
                    } else {
                        liveCameraButton
                    }
                }
                .padding(.bottom, 40)
            }
            .navigationTitle("KevLines 2.0")
            .alert("Error", isPresented: $showingError) {
                Button("OK") { }
            } message: {
                Text(errorMessage)
            }
            .sheet(isPresented: $showingShareSheet) {
                if let url = analyzedVideoURL {
                    ShareSheet(items: [url])
                }
            }
            .onChange(of: selectedVideoItem) { _, newItem in
                Task { await loadVideo(from: newItem) }
            }
        }
    }

    // MARK: - Subviews

    private var modePicker: some View {
        Picker("Mode", selection: $analysisMode) {
            ForEach(AnalysisMode.allCases, id: \.self) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private var liveCameraButton: some View {
        NavigationLink(destination: LiveAnalysisView()) {
            Label("Start Live Analysis", systemImage: "camera.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.indigo)
                .foregroundColor(.white)
                .cornerRadius(12)
        }
        .padding(.horizontal)
    }

    private var exercisePicker: some View {
        Picker("Exercise", selection: $selectedExerciseType) {
            ForEach(ExerciseType.allCases) { type in
                Text(type.rawValue).tag(type)
            }
        }
        .pickerStyle(.menu)
        .padding(.horizontal)
    }

    @ViewBuilder
    private var cameraSetupTipCard: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "camera.aperture")
                .foregroundStyle(.indigo)
            VStack(alignment: .leading, spacing: 4) {
                Text("Camera setup tip")
                    .font(.subheadline.weight(.semibold))
                Text(selectedExerciseType.cameraSetupTip)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .padding(.horizontal)
    }

    @ViewBuilder
    private var sidePicker: some View {
        if selectedExercise.requiresSideSelection {
            Picker("Side", selection: $selectedSide) {
                Text("Left").tag(BodySide.left)
                Text("Right").tag(BodySide.right)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
        }
    }

    private var videoPickerButton: some View {
        PhotosPicker(
            selection: $selectedVideoItem,
            matching: .videos
        ) {
            Label("Select Video", systemImage: "video.badge.plus")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(12)
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private var loadingVideoSection: some View {
        if isLoadingSelectedVideo {
            HStack(spacing: 10) {
                ProgressView()
                Text("Loading video...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
            .padding(.horizontal)
        }
    }

    @ViewBuilder
    private var videoPreview: some View {
        if let player {
            VideoPlayer(player: player)
                .frame(height: 300)
                .cornerRadius(12)
                .padding(.horizontal)
        }
    }

    @ViewBuilder
    private var analyzeSection: some View {
        if selectedVideoURL != nil {
            Button {
                Task { await analyzeVideo() }
            } label: {
                analyzeButtonLabel
            }
            .disabled(processor.isProcessing)
            .padding(.horizontal)
        }
    }

    @ViewBuilder
    private var analyzeButtonLabel: some View {
        if processor.isProcessing {
            VStack(spacing: 8) {
                ProgressView(value: processor.progress)
                Text("Analyzing... \(Int(processor.progress * 100))%")
                    .font(.caption)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.gray.opacity(0.3))
            .cornerRadius(12)
        } else {
            Label(analyzedVideoURL != nil ? "Re-Analyze" : "Analyze Form",
                  systemImage: "figure.run")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.green)
                .foregroundColor(.white)
                .cornerRadius(12)
        }
    }

    @ViewBuilder
    private var resultsSection: some View {
        if let summary = analysisSummary {
            VStack(alignment: .leading, spacing: 8) {
                Text("Results")
                    .font(.headline)

                if selectedExerciseType == .shoulderAssessment {
                    // Shoulder assessment: show tilt interpretation instead of rep count
                    if let tilt = summary.averageAngles.first(where: { $0.joint == .shoulder }) {
                        let absTilt = abs(tilt.degrees)
                        let side = tilt.degrees >= 0 ? "Left" : "Right"
                        Text("\(side) shoulder elevated  \(String(format: "%.1f", absTilt))° avg")
                    }
                } else {
                    Text("Reps: \(summary.totalReps)")
                }

                Text("Duration: \(String(format: "%.1f", summary.duration))s")

                ForEach(summary.averageAngles, id: \.joint) { angle in
                    if selectedExerciseType == .shoulderAssessment, angle.joint == .shoulder {
                        // Already shown above in interpreted form; skip raw line
                    } else {
                        Text("Avg \(angle.joint.rawValue): \(Int(angle.degrees))\u{00B0}")
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
            .padding(.horizontal)
        }
    }

    @ViewBuilder
    private var exportSection: some View {
        if analyzedVideoURL != nil {
            Button {
                showingShareSheet = true
            } label: {
                Label("Export Analyzed Video", systemImage: "square.and.arrow.up")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.orange)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Actions

    private func loadVideo(from item: PhotosPickerItem?) async {
        await MainActor.run {
            isLoadingSelectedVideo = true
            // Clear previous selection/results so state reflects current loading operation.
            selectedVideoURL = nil
            analyzedVideoURL = nil
            analysisSummary = nil
            player = nil
        }

        guard let item else {
            await MainActor.run { isLoadingSelectedVideo = false }
            return
        }

        defer {
            Task { @MainActor in
                isLoadingSelectedVideo = false
            }
        }

        do {
            guard let movie = try await item.loadTransferable(type: PickedMovie.self) else {
                await MainActor.run {
                    errorMessage = "Could not load video from Photos."
                    showingError = true
                }
                return
            }
            await MainActor.run {
                selectedVideoURL = movie.url
                analyzedVideoURL = nil
                analysisSummary = nil
                player = AVPlayer(url: movie.url)
            }
        } catch {
            await MainActor.run {
                errorMessage = "Failed to load video: \(error.localizedDescription)"
                showingError = true
            }
        }
    }

    private func analyzeVideo() async {
        guard let inputURL = selectedVideoURL else { return }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("analyzed_\(UUID().uuidString).mp4")

        let analyzer = selectedExercise.makeAnalyzer(side: selectedSide)

        do {
            let summary = try await processor.process(
                inputURL: inputURL,
                outputURL: outputURL,
                analyzer: analyzer
            )

            let outputAsset = AVURLAsset(url: outputURL)
            let outputDuration = CMTimeGetSeconds(outputAsset.duration)
            logger.info("Output video duration: \(outputDuration)s at \(outputURL.lastPathComponent)")

            await MainActor.run {
                analysisSummary = summary
                analyzedVideoURL = outputURL
                player = AVPlayer(url: outputURL)
            }
        } catch {
            await MainActor.run {
                errorMessage = "Analysis failed: \(error.localizedDescription)"
                showingError = true
            }
        }
    }
}

/// UIKit share sheet wrapper for exporting the analyzed video.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
