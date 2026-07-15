import Foundation
import ShazamKit

/// The four top-level states the app can be in.
///
/// - `disabled`: The app does nothing. No microphone, no timers, no work.
/// - `active`:   The microphone is monitored. Recognition only runs while the
///               measured loudness rises above the configured threshold.
/// - `startingPlayback`: A match has stopped recognition while MusicKit prepares
///               the catalog track.
/// - `playing`:  Resonance is streaming the recognized track at the synchronized
///               position. Microphone monitoring and recognition are paused.
enum SyncState: Sendable, Equatable {
    case disabled
    case active
    case startingPlayback
    case playing
}

/// A song identified by ShazamKit, reduced to the fields the app needs.
struct RecognizedSong: Sendable, Equatable {
    let title: String
    let artist: String?
    /// Apple Music catalog identifier, used to fetch and play the track with
    /// MusicKit. Nil when ShazamKit couldn't map the match to the catalog.
    let appleMusicID: String?

    init?(from item: SHMatchedMediaItem) {
        guard let title = item.title?.trimmedNonempty else { return nil }

        self.title = title
        self.artist = item.artist?.trimmedNonempty
        self.appleMusicID = item.appleMusicID?.trimmedNonempty
    }

    init(title: String, artist: String?, appleMusicID: String?) {
        self.title = title
        self.artist = artist
        self.appleMusicID = appleMusicID
    }
}

/// A recognition result plus everything needed to seek playback to the live
/// position — expressed entirely in `Sendable` values so it crosses actor
/// boundaries cleanly.
///
/// `referenceOffset` is the matched position captured on the recognizer's
/// background queue; adding elapsed monotonic time reconstructs the current
/// position at the moment we seek (equivalent to reading
/// `predictedCurrentMatchOffset`, but without holding the non-Sendable item).
struct Match: Sendable {
    let song: RecognizedSong
    let referenceOffset: TimeInterval
    let referencePlaybackRate: Double
    let capturedAtUptime: TimeInterval

    init?(item: SHMatchedMediaItem) {
        let referenceOffset = item.predictedCurrentMatchOffset
        let referencePlaybackRate = 1 + Double(item.frequencySkew)
        guard let song = RecognizedSong(from: item),
            referenceOffset.isFinite,
            referencePlaybackRate.isFinite,
            referencePlaybackRate > 0
        else { return nil }

        self.song = song
        self.referenceOffset = max(0, referenceOffset)
        self.referencePlaybackRate = referencePlaybackRate
        self.capturedAtUptime = ProcessInfo.processInfo.systemUptime
    }

    init(
        song: RecognizedSong,
        referenceOffset: TimeInterval,
        referencePlaybackRate: Double = 1,
        capturedAtUptime: TimeInterval
    ) {
        precondition(referenceOffset.isFinite)
        precondition(referencePlaybackRate.isFinite && referencePlaybackRate > 0)
        precondition(capturedAtUptime.isFinite)

        self.song = song
        self.referenceOffset = max(0, referenceOffset)
        self.referencePlaybackRate = referencePlaybackRate
        self.capturedAtUptime = capturedAtUptime
    }

    /// The position the recognized audio has reached right now.
    var currentOffset: TimeInterval {
        currentOffset(atUptime: ProcessInfo.processInfo.systemUptime)
    }

    func currentOffset(atUptime uptime: TimeInterval) -> TimeInterval {
        referenceOffset + max(0, uptime - capturedAtUptime) * referencePlaybackRate
    }
}

private extension String {
    var trimmedNonempty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
