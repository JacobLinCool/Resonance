import Foundation

@testable import Resonance

@MainActor
final class FakeMusicPlayerBackend: MusicPlayerBackend {
    struct CatalogSong: Equatable {
        let identifier: String
        let duration: TimeInterval?
    }

    var playbackTime: TimeInterval = 0
    var playbackStatus: MusicPlayerPlaybackStatus = .stopped
    var outputLatency: TimeInterval = 0
    var authorizationStatus: MusicPlayerAuthorizationStatus = .authorized
    var catalogPlaybackAllowed = true
    var catalog: [String: CatalogSong] = [:]
    var suspendedLoads: Set<String> = []
    var suspendNextPlay = false

    private(set) var loadRequests: [String] = []
    private(set) var queuedIdentifiers: [String] = []
    private(set) var prepareCallCount = 0
    private(set) var playCallCount = 0
    private(set) var stopCallCount = 0
    private(set) var playbackTimeAtPlay: TimeInterval?
    private(set) var wasPreparedWhenPlayed = false

    private var loadContinuations: [String: CheckedContinuation<CatalogSong?, Error>] = [:]
    private var playContinuation: CheckedContinuation<Void, Error>?

    var hasSuspendedPlay: Bool {
        playContinuation != nil
    }

    func requestAuthorization() async -> MusicPlayerAuthorizationStatus {
        authorizationStatus
    }

    func canPlayCatalogContent() async throws -> Bool {
        catalogPlaybackAllowed
    }

    func loadCatalogSong(identifier: String) async throws -> CatalogSong? {
        loadRequests.append(identifier)
        guard suspendedLoads.contains(identifier) else {
            return catalog[identifier]
        }

        return try await withCheckedThrowingContinuation { continuation in
            precondition(loadContinuations[identifier] == nil)
            loadContinuations[identifier] = continuation
        }
    }

    func duration(of song: CatalogSong) -> TimeInterval? {
        song.duration
    }

    func setQueue(_ song: CatalogSong) {
        queuedIdentifiers.append(song.identifier)
    }

    func prepareToPlay() async throws {
        prepareCallCount += 1
    }

    func play() async throws {
        playCallCount += 1
        playbackTimeAtPlay = playbackTime
        wasPreparedWhenPlayed = prepareCallCount > 0
        if suspendNextPlay {
            suspendNextPlay = false
            try await withCheckedThrowingContinuation { continuation in
                precondition(playContinuation == nil)
                playContinuation = continuation
            }
        }
        playbackStatus = .active
    }

    func stop() {
        stopCallCount += 1
        playbackStatus = .stopped
    }

    func resumeLoad(identifier: String, with song: CatalogSong?) {
        guard let continuation = loadContinuations.removeValue(forKey: identifier) else {
            preconditionFailure("No suspended load for \(identifier)")
        }
        continuation.resume(returning: song)
    }

    func resumePlay() {
        guard let continuation = playContinuation else {
            preconditionFailure("No suspended play")
        }
        playContinuation = nil
        continuation.resume()
    }
}
