import SwiftUI

struct ContentView: View {
    @Environment(AppCoordinator.self) private var coordinator
    let showSettings: @MainActor () -> Void

    var body: some View {
        @Bindable var coordinator = coordinator

        VStack(alignment: .leading, spacing: 14) {
            header
            Divider()
            if let song = coordinator.matchedSong {
                songDetails(song)
            }
            if coordinator.state == .active {
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
            if let error = coordinator.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
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
        VStack(alignment: .leading, spacing: 1) {
            Text(song.title).font(.body.weight(.medium)).lineLimit(1)
            if let artist = song.artist {
                Text(artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var meter: some View {
        VStack(alignment: .leading, spacing: 4) {
            LevelMeter(
                level: coordinator.level,
                threshold: Float(coordinator.thresholdDB),
                active: coordinator.isStreamingToRecognizer
            )
            .frame(height: 8)
            Text(
                coordinator.isStreamingToRecognizer
                    ? "Recognition stream active"
                    : "Waiting for music above the threshold"
            )
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }

    private var syncAdjustment: some View {
        VStack(alignment: .leading, spacing: 3) {
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
                value: Binding(
                    get: { coordinator.syncAdjustmentMilliseconds },
                    set: { coordinator.syncAdjustmentMilliseconds = $0 }
                ),
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
                Text("−500 ms")
                Spacer()
                Text("+500 ms")
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.tertiary)
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

    private var stateLabel: String {
        switch coordinator.state {
        case .disabled: return coordinator.isAuthorizing ? "Authorizing" : "Disabled"
        case .active: return coordinator.isStreamingToRecognizer ? "Recognizing" : "Active"
        case .startingPlayback: return "Starting"
        case .playing: return "Playing"
        }
    }

    private var primaryActionTitle: String {
        if coordinator.isAuthorizing { return "Authorizing…" }
        return coordinator.state == .disabled ? "Enable" : "Disable"
    }

    private var formattedSyncAdjustment: String {
        let milliseconds = Int(coordinator.syncAdjustmentMilliseconds.rounded())
        return milliseconds >= 0 ? "+\(milliseconds) ms" : "\(milliseconds) ms"
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
