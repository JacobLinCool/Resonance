import AppKit
import Carbon.HIToolbox
import Observation
import os

enum HotKeyAction: UInt32, CaseIterable, Sendable {
    case toggleEnabled = 1
    case resync = 2

    var keyEquivalentLabel: String {
        switch self {
        case .toggleEnabled: "⌃⌥⌘E"
        case .resync: "⌃⌥⌘R"
        }
    }

    fileprivate var keyCode: UInt32 {
        switch self {
        case .toggleEnabled: UInt32(kVK_ANSI_E)
        case .resync: UInt32(kVK_ANSI_R)
        }
    }
}

/// Registers systemwide Carbon hot keys. `RegisterEventHotKey` works in the
/// App Sandbox and needs no accessibility permission, unlike global NSEvent
/// monitors.
@MainActor
final class HotKeyCenter {
    var onAction: (@MainActor (HotKeyAction) -> Void)?

    private var registrations: [EventHotKeyRef] = []
    private var eventHandler: EventHandlerRef?
    private let log = Logger(subsystem: AppIdentity.bundleIdentifier, category: "hotkey")

    private static let signature: OSType = 0x5253_4E43  // "RSNC"
    private static let modifiers = UInt32(controlKey | optionKey | cmdKey)

    func setEnabled(_ enabled: Bool) {
        if enabled {
            registerAll()
        } else {
            unregisterAll()
        }
    }

    private func registerAll() {
        guard registrations.isEmpty else { return }

        installHandlerIfNeeded()
        for action in HotKeyAction.allCases {
            var reference: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(signature: Self.signature, id: action.rawValue)
            let status = RegisterEventHotKey(
                action.keyCode,
                Self.modifiers,
                hotKeyID,
                GetEventDispatcherTarget(),
                0,
                &reference
            )
            if status == noErr, let reference {
                registrations.append(reference)
            } else {
                log.error("hot key registration failed: \(status, privacy: .public)")
            }
        }
    }

    private func unregisterAll() {
        for registration in registrations {
            UnregisterEventHotKey(registration)
        }
        registrations.removeAll()
    }

    private func installHandlerIfNeeded() {
        guard eventHandler == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(
            GetEventDispatcherTarget(),
            hotKeyEventHandler,
            1,
            &eventType,
            selfPointer,
            &eventHandler
        )
        if status != noErr {
            log.error("hot key handler installation failed: \(status, privacy: .public)")
        }
    }

    fileprivate func handle(id: EventHotKeyID) {
        guard id.signature == Self.signature,
            let action = HotKeyAction(rawValue: id.id)
        else { return }
        onAction?(action)
    }
}

/// Persists the global-shortcuts toggle and applies it to the hot key center.
/// Off by default: stealing systemwide key combinations is opt-in.
@MainActor
@Observable
final class ShortcutSettings {
    var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            settings.set(isEnabled, forKey: Self.enabledKey)
            hotKeys.setEnabled(isEnabled)
        }
    }

    @ObservationIgnored private let hotKeys: HotKeyCenter
    @ObservationIgnored private let settings: UserDefaults

    static let enabledKey = "globalShortcutsEnabled"

    init(hotKeys: HotKeyCenter, settings: UserDefaults = .standard) {
        self.hotKeys = hotKeys
        self.settings = settings
        isEnabled = settings.object(forKey: Self.enabledKey) as? Bool ?? false
        hotKeys.setEnabled(isEnabled)
    }
}

/// Carbon dispatches hot-key events on the main thread, so hopping back onto
/// the main actor is an assertion rather than a scheduling round trip.
private func hotKeyEventHandler(
    _ handlerCall: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }

    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr else { return status }

    let center = Unmanaged<HotKeyCenter>.fromOpaque(userData).takeUnretainedValue()
    MainActor.assumeIsolated {
        center.handle(id: hotKeyID)
    }
    return noErr
}
