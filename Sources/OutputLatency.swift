import Foundation

/// Converts Core Audio's frame-based output pipeline into the amount of media
/// time playback must lead by for the corresponding samples to reach the user.
enum OutputLatency {
    static func seconds(
        sampleRate: Double,
        deviceFrames: Int,
        safetyOffsetFrames: Int,
        bufferFrames: Int,
        streamLatencies: [Int]
    ) -> TimeInterval? {
        let frameCounts = [deviceFrames, safetyOffsetFrames, bufferFrames] + streamLatencies
        guard sampleRate.isFinite,
            sampleRate > 0,
            frameCounts.allSatisfy({ $0 >= 0 })
        else { return nil }

        let streamFrames = streamLatencies.max() ?? 0
        let totalFrames =
            Double(deviceFrames) + Double(safetyOffsetFrames) + Double(bufferFrames)
            + Double(streamFrames)
        let latency = totalFrames / sampleRate
        return latency.isFinite ? latency : nil
    }
}
