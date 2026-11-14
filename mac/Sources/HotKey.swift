import Carbon.HIToolbox
import Foundation

/// System-wide shortcut via Carbon RegisterEventHotKey (works without Accessibility permission).
/// One event handler is shared by every shortcut: installing the same handler again on the application target
/// fails (-9866), which would leave every shortcut after the first unregistered.
final class HotKey {
    private var ref: EventHotKeyRef?
    private let action: () -> Void
    private static var instances: [UInt32: HotKey] = [:]
    private static var nextID: UInt32 = 1
    private static var handlerInstalled = false

    private static func installHandler() -> Bool {
        if handlerInstalled { return true }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var hk = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
            guard let target = HotKey.instances[hk.id] else { return OSStatus(eventNotHandledErr) }
            DispatchQueue.main.async { target.action() }
            return noErr
        }, 1, &spec, nil, nil)
        handlerInstalled = status == noErr
        return handlerInstalled
    }

    /// keyCode: kVK_* constant. modifiers: Carbon flags (optionKey | shiftKey ...).
    init?(keyCode: Int, modifiers: Int, action: @escaping () -> Void) {
        self.action = action
        guard HotKey.installHandler() else { return nil }
        let id = HotKey.nextID
        HotKey.nextID += 1
        let hotKeyID = EventHotKeyID(signature: OSType(0x47514149 /* 'GQAI' */), id: id)
        guard RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), hotKeyID, GetApplicationEventTarget(), 0, &ref) == noErr else {
            return nil
        }
        HotKey.instances[id] = self
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
    }
}
