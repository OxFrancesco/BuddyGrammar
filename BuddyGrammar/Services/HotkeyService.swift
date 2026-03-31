import Carbon
import Foundation

@MainActor
final class HotkeyService {
    private var hotKeyRefs: [UInt32: EventHotKeyRef] = [:]
    private var profileIDsByHotKeyID: [UInt32: UUID] = [:]
    private var eventHandler: EventHandlerRef?
    var onHotKey: ((UUID) -> Void)?

    init() {
        installHandler()
    }

    func register(profiles: [PromptProfile]) {
        unregisterAll()

        for (index, profile) in profiles.enumerated() {
            guard profile.isEnabled, let hotkey = profile.hotkey, hotkey.isValid else { continue }

            var hotKeyRef: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(signature: fourCharCode("BDGR"), id: UInt32(index + 1))
            let status = RegisterEventHotKey(
                hotkey.keyCode,
                hotkey.carbonModifiers,
                hotKeyID,
                GetEventDispatcherTarget(),
                0,
                &hotKeyRef
            )

            guard status == noErr, let hotKeyRef else { continue }
            hotKeyRefs[hotKeyID.id] = hotKeyRef
            profileIDsByHotKeyID[hotKeyID.id] = profile.id
        }
    }

    func unregisterAll() {
        for ref in hotKeyRefs.values {
            UnregisterEventHotKey(ref)
        }
        hotKeyRefs.removeAll()
        profileIDsByHotKeyID.removeAll()
    }

    private func installHandler() {
        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))

        InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, event, userData in
                guard let event, let userData else { return noErr }
                let service = Unmanaged<HotkeyService>.fromOpaque(userData).takeUnretainedValue()
                return service.handleHotKey(event)
            },
            1,
            &eventSpec,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
    }

    private func handleHotKey(_ event: EventRef) -> OSStatus {
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

        guard status == noErr,
              let profileID = profileIDsByHotKeyID[hotKeyID.id]
        else {
            return status
        }

        onHotKey?(profileID)
        return noErr
    }

    private func fourCharCode(_ string: String) -> OSType {
        string.utf8.reduce(0) { ($0 << 8) + OSType($1) }
    }
}
