import AppKit
import SwiftUI

@MainActor
protocol ControlWindowPresenting: AnyObject {
    func show()
}

@MainActor
protocol SettingsWindowPresenting: AnyObject {
    func show()
}

/// Handles the app-level reopen event that remains reachable when macOS
/// temporarily hides the menu bar extra because the menu bar is full.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let coordinator: AppCoordinator

    private var controlWindowPresenter: (any ControlWindowPresenting)?
    private var settingsWindowPresenter: (any SettingsWindowPresenting)?

    override init() {
        coordinator = AppCoordinator()
        super.init()
    }

    init(controlWindowPresenter: any ControlWindowPresenting) {
        coordinator = AppCoordinator()
        self.controlWindowPresenter = controlWindowPresenter
        super.init()
    }

    init(settingsWindowPresenter: any SettingsWindowPresenting) {
        coordinator = AppCoordinator()
        self.settingsWindowPresenter = settingsWindowPresenter
        super.init()
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        showControlWindow()
        return false
    }

    func showSettings() {
        if settingsWindowPresenter == nil {
            settingsWindowPresenter = SettingsWindowController()
        }
        settingsWindowPresenter?.show()
    }

    private func showControlWindow() {
        if controlWindowPresenter == nil {
            controlWindowPresenter = ControlWindowController(
                coordinator: coordinator,
                showSettings: { [weak self] in self?.showSettings() }
            )
        }
        controlWindowPresenter?.show()
    }
}

/// Hosts the same SwiftUI controls as the menu bar popover in a reusable
/// standalone window. Closing the window does not stop the menu bar app.
@MainActor
final class ControlWindowController: ControlWindowPresenting {
    private let coordinator: AppCoordinator
    private let showSettings: @MainActor () -> Void
    private var windowController: NSWindowController?

    init(
        coordinator: AppCoordinator,
        showSettings: @escaping @MainActor () -> Void
    ) {
        self.coordinator = coordinator
        self.showSettings = showSettings
    }

    func show() {
        let controller = windowController ?? makeWindowController()
        windowController = controller

        NSApp.activate()
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
    }

    private func makeWindowController() -> NSWindowController {
        let hostingController = NSHostingController(
            rootView: ContentView(showSettings: showSettings)
                .environment(coordinator)
                .fixedSize(horizontal: false, vertical: true)
        )
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Resonance"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.titleVisibility = .hidden
        window.tabbingMode = .disallowed
        window.isReleasedWhenClosed = false
        window.center()
        return NSWindowController(window: window)
    }
}

/// Owns the single Settings and Help window shared by the menu bar popover and
/// standalone control window.
@MainActor
final class SettingsWindowController: SettingsWindowPresenting {
    private var windowController: NSWindowController?

    func show() {
        let controller = windowController ?? makeWindowController()
        windowController = controller

        NSApp.activate()
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
    }

    private func makeWindowController() -> NSWindowController {
        let hostingController = NSHostingController(rootView: SettingsView())
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Resonance Settings and Help"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.tabbingMode = .disallowed
        window.isReleasedWhenClosed = false
        window.center()
        return NSWindowController(window: window)
    }
}
