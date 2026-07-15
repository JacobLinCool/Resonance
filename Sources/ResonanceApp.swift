import SwiftUI

@main
struct ResonanceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            ContentView {
                appDelegate.showSettings()
            }
            .environment(appDelegate.coordinator)
        } label: {
            // Reads only `state`, so the menu bar icon refreshes on state
            // changes — not on every loudness update.
            MenuBarLabel(coordinator: appDelegate.coordinator)
        }
        .menuBarExtraStyle(.window)
    }
}

private struct MenuBarLabel: View {
    let coordinator: AppCoordinator

    var body: some View {
        Image(systemName: coordinator.menuBarSymbol)
            .accessibilityLabel("Resonance")
    }
}
