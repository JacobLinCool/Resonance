import Foundation
import XCTest

@testable import Resonance

@MainActor
final class MusicPlayerTests: XCTestCase {
    func testPlaybackTimeRejectsNaN() {
        let backend = FakeMusicPlayerBackend()
        let player = MusicPlayer(backend: backend)

        backend.playbackTime = .nan
        XCTAssertNil(player.playbackTime)

        backend.playbackTime = 12.5
        XCTAssertEqual(player.playbackTime, 12.5)
    }

    func testSeekRejectsNonfiniteNegativeAndPastDurationPositions() async throws {
        let backend = FakeMusicPlayerBackend()
        backend.catalog["bounded"] = .init(identifier: "bounded", duration: 30)
        let player = MusicPlayer(backend: backend)

        try await player.play(match(identifier: "bounded", offset: 10))

        try player.seek(to: 30)
        XCTAssertEqual(backend.playbackTime, 30)
        assertInvalidPosition { try player.seek(to: .nan) }
        assertInvalidPosition { try player.seek(to: -0.1) }
        assertInvalidPosition { try player.seek(to: 30.1) }
    }

    func testPreparesAndPositionsEntryBeforeStartingPlayback() async throws {
        let backend = FakeMusicPlayerBackend()
        backend.catalog["prepared"] = .init(identifier: "prepared", duration: 60)
        let player = MusicPlayer(backend: backend)

        try await player.play(match(identifier: "prepared", offset: 12))

        XCTAssertEqual(backend.prepareCallCount, 1)
        XCTAssertTrue(backend.wasPreparedWhenPlayed)
        XCTAssertEqual(backend.playbackTimeAtPlay, 12.2)
    }

    func testLeadsPlaybackByReportedOutputLatency() async throws {
        let backend = FakeMusicPlayerBackend()
        backend.catalog["latency"] = .init(identifier: "latency", duration: 60)
        backend.outputLatency = 0.075
        let player = MusicPlayer(backend: backend)

        try await player.play(match(identifier: "latency", offset: 12))

        XCTAssertEqual(player.synchronizationOffset, 0.275, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(backend.playbackTimeAtPlay), 12.275, accuracy: 0.000_001)
        XCTAssertEqual(backend.playbackTime, 12.275, accuracy: 0.000_001)
    }

    func testUserAdjustmentIsRelativeToDefaultPlaybackOffset() {
        let player = MusicPlayer(backend: FakeMusicPlayerBackend())

        XCTAssertEqual(player.userAdjustment, 0, accuracy: 0.000_001)
        XCTAssertEqual(player.synchronizationOffset, 0.2, accuracy: 0.000_001)

        player.userAdjustment = 0.05
        XCTAssertEqual(player.synchronizationOffset, 0.25, accuracy: 0.000_001)
    }

    func testUserAdjustmentCombinesWithOutputLatencyAndSurvivesStop() async throws {
        let backend = FakeMusicPlayerBackend()
        backend.catalog["adjusted"] = .init(identifier: "adjusted", duration: 60)
        backend.outputLatency = 0.075
        let player = MusicPlayer(backend: backend)
        player.userAdjustment = 0.125

        try await player.play(match(identifier: "adjusted", offset: 12))

        XCTAssertEqual(player.synchronizationOffset, 0.4, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(backend.playbackTimeAtPlay), 12.4, accuracy: 0.000_001)
        XCTAssertEqual(backend.playbackTime, 12.4, accuracy: 0.000_001)

        player.stop()
        XCTAssertEqual(player.userAdjustment, 0.125, accuracy: 0.000_001)
        XCTAssertEqual(player.synchronizationOffset, 0.325, accuracy: 0.000_001)
    }

    func testNegativeAdjustmentClampsPlaybackTargetToTrackStart() async throws {
        let backend = FakeMusicPlayerBackend()
        backend.catalog["clamped"] = .init(identifier: "clamped", duration: 60)
        let player = MusicPlayer(backend: backend)
        player.userAdjustment = -0.5

        try await player.play(match(identifier: "clamped", offset: 0.1))

        XCTAssertEqual(backend.playbackTimeAtPlay, 0)
        XCTAssertEqual(backend.playbackTime, 0)
    }

    func testCancellationDuringSuspendedCatalogLoadCannotQueueOrPlay() async {
        let backend = FakeMusicPlayerBackend()
        backend.suspendedLoads.insert("cancelled")
        let player = MusicPlayer(backend: backend)
        let playTask = Task { @MainActor in
            try await player.play(match(identifier: "cancelled", offset: 8))
        }

        await waitUntil { backend.loadRequests == ["cancelled"] }
        playTask.cancel()
        await Task.yield()

        XCTAssertTrue(backend.queuedIdentifiers.isEmpty)
        XCTAssertEqual(backend.playCallCount, 0)

        backend.resumeLoad(
            identifier: "cancelled",
            with: .init(identifier: "cancelled", duration: 60)
        )
        await assertCancellation(of: playTask)

        XCTAssertTrue(backend.queuedIdentifiers.isEmpty)
        XCTAssertEqual(backend.playCallCount, 0)
        XCTAssertGreaterThanOrEqual(backend.stopCallCount, 1)
        XCTAssertEqual(backend.playbackStatus, .stopped)
    }

    func testStopRollsBackAStartupWhoseBackendPlayIgnoresCancellation() async {
        let backend = FakeMusicPlayerBackend()
        backend.catalog["suspended-play"] = .init(identifier: "suspended-play", duration: 60)
        backend.suspendNextPlay = true
        let player = MusicPlayer(backend: backend)
        let playTask = Task { @MainActor in
            try await player.play(match(identifier: "suspended-play", offset: 14))
        }

        await waitUntil { backend.hasSuspendedPlay }
        player.stop()

        XCTAssertGreaterThanOrEqual(backend.stopCallCount, 1)
        XCTAssertEqual(backend.playbackStatus, .stopped)

        backend.resumePlay()
        await assertCancellation(of: playTask)

        XCTAssertEqual(backend.playbackStatus, .stopped)
        XCTAssertGreaterThanOrEqual(backend.stopCallCount, 2)
    }

    func testSeekTargetIncludesTimeSpentStartingPlayback() async throws {
        let backend = FakeMusicPlayerBackend()
        backend.catalog["delayed-play"] = .init(identifier: "delayed-play", duration: 1_000_000)
        backend.suspendNextPlay = true
        let player = MusicPlayer(backend: backend)
        let match = Match(
            song: RecognizedSong(title: "Test Song", artist: nil, appleMusicID: "delayed-play"),
            referenceOffset: 0,
            referencePlaybackRate: 100,
            capturedAtUptime: ProcessInfo.processInfo.systemUptime
        )
        let playTask = Task { @MainActor in
            try await player.play(match)
        }

        await waitUntil { backend.hasSuspendedPlay }
        try await Task.sleep(for: .milliseconds(20))
        let offsetWhenPlaybackResumed = match.currentOffset
        backend.resumePlay()
        try await playTask.value

        XCTAssertGreaterThanOrEqual(backend.playbackTime, offsetWhenPlaybackResumed)
    }

    func testNewStartupDrainsOldStartupBeforeLoadingOrQueuing() async throws {
        let backend = FakeMusicPlayerBackend()
        backend.suspendedLoads = ["old", "new"]
        let player = MusicPlayer(backend: backend)
        let oldTask = Task { @MainActor in
            try await player.play(match(identifier: "old", offset: 5))
        }

        await waitUntil { backend.loadRequests == ["old"] }

        let newTask = Task { @MainActor in
            try await player.play(match(identifier: "new", offset: 20))
        }
        await waitUntil { backend.stopCallCount > 0 }

        XCTAssertEqual(backend.loadRequests, ["old"])
        XCTAssertTrue(backend.queuedIdentifiers.isEmpty)

        backend.resumeLoad(
            identifier: "old",
            with: .init(identifier: "old", duration: 60)
        )
        await assertCancellation(of: oldTask)
        await waitUntil { backend.loadRequests == ["old", "new"] }

        XCTAssertTrue(backend.queuedIdentifiers.isEmpty)
        XCTAssertEqual(backend.playCallCount, 0)

        backend.resumeLoad(
            identifier: "new",
            with: .init(identifier: "new", duration: 60)
        )
        try await newTask.value

        XCTAssertEqual(backend.queuedIdentifiers, ["new"])
        XCTAssertEqual(backend.playCallCount, 1)
        XCTAssertEqual(backend.playbackTime, 20.2)
        XCTAssertEqual(backend.playbackStatus, .active)
    }

    func testPrepareForPlaybackPreservesAuthorizationAndSubscriptionErrors() async throws {
        let backend = FakeMusicPlayerBackend()
        let player = MusicPlayer(backend: backend)

        backend.authorizationStatus = .denied
        await assertMusicPlayerError(.authorizationDenied) {
            try await player.prepareForPlayback()
        }

        backend.authorizationStatus = .authorized
        backend.catalogPlaybackAllowed = false
        await assertMusicPlayerError(.subscriptionRequired) {
            try await player.prepareForPlayback()
        }

        backend.catalogPlaybackAllowed = true
        try await player.prepareForPlayback()
    }

    func testHasEndedMapsOnlyStoppedAndPausedStatuses() {
        let backend = FakeMusicPlayerBackend()
        let player = MusicPlayer(backend: backend)

        backend.playbackStatus = .stopped
        XCTAssertTrue(player.hasEnded)
        backend.playbackStatus = .paused
        XCTAssertTrue(player.hasEnded)
        backend.playbackStatus = .active
        XCTAssertFalse(player.hasEnded)
    }

    private func match(identifier: String, offset: TimeInterval) -> Match {
        Match(
            song: RecognizedSong(title: "Test Song", artist: nil, appleMusicID: identifier),
            referenceOffset: offset,
            capturedAtUptime: ProcessInfo.processInfo.systemUptime + 3_600
        )
    }

    private func assertInvalidPosition(
        _ operation: () throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        do {
            try operation()
            XCTFail("Expected invalidPlaybackPosition", file: file, line: line)
        } catch let error as MusicPlayerError {
            XCTAssertEqual(error, .invalidPlaybackPosition, file: file, line: line)
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
    }

    private func assertCancellation(
        of task: Task<Void, Error>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            try await task.value
            XCTFail("Expected cancellation", file: file, line: line)
        } catch is CancellationError {
            return
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
    }

    private func assertMusicPlayerError(
        _ expected: MusicPlayerError,
        file: StaticString = #filePath,
        line: UInt = #line,
        operation: () async throws -> Void
    ) async {
        do {
            try await operation()
            XCTFail("Expected \(expected)", file: file, line: line)
        } catch let error as MusicPlayerError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
    }

    private func waitUntil(
        _ condition: () -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0..<1_000 {
            if condition() { return }
            await Task.yield()
        }
        XCTFail("Condition was not reached", file: file, line: line)
    }
}
