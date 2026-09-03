import AppKit
import Carbon.HIToolbox

/// System-wide shortcut, registered through Carbon's `RegisterEventHotKey`.
/// That route needs no Accessibility access, unlike a global event monitor.
@MainActor
final class HotKeyManager {
    static let shared = HotKeyManager()

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var registeredCombo: KeyCombo?

    /// Called when the shortcut fires.
    var onTrigger: (() -> Void)?

    /// Set when macOS refuses the combination, usually because something else owns it.
    private(set) var registrationFailed = false

    private static let signature: OSType = 0x444B5953  // 'DKYS'

    private init() {}

    @discardableResult
    func register(_ combo: KeyCombo?) -> Bool {
        unregister()
        guard let combo else { return true }

        installHandlerIfNeeded()

        var reference: EventHotKeyRef?
        let identifier = EventHotKeyID(signature: Self.signature, id: 1)
        let status = RegisterEventHotKey(
            combo.keyCode,
            combo.carbonModifiers,
            identifier,
            GetApplicationEventTarget(),
            0,
            &reference
        )

        guard status == noErr, reference != nil else {
            registrationFailed = true
            return false
        }
        hotKeyRef = reference
        registeredCombo = combo
        registrationFailed = false
        return true
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        registeredCombo = nil
        registrationFailed = false
    }

    fileprivate func handleTrigger() {
        onTrigger?()
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            hotKeyEventHandler,
            1,
            &eventType,
            nil,
            &handlerRef
        )
    }
}

private func hotKeyEventHandler(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    var identifier = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &identifier
    )
    guard status == noErr else { return status }
    Task { @MainActor in HotKeyManager.shared.handleTrigger() }
    return noErr
}
