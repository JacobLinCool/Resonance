import Foundation

/// Pure synchronization math shared by the runtime controller and its tests.
/// All timestamps use the system monotonic clock, so wall-clock changes cannot
/// move either timeline.
enum PlaybackSynchronization {
    /// Fixed acoustic head start applied before device latency and user trim.
    static let defaultPlaybackOffset: TimeInterval = 0.200
    static let targetTolerance: TimeInterval = 0.030
    static let sampleCount = 3
    static let maximumMeasurementAttempts = 3
    static let maximumCorrectionCount = 1
    static let sampleSpacing = Duration.milliseconds(40)
    static let unavailableRetryDelay = Duration.milliseconds(100)
    static let seekSettleDelay = Duration.milliseconds(220)

    static func timelineError(
        match: Match,
        playbackTime: TimeInterval,
        playbackOffset: TimeInterval,
        readStartedAt: TimeInterval,
        readFinishedAt: TimeInterval
    ) -> TimeInterval? {
        guard playbackTime.isFinite,
            playbackTime >= 0,
            playbackOffset.isFinite,
            readStartedAt.isFinite,
            readFinishedAt.isFinite,
            readFinishedAt >= readStartedAt
        else { return nil }

        let sampledAt = readStartedAt + (readFinishedAt - readStartedAt) / 2
        let target = max(0, match.currentOffset(atUptime: sampledAt) + playbackOffset)
        let error = target - playbackTime
        return error.isFinite ? error : nil
    }

    static func median(of samples: [TimeInterval]) -> TimeInterval? {
        guard !samples.isEmpty, samples.allSatisfy(\.isFinite) else { return nil }

        let sorted = samples.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }
}
