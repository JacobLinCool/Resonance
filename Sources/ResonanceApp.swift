import SwiftUI

@main
struct ResonanceApp: App {
    @State private var coordinator = AppCoordinator()

    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .environment(coordinator)
        } label: {
            // Reads only `state`, so the menu bar icon refreshes on state
            // changes — not on every loudness update.
            Image(systemName: coordinator.menuBarSymbol)
        }
        .menuBarExtraStyle(.window)
    }
}
