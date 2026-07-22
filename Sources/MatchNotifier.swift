import Foundation
import UserNotifications
import os

@MainActor
protocol MatchNotifying: AnyObject {
    func notifyMatch(_ song: RecognizedSong)
}

/// Default for tests and previews: never touches the notification center.
@MainActor
final class NullMatchNotifier: MatchNotifying {
    func notifyMatch(_ song: RecognizedSong) {}
}

/// Posts a local notification when a match starts playing, so users who have
/// the popover closed still see what Resonance synced to. Authorization is
/// requested lazily on the first notification.
@MainActor
final class UserNotificationMatchNotifier: MatchNotifying {
    private let center = UNUserNotificationCenter.current()
    private var hasRequestedAuthorization = false
    private let log = Logger(subsystem: AppIdentity.bundleIdentifier, category: "notify")

    func notifyMatch(_ song: RecognizedSong) {
        Task { [weak self] in
            await self?.deliver(song)
        }
    }

    private func deliver(_ song: RecognizedSong) async {
        if !hasRequestedAuthorization {
            hasRequestedAuthorization = true
            do {
                _ = try await center.requestAuthorization(options: [.alert, .sound])
            } catch {
                log.error("notification authorization failed: \(error.localizedDescription)")
            }
        }

        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized else { return }

        let content = UNMutableNotificationContent()
        content.title = String(localized: "Now syncing")
        content.body =
            if let artist = song.artist {
                "\(song.title) — \(artist)"
            } else {
                song.title
            }

        let request = UNNotificationRequest(
            identifier: "match.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        do {
            try await center.add(request)
        } catch {
            log.error("notification delivery failed: \(error.localizedDescription)")
        }
    }
}
