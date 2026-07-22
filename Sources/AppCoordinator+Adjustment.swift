import Foundation
import os

/// Sync adjustment lifecycle plus the output-device awareness around it. Each
/// output device remembers its own trim: AirPods and built-in speakers need
/// different values, and switching devices restores the right one.
extension AppCoordinator {
    /// Stops the bounded automatic startup correction before the user takes
    /// control. Playback continues uninterrupted while the slider is moving.
    func beginSyncAdjustment() {
        playbackSession.beginAdjustment()
    }

    /// Persists the preview and, during playback, performs exactly one seek.
    func commitSyncAdjustment() {
        persistSyncAdjustment()
        musicPlayer.userAdjustment = syncAdjustmentMilliseconds / 1_000
        playbackSession.commitAdjustment()
    }

    func resetSyncAdjustment() {
        beginSyncAdjustment()
        syncAdjustmentMilliseconds = 0
        commitSyncAdjustment()
    }

    /// The startup value: the current device's saved trim when one exists,
    /// otherwise the device-independent value written by earlier versions.
    func initialSyncAdjustment() -> Double? {
        let perDevice = currentDeviceUID.flatMap { Self.storedDeviceAdjustments(in: settings)[$0] }
        if let perDevice, Self.isValidSyncAdjustment(perDevice) {
            return perDevice
        }
        let legacy = settings.object(forKey: Self.syncAdjustmentKey) as? Double
        if let legacy, Self.isValidSyncAdjustment(legacy) {
            return legacy
        }
        return nil
    }

    func persistSyncAdjustment() {
        settings.set(syncAdjustmentMilliseconds, forKey: Self.syncAdjustmentKey)
        guard let uid = currentDeviceUID else { return }
        var adjustments = Self.storedDeviceAdjustments(in: settings)
        adjustments[uid] = syncAdjustmentMilliseconds
        settings.set(adjustments, forKey: Self.syncAdjustmentByDeviceKey)
    }

    static func storedDeviceAdjustments(in settings: UserDefaults) -> [String: Double] {
        guard let stored = settings.dictionary(forKey: syncAdjustmentByDeviceKey) else {
            return [:]
        }
        return stored.compactMapValues { $0 as? Double }
    }

    // MARK: - Default output device changes

    /// Restores the new device's saved trim and, during playback, re-reads the
    /// output pipeline latency and applies one corrective seek. Without this,
    /// switching from speakers to Bluetooth headphones mid-song would keep
    /// compensating the old device.
    func handleDefaultOutputDeviceChange(_ device: OutputDeviceInfo?) {
        guard device?.uid != currentDeviceUID else { return }
        currentDeviceUID = device?.uid

        let stored = device.flatMap { Self.storedDeviceAdjustments(in: settings)[$0.uid] }
        let restored: Double? =
            if let stored, Self.isValidSyncAdjustment(stored) { stored } else { nil }

        guard state == .playing else {
            if let restored {
                syncAdjustmentMilliseconds = restored
                musicPlayer.userAdjustment = restored / 1_000
            }
            return
        }

        playbackSession.beginAdjustment()
        if let restored {
            syncAdjustmentMilliseconds = restored
        }
        do {
            try musicPlayer.refreshOutputLatency()
        } catch {
            // The old compensation stays in effect; the corrective seek below
            // still applies the restored trim.
        }
        // Apply without persisting: the previous device's trim must not become
        // the new device's saved value until the user commits it.
        musicPlayer.userAdjustment = syncAdjustmentMilliseconds / 1_000
        playbackSession.commitAdjustment()
    }
}

extension AppCoordinator {
    // MARK: - Presentation

    var menuBarSymbol: String {
        switch state {
        case .disabled:
            "waveform.slash"
        case .active:
            "waveform"
        case .startingPlayback:
            "music.note.list"
        case .playing:
            "music.note"
        }
    }

    /// Elapsed time and duration for the playing track, when both are known.
    /// Not observation-tracked; the UI samples it on a timeline.
    var playbackProgress: (elapsed: TimeInterval, duration: TimeInterval)? {
        guard state == .playing,
            let elapsed = musicPlayer.playbackTime,
            let duration = musicPlayer.playbackDuration
        else { return nil }
        return (min(elapsed, duration), duration)
    }
}
