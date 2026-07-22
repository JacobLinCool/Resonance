import SwiftUI

/// The Settings and Help window: an About-style header followed by grouped
/// sections in the System Settings visual style — functional settings first,
/// then the explanatory help content.
struct SettingsView: View {
    @Bindable var coordinator: AppCoordinator
    @Bindable var loginItem: LoginItemModel
    @Bindable var shortcuts: ShortcutSettings
    let updateChecker: UpdateChecker

    var body: some View {
        VStack(spacing: 0) {
            header
            Form {
                general
                if !AppDistribution.isAppStore {
                    updates
                }
                requirements
                controls
                privacy
                links
            }
            .formStyle(.grouped)
        }
        .frame(width: 560, height: 700)
    }

    private var header: some View {
        VStack(spacing: 4) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 76, height: 76)
                .accessibilityHidden(true)
            Text("Resonance: Music Sync")
                .font(.title2.weight(.semibold))
            Text("Sync to the Music Around You")
                .foregroundStyle(.secondary)
            Text(versionLabel)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 20)
        .padding(.bottom, 10)
    }

    private var general: some View {
        Section("General") {
            SettingToggle(
                isOn: $loginItem.isEnabled,
                title: "Open at login",
                text: "Start Resonance automatically when you log in."
            )
            if let error = loginItem.lastError {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            SettingToggle(
                isOn: $coordinator.matchNotificationsEnabled,
                title: "Match notifications",
                text: "Show a notification when a recognized song starts playing."
            )
            SettingToggle(
                isOn: $coordinator.followRoomEnabled,
                title: "Follow the room",
                text: """
                    Briefly re-listen during playback so a changed song switches \
                    automatically and timing drift is corrected.
                    """
            )
            SettingToggle(
                isOn: $shortcuts.isEnabled,
                title: "Global shortcuts",
                text: shortcutSummary
            )
        }
    }

    private var shortcutSummary: LocalizedStringKey {
        let toggleKeys = HotKeyAction.toggleEnabled.keyEquivalentLabel
        let resyncKeys = HotKeyAction.resync.keyEquivalentLabel
        return "\(toggleKeys) toggles listening anywhere. \(resyncKeys) re-syncs."
    }

    private var updates: some View {
        Section("Updates") {
            if let update = updateChecker.availableUpdate {
                Link(destination: update.downloadURL) {
                    HStack {
                        Label {
                            Text("Version \(update.version.description) is available")
                        } icon: {
                            Image(systemName: "arrow.down.circle.fill")
                                .foregroundStyle(.blue)
                        }
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
            }
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Check for updates")
                    Text(updateStatus)
                        .font(.callout)
                        .foregroundStyle(updateChecker.lastCheckFailed ? .red : .secondary)
                }
                Spacer()
                Button {
                    Task { await updateChecker.checkNow() }
                } label: {
                    if updateChecker.isChecking {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Check Now")
                    }
                }
                .disabled(updateChecker.isChecking)
            }
        }
    }

    private var updateStatus: LocalizedStringKey {
        if updateChecker.lastCheckFailed {
            return "The update check failed. Try again later."
        }
        if updateChecker.availableUpdate != nil {
            return "A newer release is ready on GitHub."
        }
        if updateChecker.lastSuccessfulCheck != nil {
            return "Resonance is up to date."
        }
        return "New releases are checked once a day."
    }

    private var requirements: some View {
        Section("Requirements") {
            ExplanationRow(
                icon: "music.note",
                tint: .pink,
                title: "Apple Music subscription",
                text: """
                    Synchronized playback starts songs through Apple Music, \
                    which requires an active subscription.
                    """
            )
            ExplanationRow(
                icon: "mic.fill",
                tint: .orange,
                title: "Microphone and Media & Apple Music access",
                text: "Both permissions are requested the first time you press Enable."
            )
            ExplanationRow(
                icon: "wifi",
                tint: .blue,
                title: "Internet connection",
                text: "Recognition and playback both need to reach Apple's servers."
            )
        }
    }

    private var controls: some View {
        Section("How the Controls Work") {
            ExplanationRow(
                icon: "play.fill",
                tint: .green,
                title: "Enable",
                text: """
                    Requests the required permissions and starts listening for nearby music. \
                    After a match, microphone recognition stops and Resonance starts the \
                    corresponding Apple Music song at the estimated matching position.
                    """
            )
            ExplanationRow(
                icon: "stop.fill",
                tint: .red,
                title: "Disable",
                text: """
                    Stops microphone recognition and any Apple Music playback started by \
                    Resonance, then clears the current match.
                    """
            )
            ExplanationRow(
                icon: "arrow.clockwise",
                tint: .teal,
                title: "Re-sync",
                text: """
                    Stops the current playback and listens again for a fresh match. Use this \
                    when the room changes songs or the timing no longer feels aligned.
                    """
            )
            ExplanationRow(
                icon: "waveform",
                tint: .purple,
                title: "Loudness threshold",
                text: """
                    Controls how loud nearby audio must be before it is sent to ShazamKit \
                    for recognition.
                    """
            )
            ExplanationRow(
                icon: "plusminus",
                tint: .indigo,
                title: "Sync adjustment",
                text: """
                    Moves playback up to 500 ms earlier or later. The adjustment is saved \
                    separately for each audio output device and restored when you switch.
                    """
            )
            ExplanationRow(
                icon: "clock.arrow.circlepath",
                tint: .brown,
                title: "History",
                text: """
                    Every recognized song is kept in the history window, with a link back \
                    to Apple Music.
                    """
            )
        }
    }

    private var privacy: some View {
        Section("Privacy") {
            ExplanationRow(
                icon: "hand.raised.fill",
                tint: .gray,
                title: "Your audio stays yours",
                text: """
                    Resonance does not record or retain microphone audio, operate \
                    developer-controlled servers, include analytics, or require an account.
                    """
            )
            LinkRow(
                title: "Privacy Policy",
                systemImage: "doc.text",
                destination: AppLinks.privacyPolicy
            )
        }
    }

    private var links: some View {
        Section("More Information") {
            LinkRow(
                title: "Support",
                systemImage: "questionmark.circle",
                destination: AppLinks.support
            )
            LinkRow(
                title: "Source Code",
                systemImage: "chevron.left.forwardslash.chevron.right",
                destination: AppLinks.repository
            )
        }
    }

    private var versionLabel: String {
        let dictionary = Bundle.main.infoDictionary
        guard let version = dictionary?["CFBundleShortVersionString"] as? String,
            let build = dictionary?["CFBundleVersion"] as? String
        else {
            preconditionFailure("The application bundle must define version and build strings")
        }
        return String(localized: "Version \(version) (\(build))")
    }
}

/// A titled switch row with a secondary explanation, matching System Settings.
private struct SettingToggle: View {
    @Binding var isOn: Bool
    let title: LocalizedStringKey
    let text: LocalizedStringKey

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(text)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .toggleStyle(.switch)
        .controlSize(.small)
    }
}

/// A titled row with a tinted icon badge, in the style of System Settings.
private struct ExplanationRow: View {
    let icon: String
    let tint: Color
    let title: LocalizedStringKey
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            IconBadge(systemImage: icon, tint: tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(text)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct IconBadge: View {
    let systemImage: String
    let tint: Color

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 26, height: 26)
            .background(tint.gradient, in: RoundedRectangle(cornerRadius: 6))
            .accessibilityHidden(true)
    }
}

/// A full-width row that opens an external destination, marked with an
/// outward arrow so the jump out of the app is predictable.
private struct LinkRow: View {
    let title: LocalizedStringKey
    let systemImage: String
    let destination: URL

    var body: some View {
        Link(destination: destination) {
            HStack {
                Label(title, systemImage: systemImage)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
    }
}
