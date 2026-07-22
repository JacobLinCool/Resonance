import SwiftUI

struct ContentView: View {
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(UpdateChecker.self) private var updateChecker
    let showSettings: @MainActor () -> Void
    let showHistory: @MainActor () -> Void

    var body: some View {
        @Bindable var coordinator = coordinator

        VStack(alignment: .leading, spacing: 14) {
            header
            Divider()
            if let song = coordinator.matchedSong {
                songDetails(song)
            }
            if coordinator.state == .playing {
                playbackProgress
            }
            if coordinator.state == .active || coordinator.isProbing {
                meter
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("Loudness threshold").font(.caption)
                    Spacer()
                    Text("\(Int(coordinator.thresholdDB)) dB")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Slider(value: $coordinator.thresholdDB, in: -60...0, step: 1)
            }
            syncAdjustment
            followRoom
            if let error = coordinator.lastError {
                errorDetails(error)
            }
            if let update = updateChecker.availableUpdate {
                updateBanner(update)
            }
            Divider()
            footer
        }
        .padding(16)
        .frame(width: 300)
    }

    // MARK: - Sections

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: coordinator.menuBarSymbol)
                .foregroundStyle(.tint)
            Text("Resonance").font(.headline)
            Spacer()
            Text(stateLabel)
                .font(.caption.weight(.semibold))
                .foregroundStyle(stateColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(stateColor.opacity(0.15), in: Capsule())
        }
    }

    private func songDetails(_ song: RecognizedSong) -> some View {
        HStack(spacing: 8) {
            ArtworkView(url: song.artworkURL, size: 40)
            VStack(alignment: .leading, spacing: 1) {
                Text(song.title).font(.body.weight(.medium)).lineLimit(1)
                if let artist = song.artist {
                    Text(artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if let url = song.appleMusicURL {
                Link(destination: url) {
                    Image(systemName: "arrow.up.forward.app")
                        .accessibilityLabel("Open in Apple Music")
                }
                .foregroundStyle(.secondary)
                .help("Open in Apple Music")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Samples the non-observable player position once per second.
    private var playbackProgress: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            if let progress = coordinator.playbackProgress {
                VStack(alignment: .leading, spacing: 2) {
                    ProgressView(value: progress.elapsed, total: progress.duration)
                        .controlSize(.small)
                    HStack {
                        Text(formattedTime(progress.elapsed))
                        Spacer()
                        Text(formattedTime(progress.duration))
                    }
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var meter: some View {
        VStack(alignment: .leading, spacing: 4) {
            LevelMeter(
                level: coordinator.level,
                threshold: Float(coordinator.thresholdDB),
                active: coordinator.isStreamingToRecognizer
            )
            .frame(height: 8)
            Text(meterCaption)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var syncAdjustment: some View {
        @Bindable var coordinator = coordinator

        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Text("Sync adjustment").font(.caption)
                Spacer()
                Text(formattedSyncAdjustment)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Button("Reset") {
                    coordinator.resetSyncAdjustment()
                }
                .controlSize(.mini)
                .disabled(abs(coordinator.syncAdjustmentMilliseconds) < 0.5)
            }
            Slider(
                value: $coordinator.syncAdjustmentMilliseconds,
                in: AppCoordinator.syncAdjustmentRange,
                step: 10,
                onEditingChanged: { isEditing in
                    if isEditing {
                        coordinator.beginSyncAdjustment()
                    } else {
                        coordinator.commitSyncAdjustment()
                    }
                }
            )
            .accessibilityLabel("Sync adjustment")
            .accessibilityValue(formattedSyncAdjustment)
            HStack {
                Text(verbatim: "−500 ms")
                Spacer()
                Text(verbatim: "+500 ms")
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.tertiary)
        }
    }

    private var followRoom: some View {
        @Bindable var coordinator = coordinator

        return Toggle(isOn: $coordinator.followRoomEnabled) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Follow the room").font(.caption)
                Text("Re-listen during playback to catch song changes.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.switch)
        .controlSize(.mini)
    }

    private func errorDetails(_ error: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(error)
                .font(.caption)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
            if let recovery = coordinator.lastErrorRecovery {
                Button("Open System Settings") {
                    NSWorkspace.shared.open(recovery.settingsURL)
                }
                .controlSize(.small)
            }
        }
    }

    private func updateBanner(_ update: AvailableUpdate) -> some View {
        Link(destination: update.downloadURL) {
            Label {
                Text("Version \(update.version.description) is available")
            } icon: {
                Image(systemName: "arrow.down.circle")
            }
            .font(.caption)
        }
    }

    private var footer: some View {
        HStack {
            Button(primaryActionTitle) {
                coordinator.toggle()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(coordinator.isAuthorizing)

            if coordinator.state == .playing {
                Button("Re-sync") { coordinator.resync() }
            }

            Spacer()

            Button {
                showHistory()
            } label: {
                Image(systemName: "clock.arrow.circlepath")
                    .accessibilityLabel("History")
            }
            .buttonStyle(.borderless)
            .help("Recognition history")

            Button {
                showSettings()
            } label: {
                Image(systemName: "gearshape")
                    .accessibilityLabel("Settings and Help")
            }
            .buttonStyle(.borderless)
            .help("Settings and Help")

            Button("Quit") { NSApp.terminate(nil) }
        }
    }

    // MARK: - State styling

    private var stateLabel: LocalizedStringKey {
        switch coordinator.state {
        case .disabled: return coordinator.isAuthorizing ? "Authorizing" : "Disabled"
        case .active: return coordinator.isStreamingToRecognizer ? "Recognizing" : "Active"
        case .startingPlayback: return "Starting"
        case .playing: return "Playing"
        }
    }

    private var meterCaption: LocalizedStringKey {
        if coordinator.isProbing {
            return coordinator.isStreamingToRecognizer
                ? "Checking the room for changes"
                : "Listening to the room"
        }
        return coordinator.isStreamingToRecognizer
            ? "Recognition stream active"
            : "Waiting for music above the threshold"
    }

    private var primaryActionTitle: LocalizedStringKey {
        if coordinator.isAuthorizing { return "Authorizing…" }
        return coordinator.state == .disabled ? "Enable" : "Disable"
    }

    private var formattedSyncAdjustment: String {
        let milliseconds = Int(coordinator.syncAdjustmentMilliseconds.rounded())
        return milliseconds >= 0 ? "+\(milliseconds) ms" : "\(milliseconds) ms"
    }

    private func formattedTime(_ time: TimeInterval) -> String {
        Duration.seconds(time).formatted(.time(pattern: .minuteSecond))
    }

    private var stateColor: Color {
        switch coordinator.state {
        case .disabled: return .secondary
        case .active: return .orange
        case .startingPlayback: return .blue
        case .playing: return .green
        }
    }
}

/// Rounded cover art with a neutral placeholder while loading or missing.
struct ArtworkView: View {
    let url: URL?
    let size: CGFloat

    var body: some View {
        AsyncImage(url: url) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            ZStack {
                RoundedRectangle(cornerRadius: size / 6).fill(.quaternary)
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.4))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size / 6))
        .accessibilityHidden(true)
    }
}

/// A horizontal loudness bar (dBFS) with a marker at the gate threshold.
private struct LevelMeter: View {
    let level: Float  // dBFS, ~ -60...0
    let threshold: Float
    let active: Bool

    private let floor: Float = -60

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let fill = fraction(level) * width
            let mark = fraction(threshold) * width

            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(active ? Color.green : Color.orange)
                    .frame(width: max(0, fill))
                Rectangle()
                    .fill(.primary)
                    .frame(width: 2)
                    .offset(x: mark - 1)
            }
        }
    }

    private func fraction(_ db: Float) -> CGFloat {
        let clamped = min(0, max(floor, db))
        return CGFloat((clamped - floor) / (0 - floor))
    }
}
