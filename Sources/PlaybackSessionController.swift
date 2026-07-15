import Foundation
import os

/// Owns one recognized track's bounded startup alignment, playback-end watch,
/// and manual adjustment lifecycle. It never performs continuous correction.
@MainActor
final class PlaybackSessionController {
    var onPlaybackEnded: (() -> Void)?
    var onFailure: ((Error) -> Void)?

    private let musicPlayer: any MusicPlaying
    private var match: Match?
    private var task: Task<Void, Never>?
    private var isPlaying = false
    private var isEditingAdjustment = false
    private var hasPendingAdjustment = false

    private let log = Logger(
        subsystem: AppIdentity.bundleIdentifier,
        category: "sync"
    )

    init(musicPlayer: any MusicPlaying) {
        self.musicPlayer = musicPlayer
    }

    func prepare(for match: Match) {
        task?.cancel()
        task = nil
        isPlaying = false
        hasPendingAdjustment = false
        self.match = match
    }

    func start() {
        guard let match else { return }
        isPlaying = true

        if hasPendingAdjustment {
            hasPendingAdjustment = false
            applyAdjustment(to: match)
        } else if isEditingAdjustment {
            startPlaybackWatcher()
        } else {
            startAlignmentAndPlaybackWatcher(for: match)
        }
    }

    /// Cancels an unfinished automatic correction while leaving playback and
    /// the lightweight end-of-track watcher running.
    func beginAdjustment() {
        isEditingAdjustment = true
        guard isPlaying else { return }
        startPlaybackWatcher()
    }

    /// Applies one seek if playback has started, or queues that one seek if
    /// MusicKit is still starting the prepared entry.
    func commitAdjustment() {
        isEditingAdjustment = false
        guard let match else { return }

        if isPlaying {
            applyAdjustment(to: match)
        } else {
            hasPendingAdjustment = true
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        match = nil
        isPlaying = false
        isEditingAdjustment = false
        hasPendingAdjustment = false
    }
}

private extension PlaybackSessionController {
    func startAlignmentAndPlaybackWatcher(for match: Match) {
        task?.cancel()
        task = Task { @MainActor [weak self] in
            await self?.alignPlaybackAtStartup(match)
            await self?.watchPlayback()
        }
    }

    /// Performs one bounded startup correction, then leaves playback alone.
    /// MusicKit exposes seeking but no inaudible rate trim, so repeatedly
    /// chasing small errors would sound like skipping. The microphone is
    /// already stopped, keeping crowd noise out of this measurement.
    func alignPlaybackAtStartup(_ match: Match) async {
        var correctionCount = 0

        for attempt in 0..<PlaybackSynchronization.maximumMeasurementAttempts {
            guard !Task.isCancelled, isPlaying else { return }
            guard !musicPlayer.hasEnded else {
                finishPlayback()
                return
            }

            guard let error = await measuredTimelineError(match) else {
                if attempt < PlaybackSynchronization.maximumMeasurementAttempts - 1 {
                    try? await Task.sleep(for: PlaybackSynchronization.unavailableRetryDelay)
                }
                continue
            }
            guard !Task.isCancelled, isPlaying else { return }

            log.info("player timeline error: \(Int((error * 1_000).rounded()), privacy: .public) ms")
            if abs(error) <= PlaybackSynchronization.targetTolerance {
                return
            }
            guard correctionCount < PlaybackSynchronization.maximumCorrectionCount else {
                log.info("startup correction limit reached; leaving playback uninterrupted")
                return
            }

            do {
                try musicPlayer.seek(to: musicPlayer.targetPosition(for: match))
                correctionCount += 1
            } catch {
                fail(error)
                return
            }

            try? await Task.sleep(for: PlaybackSynchronization.seekSettleDelay)
        }
    }

    func measuredTimelineError(_ match: Match) async -> TimeInterval? {
        var samples: [TimeInterval] = []
        samples.reserveCapacity(PlaybackSynchronization.sampleCount)

        for index in 0..<PlaybackSynchronization.sampleCount {
            let readStartedAt = ProcessInfo.processInfo.systemUptime
            let playbackTime = musicPlayer.playbackTime
            let readFinishedAt = ProcessInfo.processInfo.systemUptime
            if let playbackTime {
                let error = PlaybackSynchronization.timelineError(
                    match: match,
                    playbackTime: playbackTime,
                    playbackOffset: musicPlayer.synchronizationOffset,
                    readStartedAt: readStartedAt,
                    readFinishedAt: readFinishedAt
                )
                if let error {
                    samples.append(error)
                }
            }

            if index < PlaybackSynchronization.sampleCount - 1 {
                try? await Task.sleep(for: PlaybackSynchronization.sampleSpacing)
                guard !Task.isCancelled, isPlaying else { return nil }
            }
        }

        guard samples.count == PlaybackSynchronization.sampleCount else { return nil }
        return PlaybackSynchronization.median(of: samples)
    }

    func applyAdjustment(to match: Match) {
        task?.cancel()
        task = nil

        do {
            try musicPlayer.seek(to: musicPlayer.targetPosition(for: match))
            let milliseconds = Int((musicPlayer.userAdjustment * 1_000).rounded())
            log.info("manual sync adjustment committed: \(milliseconds, privacy: .public) ms")
            startPlaybackWatcher()
        } catch {
            fail(error)
        }
    }

    func startPlaybackWatcher() {
        task?.cancel()
        task = Task { @MainActor [weak self] in
            await self?.watchPlayback()
        }
    }

    func watchPlayback() async {
        while !Task.isCancelled, isPlaying {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, isPlaying else { return }
            if musicPlayer.hasEnded {
                finishPlayback()
                return
            }
        }
    }

    func finishPlayback() {
        isPlaying = false
        onPlaybackEnded?()
    }

    func fail(_ error: Error) {
        isPlaying = false
        onFailure?(error)
    }
}
