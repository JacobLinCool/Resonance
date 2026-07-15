// The realtime tap and the ShazamKit feed traffic in non-Sendable AVFAudio types
// (AVAudioPCMBuffer, AVAudioTime) that are only touched synchronously on the
// audio thread; `@preconcurrency` keeps that documented use warning-free.
@preconcurrency import AVFoundation
import Accelerate
import Synchronization
import os

enum AudioMonitorError: LocalizedError, Equatable {
    case invalidInputFormat

    var errorDescription: String? {
        switch self {
        case .invalidInputFormat:
            "The microphone did not provide a usable audio format."
        }
    }
}

typealias AudioLevelHandler = @Sendable (Float, Bool) -> Void
typealias AudioBufferHandler = @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void
typealias AudioTapHandler = @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void

@MainActor
protocol AudioMonitorEngineBackend: AnyObject {
    var inputFormat: AVAudioFormat { get }

    func installTap(
        bufferSize: AVAudioFrameCount,
        format: AVAudioFormat,
        handler: @escaping AudioTapHandler
    )
    func prepare()
    func start() throws
    func removeTap()
    func stop()
}

@MainActor
final class AVAudioEngineBackend: AudioMonitorEngineBackend {
    private let engine: AVAudioEngine

    init(engine: AVAudioEngine = AVAudioEngine()) {
        self.engine = engine
    }

    var inputFormat: AVAudioFormat {
        engine.inputNode.outputFormat(forBus: 0)
    }

    func installTap(
        bufferSize: AVAudioFrameCount,
        format: AVAudioFormat,
        handler: @escaping AudioTapHandler
    ) {
        let tapBlock = Self.makeRealtimeTapBlock(handler)
        engine.inputNode.installTap(
            onBus: 0,
            bufferSize: bufferSize,
            format: format,
            block: tapBlock
        )
    }

    /// Converts the Sendable processor into AVFAudio's legacy block type from a
    /// nonisolated context. Creating an adapter closure in `installTap` would
    /// inherit MainActor isolation and trap on CoreAudio's realtime queue.
    nonisolated static func makeRealtimeTapBlock(
        _ handler: @escaping AudioTapHandler
    ) -> AVAudioNodeTapBlock {
        handler
    }

    func prepare() {
        engine.prepare()
    }

    func start() throws {
        try engine.start()
    }

    func removeTap() {
        engine.inputNode.removeTap(onBus: 0)
    }

    func stop() {
        engine.stop()
    }
}

@MainActor
protocol AudioMonitoring: AnyObject {
    var onLevel: AudioLevelHandler? { get set }
    var onGatedBuffer: AudioBufferHandler? { get set }
    var thresholdDB: Float { get set }

    func start() throws
    func stop()
}

/// Monitors microphone input and reports its loudness. Once the level crosses
/// the threshold, a short hold period keeps the ShazamKit stream continuous
/// through quiet passages.
@MainActor
final class AudioMonitor: AudioMonitoring {
    private enum EngineState {
        case stopped
        case tapInstalled
        case running
    }

    /// (smoothed dBFS, gate-open), delivered on the audio thread.
    var onLevel: AudioLevelHandler?

    /// A native microphone buffer and capture time, delivered synchronously on
    /// the audio thread while the gate is open.
    var onGatedBuffer: AudioBufferHandler?

    var thresholdDB: Float {
        get { threshold.load() }
        set { threshold.store(newValue) }
    }

    private let backend: any AudioMonitorEngineBackend
    private let threshold = AtomicThreshold(-50)
    private var engineState = EngineState.stopped

    private let log = Logger(subsystem: AppIdentity.bundleIdentifier, category: "audio")

    init(backend: any AudioMonitorEngineBackend = AVAudioEngineBackend()) {
        self.backend = backend
    }

    func start() throws {
        guard engineState == .stopped else { return }

        let format = backend.inputFormat
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw AudioMonitorError.invalidInputFormat
        }

        let targetBufferDuration = 0.2
        let bufferSize = AVAudioFrameCount(
            max(1_024, Int((targetBufferDuration * format.sampleRate).rounded()))
        )
        let holdBufferCount = max(1, Int((2.5 * format.sampleRate) / Double(bufferSize)))
        let processor = AudioTapProcessor(
            holdBufferCount: holdBufferCount,
            threshold: threshold,
            onLevel: onLevel,
            onGatedBuffer: onGatedBuffer
        )

        backend.installTap(bufferSize: bufferSize, format: format) { buffer, when in
            processor.process(buffer, at: when)
        }
        engineState = .tapInstalled

        do {
            backend.prepare()
            try backend.start()
            engineState = .running
            log.info("started: \(format.sampleRate, privacy: .public) Hz, \(format.channelCount) ch")
        } catch {
            cleanUpEngine()
            throw error
        }
    }

    func stop() {
        guard engineState != .stopped else { return }

        cleanUpEngine()
    }

    private func cleanUpEngine() {
        backend.removeTap()
        backend.stop()
        engineState = .stopped
    }
}

/// Pure hysteresis state used by the audio-thread processor and unit tests.
struct LoudnessGate {
    private(set) var isOpen = false
    private var quietBufferCount = 0
    let holdBufferCount: Int

    init(holdBufferCount: Int) {
        precondition(holdBufferCount > 0)
        self.holdBufferCount = holdBufferCount
    }

    @discardableResult
    mutating func update(levelDB: Float, thresholdDB: Float) -> Bool {
        if levelDB >= thresholdDB {
            isOpen = true
            quietBufferCount = 0
        } else if isOpen {
            quietBufferCount += 1
            if quietBufferCount >= holdBufferCount {
                isOpen = false
                quietBufferCount = 0
            }
        }
        return isOpen
    }
}

private final class AtomicThreshold: Sendable {
    private let storage: Atomic<Float>

    init(_ value: Float) {
        storage = Atomic(value)
    }

    func load() -> Float {
        storage.load(ordering: .relaxed)
    }

    func store(_ value: Float) {
        storage.store(value, ordering: .relaxed)
    }
}

/// Mutable fields here are confined to AVAudioEngine's serial tap callback.
/// The only cross-thread value is the lock-free atomic threshold; callbacks are
/// immutable Sendable values captured before the tap starts.
private final class AudioTapProcessor: @unchecked Sendable {
    private let threshold: AtomicThreshold
    private let onLevel: AudioLevelHandler?
    private let onGatedBuffer: AudioBufferHandler?

    private var smoothedDB: Float = -80
    private let smoothing: Float = 0.25
    private var gate: LoudnessGate

    private let log = Logger(subsystem: AppIdentity.bundleIdentifier, category: "audio")

    init(
        holdBufferCount: Int,
        threshold: AtomicThreshold,
        onLevel: AudioLevelHandler?,
        onGatedBuffer: AudioBufferHandler?
    ) {
        self.threshold = threshold
        self.onLevel = onLevel
        self.onGatedBuffer = onGatedBuffer
        self.gate = LoudnessGate(holdBufferCount: holdBufferCount)
    }

    func process(_ buffer: AVAudioPCMBuffer, at time: AVAudioTime) {
        guard let channel = buffer.floatChannelData, buffer.frameLength > 0 else { return }

        var meanSquare: Float = 0
        for channelIndex in 0..<Int(buffer.format.channelCount) {
            var channelRMS: Float = 0
            vDSP_rmsqv(
                channel[channelIndex],
                1,
                &channelRMS,
                vDSP_Length(buffer.frameLength)
            )
            meanSquare += channelRMS * channelRMS
        }
        let rms = sqrt(meanSquare / Float(buffer.format.channelCount))
        let instantDB = rms > 0 ? 20 * log10(rms) : -80
        smoothedDB += smoothing * (instantDB - smoothedDB)

        let wasOpen = gate.isOpen
        let isOpen = gate.update(levelDB: smoothedDB, thresholdDB: threshold.load())
        if isOpen != wasOpen {
            if isOpen {
                log.info("gate opened at \(self.smoothedDB, privacy: .public) dBFS")
            } else {
                log.info("gate closed after sustained quiet")
            }
        }

        if isOpen {
            onGatedBuffer?(buffer, time)
        }
        onLevel?(smoothedDB, isOpen)
    }
}
