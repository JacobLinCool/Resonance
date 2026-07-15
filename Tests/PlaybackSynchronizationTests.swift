import XCTest

@testable import Resonance

final class PlaybackSynchronizationTests: XCTestCase {
    private let song = RecognizedSong(
        title: "Test Song",
        artist: "Test Artist",
        appleMusicID: "123"
    )

    func testTimelineErrorUsesReadMidpointOnMonotonicClock() {
        let match = Match(
            song: song,
            referenceOffset: 10,
            referencePlaybackRate: 1.05,
            capturedAtUptime: 100
        )

        let error = PlaybackSynchronization.timelineError(
            match: match,
            playbackTime: 12,
            playbackOffset: 0.03,
            readStartedAt: 102,
            readFinishedAt: 104
        )

        XCTAssertEqual(try XCTUnwrap(error), 1.18, accuracy: 0.000_001)
    }

    func testTimelineErrorRejectsInvalidMeasurements() {
        let match = Match(song: song, referenceOffset: 10, capturedAtUptime: 100)

        XCTAssertNil(
            PlaybackSynchronization.timelineError(
                match: match,
                playbackTime: .nan,
                playbackOffset: 0,
                readStartedAt: 101,
                readFinishedAt: 102
            )
        )
        XCTAssertNil(
            PlaybackSynchronization.timelineError(
                match: match,
                playbackTime: 10,
                playbackOffset: 0,
                readStartedAt: 102,
                readFinishedAt: 101
            )
        )
    }

    func testNegativePlaybackOffsetClampsTargetToTrackStart() {
        let match = Match(song: song, referenceOffset: 0.1, capturedAtUptime: 100)

        let error = PlaybackSynchronization.timelineError(
            match: match,
            playbackTime: 0.02,
            playbackOffset: -0.5,
            readStartedAt: 100,
            readFinishedAt: 100
        )

        XCTAssertEqual(error, -0.02)
    }

    func testMedianRejectsOneTimingOutlier() throws {
        XCTAssertEqual(
            try XCTUnwrap(PlaybackSynchronization.median(of: [0.012, 0.5, 0.014])),
            0.014,
            accuracy: 0.000_001
        )
    }

}
