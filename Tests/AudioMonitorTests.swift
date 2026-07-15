@preconcurrency import AVFoundation
import Foundation
import Synchronization
import XCTest

@testable import Resonance

@MainActor
final class AudioMonitorTests: XCTestCase {
    func testRejectsZeroSampleRateBeforeInstallingTap() throws {
        let format = try XCTUnwrap(
            AVAudioFormat(standardFormatWithSampleRate: 0, channels: 1)
        )

        assertInvalidInputFormat(format)
    }

    func testRejectsZeroChannelsBeforeInstallingTap() throws {
        let format = try XCTUnwrap(
            AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 0)
        )

        assertInvalidInputFormat(format)
    }

    func testStartFailureRemovesTapAndStopsEngine() throws {
        let backend = FakeAudioMonitorEngineBackend(inputFormat: try makeValidFormat())
        backend.startError = .failed
        let monitor = AudioMonitor(backend: backend)

        XCTAssertThrowsError(try monitor.start()) { error in
            XCTAssertEqual(error as? TestStartError, .failed)
        }

        XCTAssertEqual(backend.events, [.installTap, .prepare, .start, .removeTap, .stop])
        XCTAssertEqual(backend.activeTapCount, 0)
        XCTAssertFalse(backend.isEngineRunning)
    }

    func testRetryAfterStartFailureSucceedsWithoutDuplicateTap() throws {
        let backend = FakeAudioMonitorEngineBackend(inputFormat: try makeValidFormat())
        backend.startError = .failed
        let monitor = AudioMonitor(backend: backend)

        XCTAssertThrowsError(try monitor.start())
        backend.startError = nil
        try monitor.start()

        XCTAssertEqual(backend.installTapCount, 2)
        XCTAssertEqual(backend.maximumActiveTapCount, 1)
        XCTAssertEqual(backend.duplicateTapInstallCount, 0)
        XCTAssertEqual(backend.activeTapCount, 1)
        XCTAssertTrue(backend.isEngineRunning)

        monitor.stop()
    }

    func testSuccessfulStartIsIdempotent() throws {
        let backend = FakeAudioMonitorEngineBackend(inputFormat: try makeValidFormat())
        let monitor = AudioMonitor(backend: backend)

        try monitor.start()
        try monitor.start()

        XCTAssertEqual(backend.installTapCount, 1)
        XCTAssertEqual(backend.prepareCount, 1)
        XCTAssertEqual(backend.startCount, 1)
        XCTAssertEqual(backend.activeTapCount, 1)
        XCTAssertTrue(backend.isEngineRunning)

        monitor.stop()
    }

    func testStopRemovesTapAndStopsEngineExactlyOnce() throws {
        let backend = FakeAudioMonitorEngineBackend(inputFormat: try makeValidFormat())
        let monitor = AudioMonitor(backend: backend)
        try monitor.start()

        monitor.stop()
        monitor.stop()

        XCTAssertEqual(backend.removeTapCount, 1)
        XCTAssertEqual(backend.stopCount, 1)
        XCTAssertEqual(backend.activeTapCount, 0)
        XCTAssertFalse(backend.isEngineRunning)
        XCTAssertEqual(backend.events, [.installTap, .prepare, .start, .removeTap, .stop])
    }

    func testTapHandlerProcessesBufferSynchronously() throws {
        let format = try makeValidFormat()
        let backend = FakeAudioMonitorEngineBackend(inputFormat: format)
        let monitor = AudioMonitor(backend: backend)
        let callbackState = Mutex(CallbackState())
        monitor.thresholdDB = -100
        monitor.onLevel = { _, isGateOpen in
            callbackState.withLock {
                $0.levelCount += 1
                $0.isGateOpen = isGateOpen
            }
        }
        monitor.onGatedBuffer = { _, _ in
            callbackState.withLock { $0.bufferCount += 1 }
        }
        try monitor.start()
        let buffer = try makeSilentBuffer(format: format)

        backend.emit(buffer: buffer, at: AVAudioTime(sampleTime: 0, atRate: format.sampleRate))

        callbackState.withLock {
            XCTAssertEqual($0.levelCount, 1)
            XCTAssertEqual($0.bufferCount, 1)
            XCTAssertTrue($0.isGateOpen)
        }
        monitor.stop()
    }

    func testRealtimeTapBlockRunsOutsideMainActor() async throws {
        let format = try makeValidFormat()
        let buffer = try makeSilentBuffer(format: format)
        let time = AVAudioTime(sampleTime: 0, atRate: format.sampleRate)
        let callback = expectation(description: "realtime tap callback")
        let callbackWasOnMainThread = Mutex<Bool?>(nil)
        let tapBlock = AVAudioEngineBackend.makeRealtimeTapBlock { _, _ in
            callbackWasOnMainThread.withLock { $0 = Thread.isMainThread }
            callback.fulfill()
        }
        let invocation = SendableTapInvocation(block: tapBlock, buffer: buffer, time: time)

        DispatchQueue(label: "dev.jacoblincool.ResonanceTests.audio-tap").async {
            invocation.call()
        }

        await fulfillment(of: [callback], timeout: 1)
        XCTAssertEqual(callbackWasOnMainThread.withLock { $0 }, false)
    }

    private func assertInvalidInputFormat(
        _ format: AVAudioFormat,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let backend = FakeAudioMonitorEngineBackend(inputFormat: format)
        let monitor = AudioMonitor(backend: backend)

        XCTAssertThrowsError(try monitor.start(), file: file, line: line) { error in
            XCTAssertEqual(
                error as? AudioMonitorError,
                AudioMonitorError.invalidInputFormat,
                file: file,
                line: line
            )
        }
        XCTAssertTrue(backend.events.isEmpty, file: file, line: line)
        XCTAssertEqual(backend.activeTapCount, 0, file: file, line: line)
        XCTAssertFalse(backend.isEngineRunning, file: file, line: line)
    }

    private func makeValidFormat() throws -> AVAudioFormat {
        try XCTUnwrap(
            AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)
        )
    }

    private func makeSilentBuffer(format: AVAudioFormat) throws -> AVAudioPCMBuffer {
        let frameCount: AVAudioFrameCount = 128
        let buffer = try XCTUnwrap(
            AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)
        )
        buffer.frameLength = frameCount
        let channels = try XCTUnwrap(buffer.floatChannelData)
        for channelIndex in 0..<Int(format.channelCount) {
            channels[channelIndex].update(repeating: 0, count: Int(frameCount))
        }
        return buffer
    }
}

/// AVFAudio's tap block and buffer types lack Sendable annotations. This box
/// transfers an immutable, single-use test invocation to one serial queue.
private final class SendableTapInvocation: @unchecked Sendable {
    private let block: AVAudioNodeTapBlock
    private let buffer: AVAudioPCMBuffer
    private let time: AVAudioTime

    init(block: @escaping AVAudioNodeTapBlock, buffer: AVAudioPCMBuffer, time: AVAudioTime) {
        self.block = block
        self.buffer = buffer
        self.time = time
    }

    func call() {
        block(buffer, time)
    }
}

private struct CallbackState {
    var levelCount = 0
    var bufferCount = 0
    var isGateOpen = false
}

private enum TestStartError: Error, Equatable {
    case failed
}

@MainActor
private final class FakeAudioMonitorEngineBackend: AudioMonitorEngineBackend {
    enum Event: Equatable {
        case installTap
        case prepare
        case start
        case removeTap
        case stop
    }

    let inputFormat: AVAudioFormat
    var startError: TestStartError?

    private(set) var events: [Event] = []
    private(set) var activeTapCount = 0
    private(set) var maximumActiveTapCount = 0
    private(set) var duplicateTapInstallCount = 0
    private(set) var isEngineRunning = false
    private var tapHandler: AudioTapHandler?

    init(inputFormat: AVAudioFormat) {
        self.inputFormat = inputFormat
    }

    var installTapCount: Int {
        events.count { $0 == .installTap }
    }

    var prepareCount: Int {
        events.count { $0 == .prepare }
    }

    var startCount: Int {
        events.count { $0 == .start }
    }

    var removeTapCount: Int {
        events.count { $0 == .removeTap }
    }

    var stopCount: Int {
        events.count { $0 == .stop }
    }

    func installTap(
        bufferSize: AVAudioFrameCount,
        format: AVAudioFormat,
        handler: @escaping AudioTapHandler
    ) {
        events.append(.installTap)
        if activeTapCount > 0 {
            duplicateTapInstallCount += 1
        }
        activeTapCount += 1
        maximumActiveTapCount = max(maximumActiveTapCount, activeTapCount)
        tapHandler = handler
    }

    func prepare() {
        events.append(.prepare)
    }

    func start() throws {
        events.append(.start)
        if let startError {
            throw startError
        }
        isEngineRunning = true
    }

    func removeTap() {
        events.append(.removeTap)
        activeTapCount -= 1
        tapHandler = nil
    }

    func stop() {
        events.append(.stop)
        isEngineRunning = false
    }

    func emit(buffer: AVAudioPCMBuffer, at time: AVAudioTime) {
        guard let tapHandler else {
            preconditionFailure("Cannot emit audio without an installed tap")
        }
        tapHandler(buffer, time)
    }
}
