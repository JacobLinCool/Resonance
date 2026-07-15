import XCTest

@testable import Resonance

final class LoudnessGateTests: XCTestCase {
    func testOpensAtThreshold() {
        var gate = LoudnessGate(holdBufferCount: 3)

        XCTAssertFalse(gate.update(levelDB: -51, thresholdDB: -50))
        XCTAssertTrue(gate.update(levelDB: -50, thresholdDB: -50))
    }

    func testClosesOnlyAfterConfiguredQuietPeriod() {
        var gate = LoudnessGate(holdBufferCount: 3)
        gate.update(levelDB: -40, thresholdDB: -50)

        XCTAssertTrue(gate.update(levelDB: -60, thresholdDB: -50))
        XCTAssertTrue(gate.update(levelDB: -60, thresholdDB: -50))
        XCTAssertFalse(gate.update(levelDB: -60, thresholdDB: -50))
    }

    func testLoudBufferRestartsQuietHold() {
        var gate = LoudnessGate(holdBufferCount: 2)
        gate.update(levelDB: -40, thresholdDB: -50)
        gate.update(levelDB: -60, thresholdDB: -50)
        gate.update(levelDB: -40, thresholdDB: -50)

        XCTAssertTrue(gate.update(levelDB: -60, thresholdDB: -50))
        XCTAssertFalse(gate.update(levelDB: -60, thresholdDB: -50))
    }
}
