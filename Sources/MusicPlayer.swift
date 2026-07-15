import Foundation
import os

enum MusicPlayerError: LocalizedError, Equatable {
    case authorizationDenied
    case authorizationRestricted
    case subscriptionRequired
    case serviceUnavailable
    case missingCatalogID
    case songUnavailable
    case outputDeviceUnavailable
    case invalidOutputLatency
    case invalidPlaybackPosition
    case playbackFailed

    var errorDescription: String? {
        switch self {
        case .authorizationDenied:
            "Apple Music access was denied. Enable it in System Settings › Privacy & Security › Media & Apple Music."
        case .authorizationRestricted:
            "Apple Music access is restricted for this account."
        case .subscriptionRequired:
            "An active Apple Music subscription is required for playback."
        case .serviceUnavailable:
            "Apple Music is unavailable. Check your connection and the app's code signing."
        case .missingCatalogID:
            "The recognized song has no Apple Music catalog track."
        case .songUnavailable:
            "This song is unavailable in your Apple Music storefront."
        case .outputDeviceUnavailable:
            "No audio output device is available."
        case .invalidOutputLatency:
            "The current audio output did not report a usable latency."
        case .invalidPlaybackPosition:
            "Apple Music returned an invalid playback position."
        case .playbackFailed:
            "Apple Music couldn't start playback."
        }
    }
}

enum MusicPlayerAuthorizationStatus: Sendable, Equatable {
    case authorized
    case denied
    case restricted
    case notDetermined
    case unavailable
}

enum MusicPlayerPlaybackStatus: Sendable, Equatable {
    case stopped
    case paused
    case active
}

/// App-facing playback contract. The coordinator depends on this interface;
/// `MusicPlayerBackend` remains the lower-level MusicKit boundary.
@MainActor
protocol MusicPlaying: AnyObject {
    var playbackTime: TimeInterval? { get }
    var userAdjustment: TimeInterval { get set }
    var synchronizationOffset: TimeInterval { get }
    var hasEnded: Bool { get }

    func prepareForPlayback() async throws
    func play(_ match: Match) async throws
    func targetPosition(for match: Match) -> TimeInterval
    func seek(to time: TimeInterval) throws
    func stop()
}

/// Main-actor wrapper around MusicKit's application-scoped player.
@MainActor
final class MusicPlayer: MusicPlaying {
    private struct Startup {
        let id: UUID
        let task: Task<Void, Error>
    }

    private let backend: AnyMusicPlayerBackend
    private var startup: Startup?
    private var currentSongDuration: TimeInterval?
    private var outputLatency: TimeInterval = 0
    private var storedUserAdjustment: TimeInterval = 0

    private let log = Logger(subsystem: AppIdentity.bundleIdentifier, category: "music")

    init() {
        backend = AnyMusicPlayerBackend(MusicKitPlayerBackend())
    }

    init<Backend: MusicPlayerBackend>(backend: Backend) {
        self.backend = AnyMusicPlayerBackend(backend)
    }

    /// A finite current position, or nil while MusicKit reports an invalid or
    /// indefinite CMTime.
    var playbackTime: TimeInterval? {
        let time = backend.playbackTime
        return time.isFinite && time >= 0 ? time : nil
    }

    var hasEnded: Bool {
        switch backend.playbackStatus {
        case .stopped, .paused:
            true
        case .active:
            false
        }
    }

    /// A signed, user-selected trim added to the output device compensation.
    /// Positive values advance playback; negative values move it back.
    var userAdjustment: TimeInterval {
        get { storedUserAdjustment }
        set {
            precondition(newValue.isFinite)
            storedUserAdjustment = newValue
        }
    }

    var synchronizationOffset: TimeInterval {
        PlaybackSynchronization.defaultPlaybackOffset + outputLatency + userAdjustment
    }

    func targetPosition(for match: Match) -> TimeInterval {
        max(0, match.currentOffset + synchronizationOffset)
    }

    /// Verifies authorization and catalog-playback eligibility before listening
    /// begins, so a recognized match never leads to a known-dead playback path.
    func prepareForPlayback() async throws {
        switch await backend.requestAuthorization() {
        case .authorized:
            break
        case .denied:
            throw MusicPlayerError.authorizationDenied
        case .restricted:
            throw MusicPlayerError.authorizationRestricted
        case .notDetermined, .unavailable:
            throw MusicPlayerError.serviceUnavailable
        }

        try Task.checkCancellation()

        do {
            let canPlayCatalogContent = try await backend.canPlayCatalogContent()
            try Task.checkCancellation()
            guard canPlayCatalogContent else {
                throw MusicPlayerError.subscriptionRequired
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as MusicPlayerError {
            throw error
        } catch {
            log.error("subscription check failed: \(error.localizedDescription)")
            throw MusicPlayerError.serviceUnavailable
        }
    }

    /// Serializes playback startups. A new attempt first drains any cancelled
    /// request, preventing an old `play()` continuation from changing the shared
    /// player after a newer song has been queued.
    func play(_ match: Match) async throws {
        await drainStartup()
        try Task.checkCancellation()

        let id = UUID()
        let task = Task { @MainActor [weak self] in
            guard let self else { throw CancellationError() }
            try await self.performPlay(match)
        }
        startup = Startup(id: id, task: task)

        do {
            try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
            }
            try Task.checkCancellation()
            if startup?.id == id {
                startup = nil
            }
        } catch {
            task.cancel()
            if startup?.id == id {
                startup = nil
                backend.stop()
                currentSongDuration = nil
            }
            throw error
        }
    }

    func seek(to time: TimeInterval) throws {
        guard isValidPosition(time) else {
            throw MusicPlayerError.invalidPlaybackPosition
        }
        backend.playbackTime = time
    }

    func stop() {
        startup?.task.cancel()
        backend.stop()
        currentSongDuration = nil
        outputLatency = 0
    }

    private func performPlay(_ match: Match) async throws {
        guard let appleMusicID = match.song.appleMusicID else {
            throw MusicPlayerError.missingCatalogID
        }

        do {
            let song = try await backend.loadCatalogSong(identifier: appleMusicID)
            try Task.checkCancellation()
            guard let song else {
                throw MusicPlayerError.songUnavailable
            }

            currentSongDuration = song.duration
            song.setQueue()
            try await backend.prepareToPlay()
            try Task.checkCancellation()

            let outputLatency = try backend.outputLatency
            guard outputLatency.isFinite, outputLatency >= 0 else {
                throw MusicPlayerError.invalidOutputLatency
            }
            self.outputLatency = outputLatency
            log.info(
                "output latency compensation: \(Int((outputLatency * 1_000).rounded()), privacy: .public) ms"
            )

            // Position the prepared entry before playback begins so listeners
            // do not hear the large catch-up seek caused by catalog startup.
            let preparedTarget = targetPosition(for: match)
            guard isValidPosition(preparedTarget) else {
                throw MusicPlayerError.invalidPlaybackPosition
            }
            backend.playbackTime = preparedTarget

            try await backend.play()
            try Task.checkCancellation()
            let target = targetPosition(for: match)
            guard isValidPosition(target) else {
                throw MusicPlayerError.invalidPlaybackPosition
            }
            backend.playbackTime = target
        } catch is CancellationError {
            backend.stop()
            currentSongDuration = nil
            outputLatency = 0
            throw CancellationError()
        } catch let error as MusicPlayerError {
            backend.stop()
            currentSongDuration = nil
            outputLatency = 0
            throw error
        } catch {
            backend.stop()
            currentSongDuration = nil
            outputLatency = 0
            log.error("playback startup failed: \(error.localizedDescription)")
            throw MusicPlayerError.playbackFailed
        }
    }

    private func drainStartup() async {
        guard let startup else { return }

        startup.task.cancel()
        backend.stop()
        _ = try? await startup.task.value
        backend.stop()
        currentSongDuration = nil
        outputLatency = 0
        if self.startup?.id == startup.id {
            self.startup = nil
        }
    }

    private func isValidPosition(_ time: TimeInterval) -> Bool {
        guard time.isFinite, time >= 0 else { return false }
        guard let currentSongDuration else { return true }
        guard currentSongDuration.isFinite, currentSongDuration >= 0 else { return false }
        return time <= currentSongDuration
    }
}
