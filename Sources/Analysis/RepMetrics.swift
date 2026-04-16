import Foundation

/// Per-rep metrics capturing ROM peak and tempo phase durations.
struct RepMetric: Codable {
    let repNumber: Int
    let peakFlexionAngle: Float
    let eccentricDuration: Double
    let pauseBottomDuration: Double
    let concentricDuration: Double
    let pauseTopDuration: Double

    var totalDuration: Double {
        eccentricDuration + pauseBottomDuration + concentricDuration + pauseTopDuration
    }

    /// Formatted tempo string (e.g. "3-1-2-1")
    var tempoString: String {
        "\(Int(eccentricDuration.rounded()))-\(Int(pauseBottomDuration.rounded()))-\(Int(concentricDuration.rounded()))-\(Int(pauseTopDuration.rounded()))"
    }
}

/// Collects per-rep metrics from frame-by-frame analysis output.
/// Feed each frame's phase, primary angle, rep count, and timestamp. When a rep completes
/// (repCount increments), the collector finalises phase durations and peak angle for that rep.
final class RepMetricsCollector {

    private(set) var completedReps: [RepMetric] = []

    private var lastRepCount = 0
    private var currentPeakAngle: Float = .greatestFiniteMagnitude
    private var phaseAccumulators: [TempoPhase: Double] = [:]
    private var currentPhase: TempoPhase?
    private var phaseStartTime: Double?
    private var lastTimestamp: Double?

    /// Call once per frame with the current analysis output.
    func update(phase: TempoPhase?, angle: Float, repCount: Int, timestamp: Double) {
        // Track phase durations
        if let phase, phase != currentPhase {
            finalizeCurrentPhase(at: timestamp)
            currentPhase = phase
            phaseStartTime = timestamp
        }

        // Track peak flexion (minimum angle = deepest point)
        currentPeakAngle = min(currentPeakAngle, angle)

        // Rep just completed — finalize metrics
        if repCount > lastRepCount {
            finalizeCurrentPhase(at: timestamp)

            let metric = RepMetric(
                repNumber: repCount,
                peakFlexionAngle: currentPeakAngle,
                eccentricDuration: phaseAccumulators[.eccentric, default: 0],
                pauseBottomDuration: phaseAccumulators[.pauseBottom, default: 0],
                concentricDuration: phaseAccumulators[.concentric, default: 0],
                pauseTopDuration: phaseAccumulators[.pauseTop, default: 0]
            )
            completedReps.append(metric)

            // Reset for next rep
            currentPeakAngle = .greatestFiniteMagnitude
            phaseAccumulators = [:]
            lastRepCount = repCount
        }

        lastTimestamp = timestamp
    }

    /// Current in-progress tempo (durations so far for the rep being recorded).
    func currentTempo() -> (ecc: Double, pauseB: Double, con: Double, pauseT: Double)? {
        guard currentPhase != nil else { return nil }
        var accum = phaseAccumulators
        // Include time in the current phase up to now
        if let phase = currentPhase, let start = phaseStartTime, let last = lastTimestamp {
            accum[phase, default: 0] += max(0, last - start)
        }
        return (
            ecc: accum[.eccentric, default: 0],
            pauseB: accum[.pauseBottom, default: 0],
            con: accum[.concentric, default: 0],
            pauseT: accum[.pauseTop, default: 0]
        )
    }

    /// Current in-progress tempo as a formatted string (e.g. "3-1-2-0").
    func currentTempoString() -> String {
        guard let t = currentTempo() else { return "--" }
        return "\(Int(t.ecc.rounded()))-\(Int(t.pauseB.rounded()))-\(Int(t.con.rounded()))-\(Int(t.pauseT.rounded()))"
    }

    // MARK: - Scoring

    /// Exercise consistency score (0--100). Nil if fewer than 3 completed reps.
    func computeScore() -> Int? {
        guard completedReps.count >= 3 else { return nil }

        let romScore = romConsistencyScore()
        let tempoScore = tempoConsistencyScore()
        return max(0, min(100, Int((0.6 * Double(romScore) + 0.4 * Double(tempoScore)).rounded())))
    }

    func reset() {
        completedReps.removeAll()
        lastRepCount = 0
        currentPeakAngle = .greatestFiniteMagnitude
        phaseAccumulators = [:]
        currentPhase = nil
        phaseStartTime = nil
        lastTimestamp = nil
    }

    // MARK: - Private

    private func finalizeCurrentPhase(at timestamp: Double) {
        guard let phase = currentPhase, let start = phaseStartTime else { return }
        phaseAccumulators[phase, default: 0] += max(0, timestamp - start)
    }

    /// ROM consistency: 100 - 5 * stddev(peak angles). Lower variance = better.
    private func romConsistencyScore() -> Int {
        let peaks = completedReps.map { $0.peakFlexionAngle }
        let sd = stddev(peaks)
        return max(0, Int((100.0 - 5.0 * Double(sd)).rounded()))
    }

    /// Tempo consistency: 100 - 50 * avg(stddev of each phase duration). Lower variance = better.
    private func tempoConsistencyScore() -> Int {
        let eccSD = stddev(completedReps.map { Float($0.eccentricDuration) })
        let pbSD  = stddev(completedReps.map { Float($0.pauseBottomDuration) })
        let conSD = stddev(completedReps.map { Float($0.concentricDuration) })
        let ptSD  = stddev(completedReps.map { Float($0.pauseTopDuration) })
        let avgSD = Double(eccSD + pbSD + conSD + ptSD) / 4.0
        return max(0, Int((100.0 - 50.0 * avgSD).rounded()))
    }

    private func stddev(_ values: [Float]) -> Float {
        guard values.count > 1 else { return 0 }
        let n = Float(values.count)
        let mean = values.reduce(0, +) / n
        let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / n
        return sqrt(variance)
    }
}
