import XCTest

@testable import Resonance

final class MatchTests: XCTestCase {
    private let song = RecognizedSong(
        title: "Test Song",
        artist: "Test Artist",
        appleMusicID: "123"
    )

    func testExtrapolatesFromMonotonicTime() {
        let match = Match(song: song, referenceOffset: 12.5, capturedAtUptime: 100)

        XCTAssertEqual(match.currentOffset(atUptime: 101.25), 13.75, accuracy: 0.000_001)
    }

    func testAppliesFrequencySkewToElapsedTime() {
        let match = Match(
            song: song,
            referenceOffset: 20,
            referencePlaybackRate: 1.05,
            capturedAtUptime: 100
        )

        XCTAssertEqual(match.currentOffset(atUptime: 110), 30.5, accuracy: 0.000_001)
    }

    func testDoesNotMoveBackwardWhenUptimePrecedesCapture() {
        let match = Match(song: song, referenceOffset: 12.5, capturedAtUptime: 100)

        XCTAssertEqual(match.currentOffset(atUptime: 99), 12.5, accuracy: 0.000_001)
    }
}
