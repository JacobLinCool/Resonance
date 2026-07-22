import AVFoundation
import Foundation
import Observation

/// Where the user can fix an error Resonance can't fix by itself. The UI
/// renders this as an "Open System Settings" action next to the message.
enum ErrorRecovery: Sendable, Equatable {
    case microphonePrivacy
    case mediaPrivacy

    var settingsURL: URL {
        switch self {
        case .microphonePrivacy: AppLinks.microphonePrivacySettings
        case .mediaPrivacy: AppLinks.mediaPrivacySettings
        }
    }
}

/// Owns the main-actor state machine and coordinates microphone capture,
/// recognition, and Apple Music playback.
///
/// Collaborators and internal state are deliberately non-private: same-module
/// extensions in `AppCoordinator+FollowRoom.swift` and
/// `AppCoordinator+Adjustment.swift` implement the probe loop and the
/// device-aware sync adjustment on top of them.
@MainActor
@Observable
final class AppCoordinator {
    // MARK: - Observable UI state

    private(set) var state: SyncState = .disabled
    /// Setters are internal, not private: the probe extension in
    /// `AppCoordinator+FollowRoom.swift` resets them when a capture ends.
    var level: Float = -80
    var isStreamingToRecognizer = false
    private(set) var isAuthorizing = false
    /// True while the follow-the-room probe briefly reopens the microphone
    /// during playback.
    var isProbing = false
    private(set) var matchedSong: RecognizedSong?
    private(set) var lastError: String?
    private(set) var lastErrorRecovery: ErrorRecovery?

    /// Recognition history, newest first, shared with the history window.
    let history: MatchHistoryStore

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

    /// Keeps listening to the room during playback so song changes and drift
    /// are corrected without pressing Re-sync.
    var followRoomEnabled = false {
        didSet {
            guard followRoomEnabled != oldValue else { return }
            settings.set(followRoomEnabled, forKey: Self.followRoomKey)
            if state == .playing {
                restartFollowLoop()
            }
        }
    }

    /// Posts a notification when a match starts playing.
    var matchNotificationsEnabled = true {
        didSet {
            guard matchNotificationsEnabled != oldValue else { return }
            settings.set(matchNotificationsEnabled, forKey: Self.matchNotificationsKey)
        }
    }

    // MARK: - Collaborators and tasks

    @ObservationIgnored let audio: any AudioMonitoring
    @ObservationIgnored let recognizer: any RecognitionServing
    @ObservationIgnored let musicPlayer: any MusicPlaying
    @ObservationIgnored let playbackSession: PlaybackSessionController
    @ObservationIgnored let notifier: any MatchNotifying
    @ObservationIgnored let deviceObserver: any OutputDeviceObserving
    @ObservationIgnored let followPolicy: FollowRoomPolicy
    @ObservationIgnored let settings: UserDefaults
    @ObservationIgnored private let requestMicrophoneAccess: @Sendable () async -> Bool

    @ObservationIgnored private var authorizationTask: Task<Void, Never>?
    @ObservationIgnored var playTask: Task<Void, Never>?
    @ObservationIgnored var followTask: Task<Void, Never>?
    @ObservationIgnored var listeningGeneration: UInt = 0
    @ObservationIgnored var currentDeviceUID: String?

    static let thresholdKey = "thresholdDB"
    static let thresholdRange = -60.0...0.0
    static let syncAdjustmentKey = "syncAdjustmentMilliseconds"
    static let syncAdjustmentByDeviceKey = "syncAdjustmentMillisecondsByDevice"
    static let followRoomKey = "followRoomEnabled"
    static let matchNotificationsKey = "matchNotificationsEnabled"
    static let syncAdjustmentRange = -500.0...500.0

    static func isValidSyncAdjustment(_ milliseconds: Double) -> Bool {
        milliseconds.isFinite && syncAdjustmentRange.contains(milliseconds)
    }

    convenience init() {
        self.init(
            audio: AudioMonitor(),
            recognizer: ShazamRecognizer(),
            musicPlayer: MusicPlayer(),
            requestMicrophoneAccess: {
                await AVCaptureDevice.requestAccess(for: .audio)
            },
            notifier: UserNotificationMatchNotifier(),
            deviceObserver: OutputDeviceObserver()
        )
    }

    init(
        audio: any AudioMonitoring,
        recognizer: any RecognitionServing,
        musicPlayer: any MusicPlaying,
        requestMicrophoneAccess: @escaping @Sendable () async -> Bool,
        settings: UserDefaults = .standard,
        notifier: (any MatchNotifying)? = nil,
        deviceObserver: (any OutputDeviceObserving)? = nil,
        followPolicy: FollowRoomPolicy = FollowRoomPolicy()
    ) {
        self.audio = audio
        self.recognizer = recognizer
        self.musicPlayer = musicPlayer
        playbackSession = PlaybackSessionController(musicPlayer: musicPlayer)
        self.requestMicrophoneAccess = requestMicrophoneAccess
        self.settings = settings
        self.notifier = notifier ?? NullMatchNotifier()
        self.deviceObserver = deviceObserver ?? NullOutputDeviceObserver()
        self.followPolicy = followPolicy
        history = MatchHistoryStore(settings: settings)

        let storedThreshold = settings.object(forKey: Self.thresholdKey) as? Double
        if let storedThreshold, storedThreshold.isFinite && Self.thresholdRange.contains(storedThreshold) {
            thresholdDB = storedThreshold
        }
        audio.thresholdDB = Float(thresholdDB)

        followRoomEnabled = settings.object(forKey: Self.followRoomKey) as? Bool ?? false
        matchNotificationsEnabled =
            settings.object(forKey: Self.matchNotificationsKey) as? Bool ?? true

        currentDeviceUID = self.deviceObserver.currentDevice?.uid
        if let storedSyncAdjustment = initialSyncAdjustment() {
            syncAdjustmentMilliseconds = storedSyncAdjustment
        }
        musicPlayer.userAdjustment = syncAdjustmentMilliseconds / 1_000

        playbackSession.onPlaybackEnded = { [weak self] in
            self?.resumeListening()
        }
        playbackSession.onFailure = { [weak self] error in
            self?.setError(
                String(localized: "\(error.localizedDescription) Listening again."),
                recovery: Self.recovery(for: error)
            )
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
        self.deviceObserver.onDefaultDeviceChange = { [weak self] device in
            self?.handleDefaultOutputDeviceChange(device)
        }
        self.deviceObserver.start()
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
}

extension AppCoordinator {
    // MARK: - Errors

    func setError(_ message: String?, recovery: ErrorRecovery? = nil) {
        lastError = message
        lastErrorRecovery = message == nil ? nil : recovery
    }

    static func recovery(for error: Error) -> ErrorRecovery? {
        guard let playerError = error as? MusicPlayerError else { return nil }
        return playerError == .authorizationDenied ? .mediaPrivacy : nil
    }
}

private extension AppCoordinator {
    func enable() {
        guard state == .disabled, authorizationTask == nil else { return }

        setError(nil)
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
                self.setError(
                    String(
                        localized: """
                            Microphone access was denied. \
                            Enable it in System Settings › Privacy & Security › Microphone.
                            """
                    ),
                    recovery: .microphonePrivacy
                )
                return
            }

            do {
                try await self.musicPlayer.prepareForPlayback()
                guard !Task.isCancelled, self.state == .disabled else { return }
                self.startListening()
            } catch is CancellationError {
                return
            } catch {
                self.setError(error.localizedDescription, recovery: Self.recovery(for: error))
            }
        }
    }

    func disable() {
        enterDisabled(error: nil)
    }
}

extension AppCoordinator {
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
        setError(error)
    }

    // MARK: - Active (listening and recognizing)

    func startListening() {
        cancelPlaybackWork()
        matchedSong = nil
        isStreamingToRecognizer = false
        level = -80
        recognizer.reset()
        beginLevelUpdates()

        do {
            try audio.start()
            state = .active
        } catch {
            setError(
                String(localized: "Couldn't start the microphone: \(error.localizedDescription)")
            )
            state = .disabled
        }
    }

    /// Rotates the listening generation and points the level meter at it, so
    /// callbacks from a previous capture session are ignored.
    func beginLevelUpdates() {
        invalidateListeningGeneration()
        let generation = listeningGeneration
        audio.onLevel = { [weak self] level, isStreaming in
            Task { @MainActor in
                self?.handleLevel(level, isStreaming: isStreaming, generation: generation)
            }
        }
    }

    func handleLevel(_ level: Float, isStreaming: Bool, generation: UInt) {
        guard state == .active || isProbing, generation == listeningGeneration else { return }

        self.level = level
        if isStreaming != isStreamingToRecognizer {
            isStreamingToRecognizer = isStreaming
        }
    }

    func handleMatch(_ match: Match) {
        if isProbing {
            handleProbeMatch(match)
            return
        }
        guard state == .active, playTask == nil else { return }

        setError(nil)
        stopCapture()

        guard match.song.appleMusicID != nil else {
            matchedSong = match.song
            history.record(match.song)
            setError(
                String(
                    localized: "This song isn't available in the Apple Music catalog. Listening again."
                )
            )
            startListening()
            return
        }

        startPlayback(for: match)
    }

    /// Shared entry into the `startingPlayback` phase, used by both the
    /// listening flow and the follow-the-room song switch.
    func startPlayback(for match: Match) {
        matchedSong = match.song
        history.record(match.song)
        if matchNotificationsEnabled {
            notifier.notifyMatch(match.song)
        }
        playbackSession.prepare(for: match)
        state = .startingPlayback
        playTask = Task { @MainActor [weak self] in
            await self?.playMatch(match)
        }
    }

    func stopCapture() {
        invalidateListeningGeneration()
        audio.stop()
        recognizer.reset()
        isStreamingToRecognizer = false
        level = -80
    }

    func handleRecognitionError(_ message: String) {
        if isProbing {
            // A failed probe must not tear down ongoing playback; the next
            // probe simply tries again.
            endProbeCapture()
            return
        }
        guard state == .active else { return }
        enterDisabled(error: String(localized: "Recognition failed: \(message)"))
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
            setError(
                String(localized: "\(error.localizedDescription) Listening again."),
                recovery: Self.recovery(for: error)
            )
            startListening()
        }
    }

    // MARK: - Playing and synchronization

    func enterPlaying() {
        state = .playing
        playbackSession.start()
        restartFollowLoop()
    }

    func resumeListening() {
        musicPlayer.stop()
        matchedSong = nil
        startListening()
    }

    func cancelPlaybackWork() {
        playTask?.cancel()
        playTask = nil
        followTask?.cancel()
        followTask = nil
        endProbeCapture()
        playbackSession.stop()
    }

    func invalidateListeningGeneration() {
        listeningGeneration &+= 1
    }
}
