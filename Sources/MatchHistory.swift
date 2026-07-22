import Foundation
import Observation

/// One recognized song, kept so the user can find "that song from the café"
/// after the moment has passed.
struct MatchHistoryEntry: Sendable, Equatable, Codable, Identifiable {
    let id: UUID
    let title: String
    let artist: String?
    let appleMusicID: String?
    let artworkURL: URL?
    let appleMusicURL: URL?
    let recognizedAt: Date

    init(song: RecognizedSong, recognizedAt: Date, id: UUID = UUID()) {
        self.id = id
        self.title = song.title
        self.artist = song.artist
        self.appleMusicID = song.appleMusicID
        self.artworkURL = song.artworkURL
        self.appleMusicURL = song.appleMusicURL
        self.recognizedAt = recognizedAt
    }
}

/// Persists the recognition history in `UserDefaults`, newest first. The list
/// is bounded, and consecutive re-recognitions of the same song within a short
/// window collapse into the existing entry so re-syncs don't flood the list.
@MainActor
@Observable
final class MatchHistoryStore {
    private(set) var entries: [MatchHistoryEntry] = []

    @ObservationIgnored private let settings: UserDefaults
    @ObservationIgnored private let now: @Sendable () -> Date

    static let maximumEntryCount = 100
    static let duplicateCollapseWindow: TimeInterval = 10 * 60
    private static let storageKey = "matchHistoryEntries"

    init(settings: UserDefaults = .standard, now: @escaping @Sendable () -> Date = Date.init) {
        self.settings = settings
        self.now = now
        entries = Self.load(from: settings)
    }

    func record(_ song: RecognizedSong) {
        let date = now()
        if let latest = entries.first, collapses(latest, into: song, at: date) {
            entries[0] = MatchHistoryEntry(song: song, recognizedAt: date, id: latest.id)
        } else {
            entries.insert(MatchHistoryEntry(song: song, recognizedAt: date), at: 0)
            if entries.count > Self.maximumEntryCount {
                entries.removeLast(entries.count - Self.maximumEntryCount)
            }
        }
        save()
    }

    func remove(_ entry: MatchHistoryEntry) {
        entries.removeAll { $0.id == entry.id }
        save()
    }

    func clear() {
        entries.removeAll()
        save()
    }

    private func collapses(_ latest: MatchHistoryEntry, into song: RecognizedSong, at date: Date) -> Bool {
        latest.appleMusicID != nil
            && latest.appleMusicID == song.appleMusicID
            && date.timeIntervalSince(latest.recognizedAt) < Self.duplicateCollapseWindow
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        settings.set(data, forKey: Self.storageKey)
    }

    private static func load(from settings: UserDefaults) -> [MatchHistoryEntry] {
        guard let data = settings.data(forKey: storageKey),
            let stored = try? JSONDecoder().decode([MatchHistoryEntry].self, from: data)
        else { return [] }
        return Array(stored.prefix(maximumEntryCount))
    }
}
