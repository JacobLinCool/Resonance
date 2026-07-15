@preconcurrency import AVFoundation
@preconcurrency import ShazamKit
import os

typealias RecognitionMatchHandler = @MainActor @Sendable (Match) -> Void
typealias RecognitionErrorHandler = @MainActor @Sendable (String) -> Void

protocol RecognitionServing: AnyObject, Sendable {
    var onMatch: RecognitionMatchHandler? { get set }
    var onError: RecognitionErrorHandler? { get set }

    func reset()
    func match(buffer: AVAudioPCMBuffer, at time: AVAudioTime?)
}

/// Thread-safe streaming wrapper around `SHSession`.
///
/// The audio tap reads the current session while the main actor may replace it.
/// A small unfair lock synchronizes that handoff, and delegate callbacks are
/// accepted only from the current session so a reset cannot publish stale work.
final class ShazamRecognizer: NSObject, RecognitionServing, SHSessionDelegate, @unchecked Sendable {
    var onMatch: RecognitionMatchHandler? {
        get { state.withLock { $0.onMatch } }
        set { state.withLock { $0.onMatch = newValue } }
    }

    var onError: RecognitionErrorHandler? {
        get { state.withLock { $0.onError } }
        set { state.withLock { $0.onError = newValue } }
    }

    private final class SessionBox: @unchecked Sendable {
        let session: SHSession
        let id: ObjectIdentifier

        init(_ session: SHSession) {
            self.session = session
            self.id = ObjectIdentifier(session)
        }
    }

    private struct State: Sendable {
        var session: SessionBox
        var onMatch: RecognitionMatchHandler?
        var onError: RecognitionErrorHandler?
    }

    private let state: OSAllocatedUnfairLock<State>
    private let log = Logger(subsystem: AppIdentity.bundleIdentifier, category: "shazam")

    override convenience init() {
        self.init(session: SHSession())
    }

    init(session: SHSession) {
        state = OSAllocatedUnfairLock(
            initialState: State(session: SessionBox(session), onMatch: nil, onError: nil)
        )
        super.init()
        session.delegate = self
    }

    /// Discards accumulated audio so the next attempt starts clean.
    func reset() {
        let session = SHSession()
        session.delegate = self
        let box = SessionBox(session)
        state.withLock { $0.session = box }
    }

    /// Feeds one streaming buffer synchronously from the audio thread.
    func match(buffer: AVAudioPCMBuffer, at time: AVAudioTime?) {
        let session = state.withLock { $0.session }.session
        session.matchStreamingBuffer(buffer, at: time)
    }

    // MARK: - SHSessionDelegate

    func session(_ session: SHSession, didFind match: SHMatch) {
        guard let item = match.mediaItems.first,
            let result = Match(item: item)
        else { return }

        log.info("match received")
        deliver(result, from: session)
    }

    func session(_ session: SHSession, didNotFindMatchFor signature: SHSignature, error: Error?) {
        guard let error else { return }

        let message = error.localizedDescription
        log.error("recognition failed")
        deliverFailure(message, from: session)
    }

    /// Revalidates session identity on the main actor, immediately before the
    /// callback mutates application state. A reset can otherwise occur between
    /// the delegate callback and delivery of its queued task.
    func deliver(_ match: Match, from session: SHSession) {
        let id = ObjectIdentifier(session)
        Task { @MainActor [weak self] in
            guard let self else { return }
            let handler = self.state.withLock { state in
                state.session.id == id ? state.onMatch : nil
            }
            handler?(match)
        }
    }

    func deliverFailure(_ message: String, from session: SHSession) {
        let id = ObjectIdentifier(session)
        Task { @MainActor [weak self] in
            guard let self else { return }
            let handler = self.state.withLock { state in
                state.session.id == id ? state.onError : nil
            }
            handler?(message)
        }
    }
}
