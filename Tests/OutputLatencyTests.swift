import XCTest

@testable import Resonance

final class OutputLatencyTests: XCTestCase {
    func testConvertsCompleteOutputPipelineFromFramesToSeconds() throws {
        let latency = try XCTUnwrap(
            OutputLatency.seconds(
                sampleRate: 48_000,
                deviceFrames: 1_056,
                safetyOffsetFrames: 14,
                bufferFrames: 512,
                streamLatencies: [0]
            )
        )

        XCTAssertEqual(latency, 0.032_958_333, accuracy: 0.000_000_001)
    }

    func testUsesLargestActiveOutputStreamLatency() throws {
        let latency = try XCTUnwrap(
            OutputLatency.seconds(
                sampleRate: 1_000,
                deviceFrames: 10,
                safetyOffsetFrames: 5,
                bufferFrames: 20,
                streamLatencies: [3, 7]
            )
        )

        XCTAssertEqual(latency, 0.042, accuracy: 0.000_001)
    }

    func testRejectsInvalidHardwareValues() {
        XCTAssertNil(
            OutputLatency.seconds(
                sampleRate: 0,
                deviceFrames: 0,
                safetyOffsetFrames: 0,
                bufferFrames: 0,
                streamLatencies: []
            )
        )
        XCTAssertNil(
            OutputLatency.seconds(
                sampleRate: 48_000,
                deviceFrames: -1,
                safetyOffsetFrames: 0,
                bufferFrames: 0,
                streamLatencies: []
            )
        )
    }
}
