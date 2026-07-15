import AVFoundation
import Foundation
import Observation

/// Owns the main-actor state machine and coordinates microphone capture,
/// recognition, and Apple Music playback.
@MainActor
@Observable
final class AppCoordinator {
    // MARK: - Observable UI state

    private(set) var state: SyncState = .disabled
    private(set) var level: Float = -80
    private(set) var isStreamingToRecognizer = false
    private(set) var isAuthorizing = false
    private(set) var matchedSong: RecognizedSong?
    private(set) var lastError: String?

    /// Loudness gate in dBFS, persisted across launches.
    var thresholdDB: Double = -50 {
        didSet {
            guard thresholdDB.isFinite, Self.thresholdRange.contains(thresholdDB) else {
                thresholdDB = oldValue
                return
            }
            settings.set(thresholdDB, forKey: Self.thresholdKey)
            audio.thresholdDB = Float(thresholdDB)
        }
    }

    /// Signed playback trim shown by the UI. The value remains a preview while
    /// the slider is moving and is committed when editing ends.
    var syncAdjustmentMilliseconds: Double = 0 {
        didSet {
            guard syncAdjustmentMilliseconds.isFinite,
                Self.syncAdjustmentRange.contains(syncAdjustmentMilliseconds)
            else {
                syncAdjustmentMilliseconds = oldValue
                return
            }
        }
    }

    // MARK: - Collaborators and tasks

    @ObservationIgnored private let audio: any AudioMonitoring
    @ObservationIgnored private let recognizer: any RecognitionServing
    @ObservationIgnored private let musicPlayer: any MusicPlaying
    @ObservationIgnored private let playbackSession: PlaybackSessionController
    @ObservationIgnored private let requestMicrophoneAccess: @Sendable () async -> Bool
    @ObservationIgnored private let settings: UserDefaults

    @ObservationIgnored private var authorizationTask: Task<Void, Never>?
    @ObservationIgnored private var playTask: Task<Void, Never>?
    @ObservationIgnored private var listeningGeneration: UInt = 0

    private static let thresholdKey = "thresholdDB"
    private static let thresholdRange = -60.0...0.0
    private static let syncAdjustmentKey = "syncAdjustmentMilliseconds"
    static let syncAdjustmentRange = -500.0...500.0

    private static func isValidSyncAdjustment(_ milliseconds: Double) -> Bool {
        milliseconds.isFinite && syncAdjustmentRange.contains(milliseconds)
    }

    convenience init() {
        self.init(
            audio: AudioMonitor(),
            recognizer: ShazamRecognizer(),
            musicPlayer: MusicPlayer(),
            requestMicrophoneAccess: {
                await AVCaptureDevice.requestAccess(for: .audio)
            }
        )
    }

    init(
        audio: any AudioMonitoring,
        recognizer: any RecognitionServing,
        musicPlayer: any MusicPlaying,
        requestMicrophoneAccess: @escaping @Sendable () async -> Bool,
        settings: UserDefaults = .standard
    ) {
        self.audio = audio
        self.recognizer = recognizer
        self.musicPlayer = musicPlayer
        playbackSession = PlaybackSessionController(musicPlayer: musicPlayer)
        self.requestMicrophoneAccess = requestMicrophoneAccess
        self.settings = settings

        let storedThreshold = settings.object(forKey: Self.thresholdKey) as? Double
        if let storedThreshold, storedThreshold.isFinite && Self.thresholdRange.contains(storedThreshold) {
            thresholdDB = storedThreshold
        }
        audio.thresholdDB = Float(thresholdDB)

        let storedSyncAdjustment =
            settings.object(forKey: Self.syncAdjustmentKey) as? Double
        if let storedSyncAdjustment, Self.isValidSyncAdjustment(storedSyncAdjustment) {
            syncAdjustmentMilliseconds = storedSyncAdjustment
        }
        musicPlayer.userAdjustment = syncAdjustmentMilliseconds / 1_000

        playbackSession.onPlaybackEnded = { [weak self] in
            self?.resumeListening()
        }
        playbackSession.onFailure = { [weak self] error in
            self?.lastError = "\(error.localizedDescription) Listening again."
            self?.resumeListening()
        }

        audio.onGatedBuffer = { [recognizer] buffer, time in
            recognizer.match(buffer: buffer, at: time)
        }
        self.recognizer.onMatch = { [weak self] match in
            self?.handleMatch(match)
        }
        self.recognizer.onError = { [weak self] message in
            self?.handleRecognitionError(message)
        }
    }
}

extension AppCoordinator {
    // MARK: - Main control

    func toggle() {
        if state == .disabled {
            enable()
        } else {
            disable()
        }
    }

    func resync() {
        guard state == .playing else { return }
        resumeListening()
    }

    /// Stops the bounded automatic startup correction before the user takes
    /// control. Playback continues uninterrupted while the slider is moving.
    func beginSyncAdjustment() {
        playbackSession.beginAdjustment()
    }

    /// Persists the preview and, during playback, performs exactly one seek.
    func commitSyncAdjustment() {
        settings.set(syncAdjustmentMilliseconds, forKey: Self.syncAdjustmentKey)
        musicPlayer.userAdjustment = syncAdjustmentMilliseconds / 1_000
        playbackSession.commitAdjustment()
    }

    func resetSyncAdjustment() {
        beginSyncAdjustment()
        syncAdjustmentMilliseconds = 0
        commitSyncAdjustment()
    }
}

private extension AppCoordinator {
    func enable() {
        guard state == .disabled, authorizationTask == nil else { return }

        lastError = nil
        isAuthorizing = true
        authorizationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.authorizationTask = nil
                self.isAuthorizing = false
            }

            let microphoneGranted = await self.requestMicrophoneAccess()
            guard !Task.isCancelled, self.state == .disabled else { return }
            guard microphoneGranted else {
                self.lastError =
                    "Microphone access was denied. Enable it in System Settings › Privacy & Security › Microphone."
                return
            }

            do {
                try await self.musicPlayer.prepareForPlayback()
                guard !Task.isCancelled, self.state == .disabled else { return }
                self.startListening()
            } catch is CancellationError {
                return
            } catch {
                self.lastError = error.localizedDescription
            }
        }
    }

    func disable() {
        enterDisabled(error: nil)
    }

    func enterDisabled(error: String?) {
        authorizationTask?.cancel()
        authorizationTask = nil
        isAuthorizing = false
        cancelPlaybackWork()
        invalidateListeningGeneration()
        audio.stop()
        recognizer.reset()
        musicPlayer.stop()

        state = .disabled
        isStreamingToRecognizer = false
        matchedSong = nil
        level = -80
        lastError = error
    }

    // MARK: - Active (listening and recognizing)

    func startListening() {
        cancelPlaybackWork()
        matchedSong = nil
        isStreamingToRecognizer = false
        level = -80
        recognizer.reset()

        invalidateListeningGeneration()
        let generation = listeningGeneration
        audio.onLevel = { [weak self] level, isStreaming in
            Task { @MainActor in
                self?.handleLevel(level, isStreaming: isStreaming, generation: generation)
            }
        }

        do {
            try audio.start()
            state = .active
        } catch {
            lastError = "Couldn't start the microphone: \(error.localizedDescription)"
            state = .disabled
        }
    }

    func handleLevel(_ level: Float, isStreaming: Bool, generation: UInt) {
        guard state == .active, generation == listeningGeneration else { return }

        self.level = level
        if isStreaming != isStreamingToRecognizer {
            isStreamingToRecognizer = isStreaming
        }
    }

    func handleMatch(_ match: Match) {
        guard state == .active, playTask == nil else { return }

        lastError = nil
        invalidateListeningGeneration()
        audio.stop()
        recognizer.reset()
        isStreamingToRecognizer = false
        level = -80
        matchedSong = match.song

        guard match.song.appleMusicID != nil else {
            lastError = "This song isn't available in the Apple Music catalog. Listening again."
            startListening()
            return
        }

        playbackSession.prepare(for: match)
        state = .startingPlayback
        playTask = Task { @MainActor [weak self] in
            await self?.playMatch(match)
        }
    }

    func handleRecognitionError(_ message: String) {
        guard state == .active else { return }
        enterDisabled(error: "Recognition failed: \(message)")
    }

    // MARK: - Playback startup

    func playMatch(_ match: Match) async {
        do {
            try await musicPlayer.play(match)
            guard !Task.isCancelled, state == .startingPlayback else { return }

            playTask = nil
            enterPlaying()
        } catch is CancellationError {
            return
        } catch {
            guard state == .startingPlayback else { return }

            playTask = nil
            lastError = "\(error.localizedDescription) Listening again."
            startListening()
        }
    }

    // MARK: - Playing and synchronization

    func enterPlaying() {
        state = .playing
        playbackSession.start()
    }

    func resumeListening() {
        musicPlayer.stop()
        matchedSong = nil
        startListening()
    }

    func cancelPlaybackWork() {
        playTask?.cancel()
        playTask = nil
        playbackSession.stop()
    }

    func invalidateListeningGeneration() {
        listeningGeneration &+= 1
    }
}

extension AppCoordinator {
    // MARK: - Presentation

    var menuBarSymbol: String {
        switch state {
        case .disabled:
            "waveform.slash"
        case .active:
            "waveform"
        case .startingPlayback:
            "music.note.list"
        case .playing:
            "music.note"
        }
    }
}
