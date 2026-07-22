import AppKit
import AVFoundation
import SwiftUI
import XCTest

@testable import Resonance

/// Forces every window's root view through a real AppKit layout pass, pinning
/// the dependency wiring: a missing environment object or a body that traps
/// fails here instead of at first click in production.
@MainActor
final class ViewSmokeTests: XCTestCase {
    func testContentViewLaysOutWithEnvironment() {
        let coordinator = makeCoordinator()
        let view = ContentView(showSettings: {}, showHistory: {})
            .environment(coordinator)
            .environment(UpdateChecker(settings: makeSettings()))

        layout(view)
    }

    func testSettingsViewLaysOut() {
        let settings = makeSettings()
        let view = SettingsView(
            coordinator: makeCoordinator(),
            loginItem: LoginItemModel(loginItem: LoginItemFake()),
            shortcuts: ShortcutSettings(hotKeys: HotKeyCenter(), settings: settings),
            updateChecker: UpdateChecker(settings: settings)
        )

        layout(view)
    }

    func testHistoryViewLaysOutEmptyAndPopulated() {
        let history = MatchHistoryStore(settings: makeSettings())
        layout(HistoryView(history: history))

        history.record(
            RecognizedSong(
                title: "Smoke Song",
                artist: "Smoke Artist",
                appleMusicID: "smoke",
                artworkURL: nil,
                appleMusicURL: URL(string: "https://music.apple.com/song/smoke")
            )
        )
        layout(HistoryView(history: history))
    }

    func testOnboardingViewLaysOut() {
        layout(OnboardingView(onGetStarted: {}, onNotNow: {}))
    }

    private func layout(_ view: some View) {
        let hosting = NSHostingView(rootView: AnyView(view))
        hosting.frame = NSRect(x: 0, y: 0, width: 600, height: 800)
        hosting.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(hosting.fittingSize.height, 0)
    }

    private func makeCoordinator() -> AppCoordinator {
        AppCoordinator(
            audio: AudioMonitorFake(),
            recognizer: RecognizerFake(),
            musicPlayer: MusicPlayerFake(),
            requestMicrophoneAccess: { false },
            settings: makeSettings()
        )
    }

    private func makeSettings() -> UserDefaults {
        let suiteName = "ViewSmokeTests.\(UUID().uuidString)"
        let settings = UserDefaults(suiteName: suiteName)!
        settings.removePersistentDomain(forName: suiteName)
        return settings
    }
}

@MainActor
private final class AudioMonitorFake: AudioMonitoring {
    var onLevel: AudioLevelHandler?
    var onGatedBuffer: AudioBufferHandler?
    var thresholdDB: Float = -50

    func start() throws {}
    func stop() {}
}

private final class RecognizerFake: RecognitionServing, @unchecked Sendable {
    var onMatch: RecognitionMatchHandler?
    var onError: RecognitionErrorHandler?

    func reset() {}
    func match(buffer: AVAudioPCMBuffer, at time: AVAudioTime?) {}
}

@MainActor
private final class MusicPlayerFake: MusicPlaying {
    var playbackTime: TimeInterval?
    var playbackDuration: TimeInterval?
    var userAdjustment: TimeInterval = 0
    var synchronizationOffset: TimeInterval = 0
    var hasEnded = false

    func prepareForPlayback() async throws {}
    func play(_ match: Match) async throws {}
    func targetPosition(for match: Match) -> TimeInterval { 0 }
    func seek(to time: TimeInterval) throws {}
    func refreshOutputLatency() throws {}
    func stop() {}
}

@MainActor
private final class LoginItemFake: LoginItemManaging {
    var isEnabled = false

    func setEnabled(_ enabled: Bool) throws {
        isEnabled = enabled
    }
}
