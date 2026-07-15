// MusicKit's player types aren't Sendable-annotated; the concrete backend keeps
// every framework access on the main actor.
@preconcurrency import MusicKit
import CoreAudio
import Foundation

/// The main-actor boundary around MusicKit's catalog and application player.
/// Its associated song type keeps raw MusicKit values out of `MusicPlayer` and
/// lets tests use deterministic in-memory songs.
@MainActor
protocol MusicPlayerBackend: AnyObject {
    associatedtype CatalogSong

    var playbackTime: TimeInterval { get set }
    var playbackStatus: MusicPlayerPlaybackStatus { get }
    var outputLatency: TimeInterval { get throws }

    func requestAuthorization() async -> MusicPlayerAuthorizationStatus
    func canPlayCatalogContent() async throws -> Bool
    func loadCatalogSong(identifier: String) async throws -> CatalogSong?
    func duration(of song: CatalogSong) -> TimeInterval?
    func setQueue(_ song: CatalogSong)
    func prepareToPlay() async throws
    func play() async throws
    func stop()
}

@MainActor
final class MusicKitPlayerBackend: MusicPlayerBackend {
    private let player = ApplicationMusicPlayer.shared

    var playbackTime: TimeInterval {
        get { player.playbackTime }
        set { player.playbackTime = newValue }
    }

    var playbackStatus: MusicPlayerPlaybackStatus {
        switch player.state.playbackStatus {
        case .stopped:
            .stopped
        case .paused:
            .paused
        case .playing, .interrupted, .seekingForward, .seekingBackward:
            .active
        @unknown default:
            preconditionFailure("Unsupported MusicKit playback status")
        }
    }

    var outputLatency: TimeInterval {
        get throws {
            guard let device = try AudioHardwareSystem.shared.defaultOutputDevice else {
                throw MusicPlayerError.outputDeviceUnavailable
            }

            let streams = try device.streams
            let streamLatencies = try streams.compactMap { stream -> Int? in
                guard try stream.direction == .output, try stream.isActive else { return nil }
                return try stream.latency
            }
            guard
                let latency = OutputLatency.seconds(
                    sampleRate: try device.actualSampleRate,
                    deviceFrames: try device.outputLatency,
                    safetyOffsetFrames: try device.outputSafetyOffset,
                    bufferFrames: try device.bufferFrameSize,
                    streamLatencies: streamLatencies
                )
            else {
                throw MusicPlayerError.invalidOutputLatency
            }
            return latency
        }
    }

    func requestAuthorization() async -> MusicPlayerAuthorizationStatus {
        switch await MusicAuthorization.request() {
        case .authorized:
            .authorized
        case .denied:
            .denied
        case .restricted:
            .restricted
        case .notDetermined:
            .notDetermined
        @unknown default:
            .unavailable
        }
    }

    func canPlayCatalogContent() async throws -> Bool {
        try await MusicSubscription.current.canPlayCatalogContent
    }

    func loadCatalogSong(identifier: String) async throws -> Song? {
        let request = MusicCatalogResourceRequest<Song>(
            matching: \.id,
            equalTo: MusicItemID(identifier)
        )
        return try await request.response().items.first
    }

    func duration(of song: Song) -> TimeInterval? {
        song.duration
    }

    func setQueue(_ song: Song) {
        player.queue = [song]
    }

    func prepareToPlay() async throws {
        try await player.prepareToPlay()
    }

    func play() async throws {
        try await player.play()
    }

    func stop() {
        player.stop()
    }
}

struct LoadedCatalogSong {
    let duration: TimeInterval?
    let setQueue: @MainActor () -> Void
}

/// Erases only the backend's associated song type. All operations remain
/// main-actor isolated, and the loaded-song closure retains the exact backend
/// value that produced it.
@MainActor
final class AnyMusicPlayerBackend {
    private let playbackTimeGetter: @MainActor () -> TimeInterval
    private let playbackTimeSetter: @MainActor (TimeInterval) -> Void
    private let playbackStatusGetter: @MainActor () -> MusicPlayerPlaybackStatus
    private let outputLatencyGetter: @MainActor () throws -> TimeInterval
    private let requestAuthorizationAction: @MainActor () async -> MusicPlayerAuthorizationStatus
    private let canPlayCatalogContentAction: @MainActor () async throws -> Bool
    private let loadCatalogSongAction: @MainActor (String) async throws -> LoadedCatalogSong?
    private let prepareToPlayAction: @MainActor () async throws -> Void
    private let playAction: @MainActor () async throws -> Void
    private let stopAction: @MainActor () -> Void

    init<Backend: MusicPlayerBackend>(_ backend: Backend) {
        playbackTimeGetter = { backend.playbackTime }
        playbackTimeSetter = { backend.playbackTime = $0 }
        playbackStatusGetter = { backend.playbackStatus }
        outputLatencyGetter = { try backend.outputLatency }
        requestAuthorizationAction = { await backend.requestAuthorization() }
        canPlayCatalogContentAction = { try await backend.canPlayCatalogContent() }
        loadCatalogSongAction = { identifier in
            guard let song = try await backend.loadCatalogSong(identifier: identifier) else {
                return nil
            }
            let duration = backend.duration(of: song)
            return LoadedCatalogSong(duration: duration) {
                backend.setQueue(song)
            }
        }
        prepareToPlayAction = { try await backend.prepareToPlay() }
        playAction = { try await backend.play() }
        stopAction = { backend.stop() }
    }

    var playbackTime: TimeInterval {
        get { playbackTimeGetter() }
        set { playbackTimeSetter(newValue) }
    }

    var playbackStatus: MusicPlayerPlaybackStatus {
        playbackStatusGetter()
    }

    var outputLatency: TimeInterval {
        get throws { try outputLatencyGetter() }
    }

    func requestAuthorization() async -> MusicPlayerAuthorizationStatus {
        await requestAuthorizationAction()
    }

    func canPlayCatalogContent() async throws -> Bool {
        try await canPlayCatalogContentAction()
    }

    func loadCatalogSong(identifier: String) async throws -> LoadedCatalogSong? {
        try await loadCatalogSongAction(identifier)
    }

    func prepareToPlay() async throws {
        try await prepareToPlayAction()
    }

    func play() async throws {
        try await playAction()
    }

    func stop() {
        stopAction()
    }
}
