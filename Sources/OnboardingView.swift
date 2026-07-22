import SwiftUI

/// First-run walkthrough: explains what Resonance does and why the permission
/// prompts are about to appear, before any of them are triggered.
struct OnboardingView: View {
    let onGetStarted: @MainActor () -> Void
    let onNotNow: @MainActor () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 88, height: 88)
                    .accessibilityHidden(true)
                Text("Welcome to Resonance")
                    .font(.title2.weight(.semibold))
                Text("Sync to the Music Around You")
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 28)
            .padding(.bottom, 20)

            VStack(alignment: .leading, spacing: 16) {
                OnboardingStep(
                    icon: "mic.fill",
                    tint: .orange,
                    title: "Listen",
                    text: "Resonance waits until nearby music rises above a loudness threshold."
                )
                OnboardingStep(
                    icon: "waveform.badge.magnifyingglass",
                    tint: .purple,
                    title: "Recognize",
                    text: "A short sample identifies the song and its exact live position."
                )
                OnboardingStep(
                    icon: "music.note",
                    tint: .pink,
                    title: "Sync",
                    text: """
                        The same song starts from Apple Music in your headphones, \
                        aligned with the room.
                        """
                )
            }
            .padding(.horizontal, 36)

            Spacer(minLength: 20)

            VStack(spacing: 12) {
                Text(
                    """
                    Get Started asks for Microphone and Media & Apple Music access. \
                    Playback needs an active Apple Music subscription.
                    """
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Button("Not Now") { onNotNow() }
                    Button("Get Started") { onGetStarted() }
                        .keyboardShortcut(.defaultAction)
                }

                Text("Resonance lives in the menu bar — look for the waveform icon.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 20)
        }
        .frame(width: 440, height: 470)
    }
}

private struct OnboardingStep: View {
    let icon: String
    let tint: Color
    let title: LocalizedStringKey
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(tint.gradient, in: RoundedRectangle(cornerRadius: 8))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.semibold))
                Text(text)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
