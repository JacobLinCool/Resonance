import SwiftUI

struct SettingsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                requirements
                controls
                privacy
                links
            }
            .padding(24)
        }
        .frame(width: 560, height: 620)
        .navigationTitle("Resonance Settings")
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 64, height: 64)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text("Resonance: Music Sync")
                    .font(.title2.weight(.semibold))
                Text("Sync to the Music Around You")
                    .foregroundStyle(.secondary)
                Text(versionLabel)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var requirements: some View {
        SettingsSection(
            title: "Requirements",
            systemImage: "checkmark.circle"
        ) {
            Text(
                "Synchronized playback requires an active Apple Music subscription, "
                    + "Microphone and Media & Apple Music permission, and an internet connection."
            )
        }
    }

    private var controls: some View {
        SettingsSection(
            title: "How the controls work",
            systemImage: "slider.horizontal.3"
        ) {
            VStack(alignment: .leading, spacing: 14) {
                ControlExplanation(
                    title: "Enable",
                    text: "Requests the required permissions and starts listening for nearby music. "
                        + "After a match, microphone recognition stops and Resonance starts the "
                        + "corresponding Apple Music song at the estimated matching position."
                )
                ControlExplanation(
                    title: "Disable",
                    text: "Stops microphone recognition and any Apple Music playback started by "
                        + "Resonance, then clears the current match."
                )
                ControlExplanation(
                    title: "Re-sync",
                    text: "Stops the current playback and listens again for a fresh match. Use this "
                        + "when the room changes songs or the timing no longer feels aligned."
                )
                ControlExplanation(
                    title: "Loudness threshold",
                    text: "Controls how loud nearby audio must be before it is sent to ShazamKit "
                        + "for recognition."
                )
                ControlExplanation(
                    title: "Sync adjustment",
                    text: "Moves playback up to 500 ms earlier or later. The adjustment is saved "
                        + "on this Mac and reused the next time Resonance runs."
                )
            }
        }
    }

    private var privacy: some View {
        SettingsSection(
            title: "Privacy",
            systemImage: "hand.raised"
        ) {
            VStack(alignment: .leading, spacing: 10) {
                Text(
                    "Resonance does not record or retain microphone audio, operate "
                        + "developer-controlled servers, include analytics, or require an account."
                )
                Link(destination: AppLinks.privacyPolicy) {
                    Label("Read the Privacy Policy", systemImage: "arrow.up.right.square")
                }
            }
        }
    }

    private var links: some View {
        SettingsSection(
            title: "More information",
            systemImage: "info.circle"
        ) {
            HStack(spacing: 18) {
                Link("Support", destination: AppLinks.support)
                Link("Source Code", destination: AppLinks.repository)
            }
        }
    }

    private var versionLabel: String {
        let dictionary = Bundle.main.infoDictionary
        guard let version = dictionary?["CFBundleShortVersionString"] as? String,
            let build = dictionary?["CFBundleVersion"] as? String
        else {
            preconditionFailure("The application bundle must define version and build strings")
        }
        return "Version \(version) (\(build))"
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        GroupBox {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
        } label: {
            Label(title, systemImage: systemImage)
                .font(.headline)
        }
    }
}

private struct ControlExplanation: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.body.weight(.semibold))
            Text(text)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
