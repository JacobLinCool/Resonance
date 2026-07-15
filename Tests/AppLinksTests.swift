import XCTest

@testable import Resonance

final class AppLinksTests: XCTestCase {
    func testPublicLinksUseHTTPSAndExpectedRepository() {
        for url in [AppLinks.privacyPolicy, AppLinks.repository, AppLinks.support] {
            XCTAssertEqual(url.scheme, "https")
            XCTAssertEqual(url.host, "github.com")
            XCTAssertTrue(url.path.hasPrefix("/JacobLinCool/Resonance"))
        }
    }
}
