import SwiftUI

struct WorkoutHistoryView: View {
    @State private var workouts: [WorkoutResult] = []

    var body: some View {
        NavigationStack {
            Group {
                if workouts.isEmpty {
                    ContentUnavailableView(
                        "No Workouts Yet",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("Analyzed workouts will appear here.")
                    )
                } else {
                    List(workouts) { workout in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(workout.exerciseType.rawValue)
                                .font(.headline)
                            HStack {
                                Text("\(workout.totalReps) reps")
                                Spacer()
                                Text(workout.date, style: .date)
                                    .foregroundStyle(.secondary)
                            }
                            Text(String(format: "%.1fs", workout.duration))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("History")
        }
    }
}
