import Foundation
import os

/// Timing and tolerance policy for follow-the-room mode. Tests inject short
/// intervals; production uses the defaults.
struct FollowRoomPolicy: Sendable {
    /// Pause between probes while playback runs.
    var probeInterval: Duration = .seconds(25)
    /// How long one probe keeps the microphone open waiting for a match.
    var probeWindow: Duration = .seconds(12)
    /// Poll spacing inside the probe window and the follow loop.
    var tickInterval: Duration = .seconds(1)
    /// A probe also starts this close to the end of the current track, so the
    /// next song is caught without a silent gap.
    var endOfTrackLead: TimeInterval = 12
    /// Same-song probe corrections below this timeline error are ignored;
    /// seeking for tiny errors would be more audible than the drift.
    var driftTolerance: TimeInterval = 0.35
}

/// Follow-the-room: while a synced song plays into headphones, the microphone
/// still hears the room. Short periodic probes re-run recognition so a changed
/// song switches playback and a drifted one is corrected — without Re-sync.
extension AppCoordinator {
    /// Starts or stops the follow loop to match `followRoomEnabled`. Only
    /// meaningful while playing; every other state tears the loop down through
    /// `cancelPlaybackWork`.
    func restartFollowLoop() {
        followTask?.cancel()
        followTask = nil
        endProbeCapture()
        guard followRoomEnabled, state == .playing else { return }

        followTask = Task { @MainActor [weak self] in
            await self?.runFollowLoop()
        }
    }

    private func runFollowLoop() async {
        var untilNextProbe = followPolicy.probeInterval
        while !Task.isCancelled, state == .playing {
            try? await Task.sleep(for: followPolicy.tickInterval)
            guard !Task.isCancelled, state == .playing else { return }

            untilNextProbe -= followPolicy.tickInterval
            if untilNextProbe <= .zero || isNearTrackEnd {
                await runProbe()
                guard !Task.isCancelled, state == .playing else { return }
                untilNextProbe = followPolicy.probeInterval
            }
        }
    }

    private var isNearTrackEnd: Bool {
        guard let duration = musicPlayer.playbackDuration,
            let time = musicPlayer.playbackTime
        else { return false }
        return duration - time <= followPolicy.endOfTrackLead
    }

    /// Opens the microphone for one bounded window. A match arrives through
    /// the regular recognizer callback and lands in `handleProbeMatch`.
    private func runProbe() async {
        guard state == .playing, !isProbing else { return }

        recognizer.reset()
        beginLevelUpdates()
        do {
            try audio.start()
        } catch {
            // A probe that can't open the microphone is skipped, not fatal.
            return
        }
        isProbing = true

        let clock = ContinuousClock()
        let deadline = clock.now + followPolicy.probeWindow
        while !Task.isCancelled, isProbing, state == .playing, clock.now < deadline {
            try? await Task.sleep(for: followPolicy.tickInterval)
        }
        endProbeCapture()
    }

    /// Closes the probe's capture without touching playback. Safe to call
    /// redundantly; only an open probe reacts.
    func endProbeCapture() {
        guard isProbing else { return }
        isProbing = false
        invalidateListeningGeneration()
        audio.stop()
        recognizer.reset()
        isStreamingToRecognizer = false
        level = -80
    }

    func handleProbeMatch(_ match: Match) {
        guard state == .playing, isProbing else { return }

        if let currentID = matchedSong?.appleMusicID, match.song.appleMusicID == currentID {
            endProbeCapture()
            history.record(match.song)
            correctDriftIfNeeded(with: match)
            return
        }

        guard match.song.appleMusicID != nil else {
            // The room moved to something the catalog can't play; keep the
            // current track rather than stopping the music.
            endProbeCapture()
            history.record(match.song)
            return
        }

        endProbeCapture()
        followTask?.cancel()
        followTask = nil
        playTask?.cancel()
        playTask = nil
        playbackSession.stop()
        musicPlayer.stop()
        setError(nil)
        startPlayback(for: match)
    }

    /// Adopts the fresh recognition as the new timeline reference and applies
    /// at most one corrective seek when the measured error is worth hearing.
    private func correctDriftIfNeeded(with match: Match) {
        let target = musicPlayer.targetPosition(for: match)
        guard let playbackTime = musicPlayer.playbackTime,
            abs(target - playbackTime) > followPolicy.driftTolerance
        else {
            playbackSession.adoptFreshMatch(match, correcting: false)
            return
        }
        playbackSession.adoptFreshMatch(match, correcting: true)
    }
}
