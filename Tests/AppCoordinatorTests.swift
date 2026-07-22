import AVFoundation
import Foundation
import os
import XCTest

@testable import Resonance

@MainActor
final class AppCoordinatorTests: XCTestCase {
    func testSuccessfulAuthorizationStartsListening() async {
        let fixture = makeFixture()

        fixture.coordinator.toggle()
        await waitUntil { fixture.coordinator.state == .active }

        XCTAssertFalse(fixture.coordinator.isAuthorizing)
        XCTAssertEqual(fixture.audio.startCount, 1)
        XCTAssertEqual(fixture.music.prepareCount, 1)
        XCTAssertNil(fixture.coordinator.lastError)

        fixture.coordinator.toggle()
    }

    func testDeniedMicrophoneAccessNeverStartsListening() async {
        let fixture = makeFixture(microphoneGranted: false)

        fixture.coordinator.toggle()
        await waitUntil { !fixture.coordinator.isAuthorizing }

        XCTAssertEqual(fixture.coordinator.state, .disabled)
        XCTAssertEqual(fixture.audio.startCount, 0)
        XCTAssertEqual(fixture.music.prepareCount, 0)
        XCTAssertNotNil(fixture.coordinator.lastError)
    }

    func testRecognitionFailureWhileListeningStopsEveryService() async {
        let fixture = makeFixture()
        fixture.coordinator.toggle()
        await waitUntil { fixture.coordinator.state == .active }

        fixture.recognizer.emitFailure("network unavailable")

        XCTAssertEqual(fixture.coordinator.state, .disabled)
        XCTAssertEqual(fixture.audio.stopCount, 1)
        XCTAssertGreaterThanOrEqual(fixture.recognizer.resetCount, 2)
        XCTAssertEqual(fixture.music.stopCount, 1)
        XCTAssertEqual(
            fixture.coordinator.lastError,
            String(localized: "Recognition failed: \("network unavailable")")
        )
    }

    func testLateRecognitionFailureCannotInterruptPlaybackStartup() async {
        let gate = AsyncGate()
        let fixture = makeFixture(playGate: gate)
        fixture.coordinator.toggle()
        await waitUntil { fixture.coordinator.state == .active }

        fixture.recognizer.emitMatch(match())
        await waitUntil { fixture.coordinator.state == .startingPlayback && fixture.music.playCount == 1 }

        fixture.recognizer.emitFailure("late callback")
        XCTAssertEqual(fixture.coordinator.state, .startingPlayback)
        XCTAssertNil(fixture.coordinator.lastError)

        await gate.open()
        await waitUntil { fixture.coordinator.state == .playing }
        XCTAssertEqual(fixture.music.playCount, 1)

        fixture.coordinator.toggle()
    }

    func testOnlyFirstMatchCanStartPlayback() async {
        let gate = AsyncGate()
        let fixture = makeFixture(playGate: gate)
        fixture.coordinator.toggle()
        await waitUntil { fixture.coordinator.state == .active }

        fixture.recognizer.emitMatch(match(identifier: "first"))
        fixture.recognizer.emitMatch(match(identifier: "second"))
        await waitUntil { fixture.music.playCount == 1 }

        XCTAssertEqual(fixture.coordinator.state, .startingPlayback)
        XCTAssertEqual(fixture.music.playedIdentifiers, ["first"])

        await gate.open()
        await waitUntil { fixture.coordinator.state == .playing }
        fixture.coordinator.toggle()
    }

    func testDisableDuringPlaybackStartupCancelsAndRollsBack() async {
        let gate = AsyncGate()
        let fixture = makeFixture(playGate: gate)
        fixture.coordinator.toggle()
        await waitUntil { fixture.coordinator.state == .active }

        fixture.recognizer.emitMatch(match())
        await waitUntil { fixture.coordinator.state == .startingPlayback && fixture.music.playCount == 1 }

        fixture.coordinator.toggle()
        XCTAssertEqual(fixture.coordinator.state, .disabled)
        XCTAssertEqual(fixture.music.stopCount, 1)

        await gate.open()
        await settleTasks()
        XCTAssertEqual(fixture.coordinator.state, .disabled)
        XCTAssertNil(fixture.coordinator.matchedSong)
    }

    func testPlaybackControllerCorrectsTimelineBeyondTargetTolerance() async throws {
        let fixture = makeFixture()
        fixture.coordinator.toggle()
        await waitUntil { fixture.coordinator.state == .active }
        fixture.music.playbackTime = 10
        fixture.music.outputLatency = 0.075

        fixture.recognizer.emitMatch(match())
        await waitUntil { fixture.coordinator.state == .playing }
        await waitUntil(timeoutIterations: 500) { !fixture.music.seekTimes.isEmpty }

        XCTAssertEqual(try XCTUnwrap(fixture.music.seekTimes.first), 12.275, accuracy: 0.001)
        fixture.coordinator.toggle()
    }

    func testPlaybackControllerNeverRepeatsStartupCorrection() async {
        let fixture = makeFixture()
        fixture.coordinator.toggle()
        await waitUntil { fixture.coordinator.state == .active }
        fixture.music.playbackTime = 10
        fixture.music.appliesSeeks = false

        fixture.recognizer.emitMatch(match())
        await waitUntil { fixture.coordinator.state == .playing }
        await waitUntil(timeoutIterations: 500) { !fixture.music.seekTimes.isEmpty }
        try? await Task.sleep(for: .milliseconds(500))

        XCTAssertEqual(fixture.music.seekTimes.count, 1)
        fixture.coordinator.toggle()
    }

    func testSyncAdjustmentCommitsBeforePlaybackAndPersists() async {
        let fixture = makeFixture()

        fixture.coordinator.beginSyncAdjustment()
        fixture.coordinator.syncAdjustmentMilliseconds = -180
        XCTAssertTrue(fixture.music.seekTimes.isEmpty)
        XCTAssertEqual(fixture.music.userAdjustment, 0)

        fixture.coordinator.commitSyncAdjustment()
        XCTAssertEqual(fixture.music.userAdjustment, -0.18, accuracy: 0.000_001)
        XCTAssertTrue(fixture.music.seekTimes.isEmpty)

        let reloaded = makeFixture(settings: fixture.settings)
        XCTAssertEqual(reloaded.coordinator.syncAdjustmentMilliseconds, -180)
        XCTAssertEqual(reloaded.music.userAdjustment, -0.18, accuracy: 0.000_001)
    }

    func testDraggingDuringPlaybackSeeksOnceOnlyWhenReleased() async throws {
        let fixture = makeFixture()
        fixture.coordinator.toggle()
        await waitUntil { fixture.coordinator.state == .active }
        fixture.music.playbackTime = 12.2

        fixture.recognizer.emitMatch(match())
        await waitUntil {
            fixture.music.playbackTimeReadCount >= PlaybackSynchronization.sampleCount
        }

        fixture.coordinator.beginSyncAdjustment()
        fixture.coordinator.syncAdjustmentMilliseconds = 200
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(fixture.music.seekTimes.isEmpty)
        XCTAssertEqual(fixture.music.userAdjustment, 0)

        fixture.coordinator.commitSyncAdjustment()
        await waitUntil { fixture.music.seekTimes.count == 1 }

        XCTAssertEqual(try XCTUnwrap(fixture.music.seekTimes.first), 12.4, accuracy: 0.001)
        XCTAssertEqual(fixture.music.userAdjustment, 0.2, accuracy: 0.000_001)
        try? await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(fixture.music.seekTimes.count, 1)
        fixture.coordinator.toggle()
    }

    func testAdjustmentCommittedDuringStartupAppliesOnceAfterPlaybackBegins() async throws {
        let gate = AsyncGate()
        let fixture = makeFixture(playGate: gate)
        fixture.coordinator.toggle()
        await waitUntil { fixture.coordinator.state == .active }

        fixture.recognizer.emitMatch(match())
        await waitUntil { fixture.coordinator.state == .startingPlayback }
        fixture.coordinator.beginSyncAdjustment()
        fixture.coordinator.syncAdjustmentMilliseconds = 300
        fixture.coordinator.commitSyncAdjustment()
        XCTAssertTrue(fixture.music.seekTimes.isEmpty)

        await gate.open()
        await waitUntil { fixture.coordinator.state == .playing }
        await waitUntil { fixture.music.seekTimes.count == 1 }

        XCTAssertEqual(try XCTUnwrap(fixture.music.seekTimes.first), 12.5, accuracy: 0.001)
        try? await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(fixture.music.seekTimes.count, 1)
        fixture.coordinator.toggle()
    }

    func testMatchIsRecordedToHistoryAndNotified() async {
        let fixture = makeFixture()
        fixture.coordinator.toggle()
        await waitUntil { fixture.coordinator.state == .active }

        fixture.recognizer.emitMatch(match())
        await waitUntil { fixture.coordinator.state == .playing }

        XCTAssertEqual(fixture.coordinator.history.entries.map(\.appleMusicID), ["track"])
        XCTAssertEqual(fixture.notifier.notifiedSongs.map(\.title), ["Test Song"])
        fixture.coordinator.toggle()
    }

    func testDisabledNotificationsSuppressTheMatchNotification() async {
        let fixture = makeFixture()
        fixture.coordinator.matchNotificationsEnabled = false
        fixture.coordinator.toggle()
        await waitUntil { fixture.coordinator.state == .active }

        fixture.recognizer.emitMatch(match())
        await waitUntil { fixture.coordinator.state == .playing }

        XCTAssertTrue(fixture.notifier.notifiedSongs.isEmpty)
        XCTAssertEqual(fixture.coordinator.history.entries.count, 1)
        fixture.coordinator.toggle()
    }

    func testFollowRoomProbeSwitchesToTheRoomsNewSong() async {
        let fixture = makeFixture(followPolicy: fastFollowPolicy())
        fixture.coordinator.followRoomEnabled = true
        fixture.coordinator.toggle()
        await waitUntil { fixture.coordinator.state == .active }
        fixture.music.playbackTime = 10

        fixture.recognizer.emitMatch(match(identifier: "first"))
        await waitUntil { fixture.coordinator.state == .playing }
        await waitUntil { fixture.coordinator.isProbing }

        fixture.recognizer.emitMatch(match(identifier: "second", offset: 30))
        await waitUntil { fixture.music.playedIdentifiers == ["first", "second"] }
        await waitUntil { fixture.coordinator.state == .playing }

        XCTAssertEqual(fixture.coordinator.matchedSong?.appleMusicID, "second")
        XCTAssertEqual(fixture.notifier.notifiedSongs.count, 2)
        fixture.coordinator.toggle()
    }

    func testFollowRoomProbeCorrectsDriftForTheSameSong() async {
        let fixture = makeFixture(followPolicy: fastFollowPolicy())
        fixture.coordinator.followRoomEnabled = true
        fixture.coordinator.toggle()
        await waitUntil { fixture.coordinator.state == .active }
        fixture.music.playbackTime = 10

        fixture.recognizer.emitMatch(match(identifier: "track", offset: 12))
        await waitUntil { fixture.coordinator.state == .playing }
        await waitUntil { fixture.coordinator.isProbing }

        fixture.recognizer.emitMatch(match(identifier: "track", offset: 30))
        await waitUntil(timeoutIterations: 2_000) {
            fixture.music.seekTimes.contains { abs($0 - 30.2) < 0.05 }
        }

        XCTAssertEqual(fixture.music.playCount, 1)
        XCTAssertEqual(fixture.coordinator.state, .playing)
        fixture.coordinator.toggle()
    }

    func testDeviceChangeRestoresPerDeviceAdjustment() async {
        let deviceA = OutputDeviceInfo(uid: "device-a", name: "Built-in")
        let deviceB = OutputDeviceInfo(uid: "device-b", name: "AirPods")
        let fixture = makeFixture(device: deviceA)

        fixture.coordinator.beginSyncAdjustment()
        fixture.coordinator.syncAdjustmentMilliseconds = -180
        fixture.coordinator.commitSyncAdjustment()

        fixture.deviceObserver.changeDefaultDevice(to: deviceB)
        XCTAssertEqual(fixture.coordinator.syncAdjustmentMilliseconds, -180)

        fixture.coordinator.beginSyncAdjustment()
        fixture.coordinator.syncAdjustmentMilliseconds = 120
        fixture.coordinator.commitSyncAdjustment()

        fixture.deviceObserver.changeDefaultDevice(to: deviceA)
        XCTAssertEqual(fixture.coordinator.syncAdjustmentMilliseconds, -180)
        XCTAssertEqual(fixture.music.userAdjustment, -0.18, accuracy: 0.000_001)

        let reloaded = makeFixture(settings: fixture.settings, device: deviceB)
        XCTAssertEqual(reloaded.coordinator.syncAdjustmentMilliseconds, 120)
    }

    func testDeviceChangeDuringPlaybackRefreshesLatencyAndSeeksOnce() async {
        let deviceA = OutputDeviceInfo(uid: "device-a", name: "Built-in")
        let deviceB = OutputDeviceInfo(uid: "device-b", name: "AirPods")
        let fixture = makeFixture(device: deviceA)
        fixture.coordinator.toggle()
        await waitUntil { fixture.coordinator.state == .active }
        fixture.music.playbackTime = 10

        fixture.recognizer.emitMatch(match())
        await waitUntil { fixture.coordinator.state == .playing }
        await waitUntil { !fixture.music.seekTimes.isEmpty }
        let seekCountBeforeChange = fixture.music.seekTimes.count

        fixture.deviceObserver.changeDefaultDevice(to: deviceB)

        XCTAssertEqual(fixture.music.refreshOutputLatencyCount, 1)
        await waitUntil { fixture.music.seekTimes.count == seekCountBeforeChange + 1 }
        XCTAssertEqual(fixture.coordinator.state, .playing)
        fixture.coordinator.toggle()
    }

    private func fastFollowPolicy() -> FollowRoomPolicy {
        FollowRoomPolicy(
            probeInterval: .milliseconds(30),
            probeWindow: .milliseconds(400),
            tickInterval: .milliseconds(10),
            endOfTrackLead: 0,
            driftTolerance: 0.35
        )
    }

    private func makeFixture(
        microphoneGranted: Bool = true,
        playGate: AsyncGate? = nil,
        settings: UserDefaults? = nil,
        device: OutputDeviceInfo? = nil,
        followPolicy: FollowRoomPolicy = FollowRoomPolicy()
    ) -> Fixture {
        let audio = AudioMonitorSpy()
        let recognizer = RecognitionSpy()
        let music = MusicPlayerSpy(playGate: playGate)
        let notifier = MatchNotifierSpy()
        let deviceObserver = OutputDeviceObserverFake(currentDevice: device)
        let resolvedSettings: UserDefaults
        if let settings {
            resolvedSettings = settings
        } else {
            let suiteName = "AppCoordinatorTests.\(UUID().uuidString)"
            resolvedSettings = UserDefaults(suiteName: suiteName)!
            resolvedSettings.removePersistentDomain(forName: suiteName)
        }
        let coordinator = AppCoordinator(
            audio: audio,
            recognizer: recognizer,
            musicPlayer: music,
            requestMicrophoneAccess: { microphoneGranted },
            settings: resolvedSettings,
            notifier: notifier,
            deviceObserver: deviceObserver,
            followPolicy: followPolicy
        )
        return Fixture(
            coordinator: coordinator,
            audio: audio,
            recognizer: recognizer,
            music: music,
            notifier: notifier,
            deviceObserver: deviceObserver,
            settings: resolvedSettings
        )
    }

    private func match(identifier: String = "track", offset: TimeInterval = 12) -> Match {
        Match(
            song: RecognizedSong(title: "Test Song", artist: "Test Artist", appleMusicID: identifier),
            referenceOffset: offset,
            capturedAtUptime: ProcessInfo.processInfo.systemUptime + 3_600
        )
    }

    private func waitUntil(
        timeoutIterations: Int = 1_000,
        _ condition: () -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0..<timeoutIterations {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(1))
        }
        XCTFail("Condition was not reached", file: file, line: line)
    }

    private func settleTasks() async {
        for _ in 0..<20 {
            await Task.yield()
        }
    }
}

@MainActor
private struct Fixture {
    let coordinator: AppCoordinator
    let audio: AudioMonitorSpy
    let recognizer: RecognitionSpy
    let music: MusicPlayerSpy
    let notifier: MatchNotifierSpy
    let deviceObserver: OutputDeviceObserverFake
    let settings: UserDefaults
}

@MainActor
private final class MatchNotifierSpy: MatchNotifying {
    private(set) var notifiedSongs: [RecognizedSong] = []

    func notifyMatch(_ song: RecognizedSong) {
        notifiedSongs.append(song)
    }
}

@MainActor
private final class OutputDeviceObserverFake: OutputDeviceObserving {
    var onDefaultDeviceChange: (@MainActor (OutputDeviceInfo?) -> Void)?
    private(set) var currentDevice: OutputDeviceInfo?
    private(set) var startCount = 0

    init(currentDevice: OutputDeviceInfo?) {
        self.currentDevice = currentDevice
    }

    func start() {
        startCount += 1
    }

    func stop() {}

    func changeDefaultDevice(to device: OutputDeviceInfo?) {
        currentDevice = device
        onDefaultDeviceChange?(device)
    }
}

@MainActor
private final class AudioMonitorSpy: AudioMonitoring {
    var onLevel: AudioLevelHandler?
    var onGatedBuffer: AudioBufferHandler?
    var thresholdDB: Float = -50

    private(set) var startCount = 0
    private(set) var stopCount = 0

    func start() throws {
        startCount += 1
    }

    func stop() {
        stopCount += 1
    }
}

private final class RecognitionSpy: RecognitionServing, @unchecked Sendable {
    private struct State: Sendable {
        var onMatch: RecognitionMatchHandler?
        var onError: RecognitionErrorHandler?
        var resetCount = 0
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    var onMatch: RecognitionMatchHandler? {
        get { state.withLock { $0.onMatch } }
        set { state.withLock { $0.onMatch = newValue } }
    }

    var onError: RecognitionErrorHandler? {
        get { state.withLock { $0.onError } }
        set { state.withLock { $0.onError = newValue } }
    }

    var resetCount: Int {
        state.withLock { $0.resetCount }
    }

    func reset() {
        state.withLock { $0.resetCount += 1 }
    }

    func match(buffer: AVAudioPCMBuffer, at time: AVAudioTime?) {}

    @MainActor
    func emitMatch(_ match: Match) {
        let handler = state.withLock { $0.onMatch }
        handler?(match)
    }

    @MainActor
    func emitFailure(_ message: String) {
        let handler = state.withLock { $0.onError }
        handler?(message)
    }
}

@MainActor
private final class MusicPlayerSpy: MusicPlaying {
    private var storedPlaybackTime: TimeInterval? = 0
    var playbackTime: TimeInterval? {
        get {
            playbackTimeReadCount += 1
            return storedPlaybackTime
        }
        set { storedPlaybackTime = newValue }
    }
    var playbackDuration: TimeInterval?
    var userAdjustment: TimeInterval = 0
    var outputLatency: TimeInterval = 0
    var hasEnded = false
    var appliesSeeks = true
    private(set) var refreshOutputLatencyCount = 0

    var synchronizationOffset: TimeInterval {
        PlaybackSynchronization.defaultPlaybackOffset + outputLatency + userAdjustment
    }

    private(set) var prepareCount = 0
    private(set) var playCount = 0
    private(set) var stopCount = 0
    private(set) var playbackTimeReadCount = 0
    private(set) var playedIdentifiers: [String] = []
    private(set) var seekTimes: [TimeInterval] = []

    private let playGate: AsyncGate?

    init(playGate: AsyncGate?) {
        self.playGate = playGate
    }

    func prepareForPlayback() async throws {
        prepareCount += 1
    }

    func play(_ match: Match) async throws {
        playCount += 1
        playedIdentifiers.append(match.song.appleMusicID ?? "")
        if let playGate {
            await playGate.wait()
        }
        try Task.checkCancellation()
    }

    func targetPosition(for match: Match) -> TimeInterval {
        max(0, match.currentOffset + synchronizationOffset)
    }

    func seek(to time: TimeInterval) throws {
        seekTimes.append(time)
        if appliesSeeks {
            playbackTime = time
        }
    }

    func refreshOutputLatency() throws {
        refreshOutputLatencyCount += 1
    }

    func stop() {
        stopCount += 1
        playbackTime = nil
    }
}
