import AppKit
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
}

@MainActor
private final class ControlWindowPresenterSpy: ControlWindowPresenting {
    private(set) var showCount = 0

    func show() {
        showCount += 1
    }
}
