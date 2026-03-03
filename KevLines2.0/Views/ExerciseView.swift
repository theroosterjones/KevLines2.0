import SwiftUI
import PhotosUI
import AVKit

struct ExerciseView: View {
    @StateObject private var processor = VideoProcessor()

    @State private var selectedExercise: ExerciseConfig = ExerciseConfig.all[0]
    @State private var selectedSide: BodySide = .left
    @State private var selectedVideoItem: PhotosPickerItem?
    @State private var selectedVideoURL: URL?
    @State private var analyzedVideoURL: URL?
    @State private var analysisSummary: AnalysisSummary?

    @State private var showingError = false
    @State private var errorMessage = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Exercise picker
                Picker("Exercise", selection: $selectedExercise.type) {
                    ForEach(ExerciseConfig.all, id: \.type) { config in
                        Text(config.displayName).tag(config.type)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                // Side picker
                Picker("Side", selection: $selectedSide) {
                    Text("Left").tag(BodySide.left)
                    Text("Right").tag(BodySide.right)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                // Video selection
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

                // Video preview
                if let url = selectedVideoURL {
                    VideoPlayer(player: AVPlayer(url: url))
                        .frame(height: 300)
                        .cornerRadius(12)
                        .padding(.horizontal)
                }

                // Analyze button
                if selectedVideoURL != nil {
                    Button {
                        Task { await analyzeVideo() }
                    } label: {
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
                            Label("Analyze Form", systemImage: "figure.run")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.green)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                        }
                    }
                    .disabled(processor.isProcessing)
                    .padding(.horizontal)
                }

                // Results
                if let summary = analysisSummary {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Results")
                            .font(.headline)
                        Text("Reps: \(summary.totalReps)")
                        Text("Duration: \(String(format: "%.1f", summary.duration))s")
                        for angle in summary.averageAngles {
                            Text("Avg \(angle.joint.rawValue): \(Int(angle.degrees))°")
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    .padding(.horizontal)
                }

                Spacer()
            }
            .navigationTitle("KevLines 2.0")
            .alert("Notice", isPresented: $showingError) {
                Button("OK") { }
            } message: {
                Text(errorMessage)
            }
            .onChange(of: selectedVideoItem) { _, newItem in
                Task { await loadVideo(from: newItem) }
            }
        }
    }

    // MARK: - Actions

    private func loadVideo(from item: PhotosPickerItem?) async {
        guard let item else { return }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { return }
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("input_video_\(UUID().uuidString).mov")
            try data.write(to: tempURL)
            await MainActor.run { selectedVideoURL = tempURL }
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
            await MainActor.run {
                analysisSummary = summary
                analyzedVideoURL = outputURL
            }
        } catch {
            await MainActor.run {
                errorMessage = "Analysis failed: \(error.localizedDescription)"
                showingError = true
            }
        }
    }
}
