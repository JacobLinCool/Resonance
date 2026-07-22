import Foundation
import Observation
import ServiceManagement
import os

@MainActor
protocol LoginItemManaging: AnyObject {
    var isEnabled: Bool { get }
    func setEnabled(_ enabled: Bool) throws
}

/// Wraps `SMAppService.mainApp` so Resonance can start with the Mac.
@MainActor
final class MainAppLoginItem: LoginItemManaging {
    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}

/// Observable UI model for the launch-at-login toggle. Registration failures
/// roll the toggle back and surface the error text inline.
@MainActor
@Observable
final class LoginItemModel {
    var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            apply(isEnabled)
        }
    }
    private(set) var lastError: String?

    @ObservationIgnored private let loginItem: any LoginItemManaging
    @ObservationIgnored private let log = Logger(
        subsystem: AppIdentity.bundleIdentifier,
        category: "login-item"
    )

    init(loginItem: any LoginItemManaging = MainAppLoginItem()) {
        self.loginItem = loginItem
        isEnabled = loginItem.isEnabled
    }

    private func apply(_ enabled: Bool) {
        lastError = nil
        do {
            try loginItem.setEnabled(enabled)
        } catch {
            log.error("login item update failed: \(error.localizedDescription)")
            lastError = error.localizedDescription
            isEnabled = loginItem.isEnabled
        }
    }
}
