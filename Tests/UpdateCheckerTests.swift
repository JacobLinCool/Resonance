import Foundation
import XCTest

@testable import Resonance

@MainActor
final class UpdateCheckerTests: XCTestCase {
    func testVersionParsingAcceptsNumericTagsOnly() {
        XCTAssertEqual(AppVersion(tag: "0.2.0")?.components, [0, 2, 0])
        XCTAssertEqual(AppVersion(tag: "v1.10")?.components, [1, 10])
        XCTAssertNil(AppVersion(tag: "0.2.0-beta.1"))
        XCTAssertNil(AppVersion(tag: "release"))
        XCTAssertNil(AppVersion(tag: ""))
    }

    func testVersionComparisonIsNumericPerComponent() throws {
        let zeroTwo = try XCTUnwrap(AppVersion(tag: "0.2"))
        let zeroTwoZero = try XCTUnwrap(AppVersion(tag: "0.2.0"))
        let zeroTen = try XCTUnwrap(AppVersion(tag: "0.10.0"))
        let one = try XCTUnwrap(AppVersion(tag: "1.0.0"))

        XCTAssertFalse(zeroTwo < zeroTwoZero)
        XCTAssertFalse(zeroTwoZero < zeroTwo)
        XCTAssertTrue(zeroTwo < zeroTen)
        XCTAssertTrue(zeroTen < one)
    }

    func testNewerReleaseBecomesAvailableUpdate() async throws {
        let checker = makeChecker(current: "0.2.0", latestTag: "v0.3.0")

        await checker.checkNow()

        let update = try XCTUnwrap(checker.availableUpdate)
        XCTAssertEqual(update.version.components, [0, 3, 0])
        XCTAssertFalse(checker.lastCheckFailed)
        XCTAssertNotNil(checker.lastSuccessfulCheck)
    }

    func testCurrentOrOlderReleaseYieldsNoUpdate() async {
        let same = makeChecker(current: "0.2.0", latestTag: "v0.2.0")
        await same.checkNow()
        XCTAssertNil(same.availableUpdate)

        let older = makeChecker(current: "0.2.0", latestTag: "v0.1.0")
        await older.checkNow()
        XCTAssertNil(older.availableUpdate)
    }

    func testPrereleaseTagIsIgnored() async {
        let checker = makeChecker(current: "0.2.0", latestTag: "v0.3.0-beta.1")

        await checker.checkNow()

        XCTAssertNil(checker.availableUpdate)
        XCTAssertFalse(checker.lastCheckFailed)
    }

    func testFetchFailureIsReportedWithoutAnUpdate() async {
        let checker = UpdateChecker(
            currentVersionText: "0.2.0",
            fetchLatest: { throw URLError(.notConnectedToInternet) },
            settings: makeSettings()
        )

        await checker.checkNow()

        XCTAssertNil(checker.availableUpdate)
        XCTAssertTrue(checker.lastCheckFailed)
    }

    func testAutomaticCheckHonorsTheDailyThrottle() async {
        let settings = makeSettings()
        let clock = MutableClock(Date(timeIntervalSince1970: 1_000_000))
        let fetchCounter = FetchCounter()
        let checker = UpdateChecker(
            currentVersionText: "0.2.0",
            fetchLatest: {
                fetchCounter.increment()
                return ("v0.2.0", URL(string: "https://example.com/release")!)
            },
            settings: settings,
            now: { clock.value }
        )

        await checker.checkAutomaticallyIfDue()
        XCTAssertEqual(fetchCounter.count, 1)

        await checker.checkAutomaticallyIfDue()
        XCTAssertEqual(fetchCounter.count, 1)

        clock.advance(by: UpdateChecker.automaticCheckInterval + 1)
        await checker.checkAutomaticallyIfDue()
        XCTAssertEqual(fetchCounter.count, 2)
    }

    private func makeChecker(current: String, latestTag: String) -> UpdateChecker {
        UpdateChecker(
            currentVersionText: current,
            fetchLatest: { (latestTag, URL(string: "https://example.com/release")!) },
            settings: makeSettings()
        )
    }

    private func makeSettings() -> UserDefaults {
        let suiteName = "UpdateCheckerTests.\(UUID().uuidString)"
        let settings = UserDefaults(suiteName: suiteName)!
        settings.removePersistentDomain(forName: suiteName)
        return settings
    }
}

/// Mutated and read on the test's main actor only.
private final class FetchCounter: @unchecked Sendable {
    private(set) var count = 0

    func increment() {
        count += 1
    }
}
