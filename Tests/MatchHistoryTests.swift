import Foundation
import XCTest

@testable import Resonance

@MainActor
final class MatchHistoryTests: XCTestCase {
    func testRecordsNewestFirstAndPersistsAcrossReload() {
        let settings = makeSettings()
        let store = MatchHistoryStore(settings: settings)

        store.record(song(id: "1", title: "First"))
        store.record(song(id: "2", title: "Second"))

        XCTAssertEqual(store.entries.map(\.title), ["Second", "First"])

        let reloaded = MatchHistoryStore(settings: settings)
        XCTAssertEqual(reloaded.entries.map(\.title), ["Second", "First"])
    }

    func testConsecutiveSameSongCollapsesWithinTheWindow() {
        let settings = makeSettings()
        let clock = MutableClock(Date(timeIntervalSince1970: 1_000))
        let store = MatchHistoryStore(settings: settings, now: { clock.value })

        store.record(song(id: "1", title: "Song"))
        clock.advance(by: 60)
        store.record(song(id: "1", title: "Song"))

        XCTAssertEqual(store.entries.count, 1)
        XCTAssertEqual(store.entries[0].recognizedAt, clock.value)

        clock.advance(by: MatchHistoryStore.duplicateCollapseWindow + 1)
        store.record(song(id: "1", title: "Song"))

        XCTAssertEqual(store.entries.count, 2)
    }

    func testSongsWithoutCatalogIDNeverCollapse() {
        let store = MatchHistoryStore(settings: makeSettings())

        store.record(RecognizedSong(title: "Unknown", artist: nil, appleMusicID: nil))
        store.record(RecognizedSong(title: "Unknown", artist: nil, appleMusicID: nil))

        XCTAssertEqual(store.entries.count, 2)
    }

    func testEntryCountIsBounded() {
        let store = MatchHistoryStore(settings: makeSettings())

        for index in 0...(MatchHistoryStore.maximumEntryCount + 10) {
            store.record(song(id: "\(index)", title: "Song \(index)"))
        }

        XCTAssertEqual(store.entries.count, MatchHistoryStore.maximumEntryCount)
        XCTAssertEqual(store.entries.first?.title, "Song \(MatchHistoryStore.maximumEntryCount + 10)")
    }

    func testRemoveAndClear() {
        let store = MatchHistoryStore(settings: makeSettings())
        store.record(song(id: "1", title: "One"))
        store.record(song(id: "2", title: "Two"))

        let victim = store.entries[0]
        store.remove(victim)
        XCTAssertEqual(store.entries.map(\.title), ["One"])

        store.clear()
        XCTAssertTrue(store.entries.isEmpty)
    }

    private func song(id: String, title: String) -> RecognizedSong {
        RecognizedSong(
            title: title,
            artist: "Artist",
            appleMusicID: id,
            artworkURL: URL(string: "https://example.com/art.png"),
            appleMusicURL: URL(string: "https://music.apple.com/song/\(id)")
        )
    }

    private func makeSettings() -> UserDefaults {
        let suiteName = "MatchHistoryTests.\(UUID().uuidString)"
        let settings = UserDefaults(suiteName: suiteName)!
        settings.removePersistentDomain(forName: suiteName)
        return settings
    }
}

/// Test-controlled clock: mutated only from the test's main actor while the
/// store reads it synchronously on the same actor.
final class MutableClock: @unchecked Sendable {
    private(set) var value: Date

    init(_ value: Date) {
        self.value = value
    }

    func advance(by interval: TimeInterval) {
        value += interval
    }
}
