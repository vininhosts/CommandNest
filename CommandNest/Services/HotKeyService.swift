import Carbon
import Foundation

enum HotKeyError: LocalizedError {
    case registrationFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .registrationFailed(let status):
            if status == eventHotKeyExistsErr {
                return "That shortcut is already used by another app or by macOS. Choose a different shortcut in Settings."
            }
            return "Could not register the global shortcut. macOS returned status \(status)."
        }
    }
}

final class HotKeyService {
    static let shared = HotKeyService()

    var onHotKey: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private let hotKeyID = EventHotKeyID(signature: HotKeyService.fourCharacterCode("SCAI"), id: 1)

    private init() {}

    deinit {
        stop()
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }

    func start(with shortcut: GlobalKeyboardShortcut) throws {
        stop()
        try installEventHandlerIfNeeded()

        var registeredRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &registeredRef
        )

        guard status == noErr else {
            throw HotKeyError.registrationFailed(status)
        }

        hotKeyRef = registeredRef
    }

    func stop() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }

    private func installEventHandlerIfNeeded() throws {
        guard eventHandlerRef == nil else {
            return
        }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, eventRef, userData in
                guard let eventRef,
                      let userData else {
                    return noErr
                }

                var receivedID = EventHotKeyID()
                let status = GetEventParameter(
                    eventRef,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &receivedID
                )

                guard status == noErr else {
                    return status
                }

                let service = Unmanaged<HotKeyService>.fromOpaque(userData).takeUnretainedValue()
                if receivedID.signature == service.hotKeyID.signature && receivedID.id == service.hotKeyID.id {
                    DispatchQueue.main.async {
                        service.onHotKey?()
                    }
                }

                return noErr
            },
            1,
            &eventType,
            selfPointer,
            &eventHandlerRef
        )

        guard status == noErr else {
            throw HotKeyError.registrationFailed(status)
        }
    }

    private static func fourCharacterCode(_ string: String) -> OSType {
        string.utf8.prefix(4).reduce(0) { partialResult, character in
            (partialResult << 8) + OSType(character)
        }
    }
}
