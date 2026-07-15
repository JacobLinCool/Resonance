import Foundation
import ShazamKit
import XCTest

@testable import Resonance

@MainActor
final class ShazamRecognizerTests: XCTestCase {
    func testCurrentSessionDeliversCallbacks() async {
        let initialSession = SHSession()
        let recognizer = ShazamRecognizer(session: initialSession)
        var receivedMatches = 0
        var receivedFailures: [String] = []
        recognizer.onMatch = { _ in receivedMatches += 1 }
        recognizer.onError = { receivedFailures.append($0) }

        recognizer.deliver(match(), from: initialSession)
        recognizer.deliverFailure("failure", from: initialSession)
        await waitUntil { receivedMatches == 1 && receivedFailures == ["failure"] }
    }

    func testResetRejectsMatchQueuedByPreviousSession() async {
        let initialSession = SHSession()
        let recognizer = ShazamRecognizer(session: initialSession)
        var receivedMatches = 0
        recognizer.onMatch = { _ in receivedMatches += 1 }

        recognizer.deliver(match(), from: initialSession)
        recognizer.reset()
        await settleTasks()

        XCTAssertEqual(receivedMatches, 0)
    }

    func testResetRejectsFailureQueuedByPreviousSession() async {
        let initialSession = SHSession()
        let recognizer = ShazamRecognizer(session: initialSession)
        var receivedFailures: [String] = []
        recognizer.onError = { receivedFailures.append($0) }

        recognizer.deliverFailure("stale", from: initialSession)
        recognizer.reset()
        await settleTasks()

        XCTAssertTrue(receivedFailures.isEmpty)
    }

    private func match() -> Match {
        Match(
            song: RecognizedSong(title: "Test Song", artist: nil, appleMusicID: "track"),
            referenceOffset: 5,
            capturedAtUptime: ProcessInfo.processInfo.systemUptime
        )
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

    private func settleTasks() async {
        for _ in 0..<20 {
            await Task.yield()
        }
    }
}
