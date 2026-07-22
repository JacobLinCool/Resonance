import AppKit
import SwiftUI
import XCTest

@testable import Resonance

@MainActor
final class AppDelegateTests: XCTestCase {
    func testReopenAlwaysShowsControlWindowAndSuppressesDefaultHandling() {
        let presenter = ControlWindowPresenterSpy()
        let delegate = AppDelegate(controlWindowPresenter: presenter)

        XCTAssertFalse(
            delegate.applicationShouldHandleReopen(
                NSApplication.shared,
                hasVisibleWindows: false
            )
        )
        XCTAssertFalse(
            delegate.applicationShouldHandleReopen(
                NSApplication.shared,
                hasVisibleWindows: true
            )
        )
        XCTAssertEqual(presenter.showCount, 2)
    }

    func testShowSettingsReusesTheInjectedPresenter() {
        let presenter = SettingsWindowPresenterSpy()
        let delegate = AppDelegate(settingsWindowPresenter: presenter)

        delegate.showSettings()
        delegate.showSettings()

        XCTAssertEqual(presenter.showCount, 2)
    }

    func testPanelWindowControllerCreatesOneVisibleReusableWindow() {
        let presenter = PanelWindowController(title: "Test Panel") { AnyView(Text(verbatim: "Test")) }

        presenter.show()
        let initialWindows = panelWindows
        defer { initialWindows.forEach { $0.close() } }

        XCTAssertEqual(initialWindows.count, 1)
        XCTAssertTrue(initialWindows[0].isVisible)

        presenter.show()

        XCTAssertEqual(panelWindows.count, 1)
        XCTAssertTrue(panelWindows[0] === initialWindows[0])
    }

    private var panelWindows: [NSWindow] {
        NSApp.windows.filter { $0.title == "Test Panel" }
    }
}

@MainActor
private final class SettingsWindowPresenterSpy: SettingsWindowPresenting {
    private(set) var showCount = 0

    func show() {
        showCount += 1
    }
}

@MainActor
private final class ControlWindowPresenterSpy: ControlWindowPresenting {
    private(set) var showCount = 0

    func show() {
        showCount += 1
    }
}
