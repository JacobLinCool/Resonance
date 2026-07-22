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

/// Handles app-level lifecycle: the reopen event that remains reachable when
/// macOS hides the menu bar extra, first-run onboarding, global shortcuts,
/// and the daily update check for direct-download builds.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let coordinator: AppCoordinator
    let updateChecker = UpdateChecker()
    let loginItem = LoginItemModel()
    let shortcuts: ShortcutSettings

    private let hotKeys = HotKeyCenter()
    private var controlWindowPresenter: (any ControlWindowPresenting)?
    private var settingsWindowPresenter: (any SettingsWindowPresenting)?
    private var historyWindow: PanelWindowController?
    private var onboardingWindow: PanelWindowController?

    static let onboardingCompletedKey = "hasCompletedOnboarding"

    override init() {
        coordinator = AppCoordinator()
        shortcuts = ShortcutSettings(hotKeys: hotKeys)
        super.init()
        wireHotKeys()
    }

    init(controlWindowPresenter: any ControlWindowPresenting) {
        coordinator = AppCoordinator()
        shortcuts = ShortcutSettings(hotKeys: hotKeys)
        self.controlWindowPresenter = controlWindowPresenter
        super.init()
        wireHotKeys()
    }

    init(settingsWindowPresenter: any SettingsWindowPresenting) {
        coordinator = AppCoordinator()
        shortcuts = ShortcutSettings(hotKeys: hotKeys)
        self.settingsWindowPresenter = settingsWindowPresenter
        super.init()
        wireHotKeys()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        showOnboardingIfNeeded()
        startAutomaticUpdateChecks()
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
            settingsWindowPresenter = PanelWindowController(
                title: String(localized: "Resonance Settings and Help")
            ) { [weak self] in
                guard let self else { return AnyView(EmptyView()) }
                return AnyView(
                    SettingsView(
                        coordinator: self.coordinator,
                        loginItem: self.loginItem,
                        shortcuts: self.shortcuts,
                        updateChecker: self.updateChecker
                    )
                )
            }
        }
        settingsWindowPresenter?.show()
    }

    func showHistory() {
        if historyWindow == nil {
            historyWindow = PanelWindowController(
                title: String(localized: "Recognition History")
            ) { [weak self] in
                guard let self else { return AnyView(EmptyView()) }
                return AnyView(HistoryView(history: self.coordinator.history))
            }
        }
        historyWindow?.show()
    }

    private func showControlWindow() {
        if controlWindowPresenter == nil {
            controlWindowPresenter = ControlWindowController(
                coordinator: coordinator,
                updateChecker: updateChecker,
                showSettings: { [weak self] in self?.showSettings() },
                showHistory: { [weak self] in self?.showHistory() }
            )
        }
        controlWindowPresenter?.show()
    }

    // MARK: - Onboarding

    private func showOnboardingIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: Self.onboardingCompletedKey) else { return }

        let panel = PanelWindowController(
            title: String(localized: "Welcome to Resonance")
        ) { [weak self] in
            AnyView(
                OnboardingView(
                    onGetStarted: { self?.completeOnboarding(startListening: true) },
                    onNotNow: { self?.completeOnboarding(startListening: false) }
                )
            )
        }
        onboardingWindow = panel
        panel.show()
    }

    private func completeOnboarding(startListening: Bool) {
        UserDefaults.standard.set(true, forKey: Self.onboardingCompletedKey)
        onboardingWindow?.close()
        onboardingWindow = nil
        if startListening, coordinator.state == .disabled {
            coordinator.toggle()
        }
    }

    // MARK: - Shortcuts and updates

    private func wireHotKeys() {
        hotKeys.onAction = { [weak self] action in
            switch action {
            case .toggleEnabled:
                self?.coordinator.toggle()
            case .resync:
                self?.coordinator.resync()
            }
        }
    }

    private func startAutomaticUpdateChecks() {
        guard !AppDistribution.isAppStore else { return }
        Task { [updateChecker] in
            await updateChecker.checkAutomaticallyIfDue()
        }
    }
}

/// Hosts the same SwiftUI controls as the menu bar popover in a reusable
/// standalone window. Closing the window does not stop the menu bar app.
@MainActor
final class ControlWindowController: ControlWindowPresenting {
    private let coordinator: AppCoordinator
    private let updateChecker: UpdateChecker
    private let showSettings: @MainActor () -> Void
    private let showHistory: @MainActor () -> Void
    private var windowController: NSWindowController?

    init(
        coordinator: AppCoordinator,
        updateChecker: UpdateChecker,
        showSettings: @escaping @MainActor () -> Void,
        showHistory: @escaping @MainActor () -> Void
    ) {
        self.coordinator = coordinator
        self.updateChecker = updateChecker
        self.showSettings = showSettings
        self.showHistory = showHistory
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
            rootView: ContentView(showSettings: showSettings, showHistory: showHistory)
                .environment(coordinator)
                .environment(updateChecker)
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

/// Owns one reusable titled window around a SwiftUI root view. Serves the
/// settings, history, and onboarding windows.
@MainActor
final class PanelWindowController: SettingsWindowPresenting {
    private let title: String
    private let makeContent: @MainActor () -> AnyView
    private var windowController: NSWindowController?

    init(title: String, makeContent: @escaping @MainActor () -> AnyView) {
        self.title = title
        self.makeContent = makeContent
    }

    func show() {
        let controller = windowController ?? makeWindowController()
        windowController = controller

        NSApp.activate()
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
    }

    func close() {
        windowController?.window?.close()
    }

    private func makeWindowController() -> NSWindowController {
        let hostingController = NSHostingController(rootView: makeContent())
        let window = NSWindow(contentViewController: hostingController)
        window.title = title
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.tabbingMode = .disallowed
        window.isReleasedWhenClosed = false
        window.center()
        return NSWindowController(window: window)
    }
}
