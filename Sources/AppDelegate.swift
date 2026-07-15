import AppKit
import SwiftUI

@MainActor
protocol ControlWindowPresenting: AnyObject {
    func show()
}

/// Handles the app-level reopen event that remains reachable when macOS
/// temporarily hides the menu bar extra because the menu bar is full.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let coordinator: AppCoordinator

    private var controlWindowPresenter: (any ControlWindowPresenting)?

    override init() {
        coordinator = AppCoordinator()
        super.init()
    }

    init(controlWindowPresenter: any ControlWindowPresenting) {
        coordinator = AppCoordinator()
        self.controlWindowPresenter = controlWindowPresenter
        super.init()
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        showControlWindow()
        return false
    }

    private func showControlWindow() {
        if controlWindowPresenter == nil {
            controlWindowPresenter = ControlWindowController(coordinator: coordinator)
        }
        controlWindowPresenter?.show()
    }
}

/// Hosts the same SwiftUI controls as the menu bar popover in a reusable
/// standalone window. Closing the window does not stop the menu bar app.
@MainActor
final class ControlWindowController: ControlWindowPresenting {
    private let coordinator: AppCoordinator
    private var windowController: NSWindowController?

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
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
            rootView: ContentView()
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
