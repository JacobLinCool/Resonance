import CoreAudio
import Foundation
import os

/// The stable identity of an audio output device, used to key saved
/// per-device sync adjustments.
struct OutputDeviceInfo: Sendable, Equatable {
    let uid: String
    let name: String?
}

@MainActor
protocol OutputDeviceObserving: AnyObject {
    /// Called on the main actor whenever the system default output changes.
    var onDefaultDeviceChange: (@MainActor (OutputDeviceInfo?) -> Void)? { get set }

    var currentDevice: OutputDeviceInfo? { get }

    func start()
    func stop()
}

/// Default for tests and previews: reports no device and never fires.
@MainActor
final class NullOutputDeviceObserver: OutputDeviceObserving {
    var onDefaultDeviceChange: (@MainActor (OutputDeviceInfo?) -> Void)?
    var currentDevice: OutputDeviceInfo? { nil }

    func start() {}
    func stop() {}
}

/// Watches Core Audio's default output device so playback compensation and the
/// saved sync adjustment can follow the device the user is actually hearing.
@MainActor
final class OutputDeviceObserver: OutputDeviceObserving {
    var onDefaultDeviceChange: (@MainActor (OutputDeviceInfo?) -> Void)?

    private var isObserving = false
    private var listenerBlock: AudioObjectPropertyListenerBlock?
    private let log = Logger(subsystem: AppIdentity.bundleIdentifier, category: "device")

    private static var defaultOutputAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    var currentDevice: OutputDeviceInfo? {
        Self.readDefaultOutputDevice()
    }

    func start() {
        guard !isObserving else { return }

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.publishChange()
            }
        }
        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &Self.defaultOutputAddress,
            .main,
            block
        )
        guard status == noErr else {
            log.error("failed to observe default output device: \(status, privacy: .public)")
            return
        }
        listenerBlock = block
        isObserving = true
    }

    func stop() {
        guard isObserving, let listenerBlock else { return }

        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &Self.defaultOutputAddress,
            .main,
            listenerBlock
        )
        self.listenerBlock = nil
        isObserving = false
    }

    private func publishChange() {
        let device = Self.readDefaultOutputDevice()
        log.info("default output changed: \(device?.name ?? "unknown", privacy: .public)")
        onDefaultDeviceChange?(device)
    }

    private static func readDefaultOutputDevice() -> OutputDeviceInfo? {
        var deviceID = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultOutputAddress,
            0,
            nil,
            &size,
            &deviceID
        )
        guard status == noErr, deviceID != kAudioObjectUnknown else { return nil }

        guard let uid = readString(deviceID, selector: kAudioDevicePropertyDeviceUID) else {
            return nil
        }
        let name = readString(deviceID, selector: kAudioObjectPropertyName)
        return OutputDeviceInfo(uid: uid, name: name)
    }

    private static func readString(
        _ deviceID: AudioObjectID,
        selector: AudioObjectPropertySelector
    ) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: CFString?
        var size = UInt32(MemoryLayout<CFString?>.size)
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, pointer)
        }
        guard status == noErr, let value else { return nil }
        return value as String
    }
}
