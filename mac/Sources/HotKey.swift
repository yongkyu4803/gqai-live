import Carbon.HIToolbox
import Foundation

/// System-wide shortcut via Carbon RegisterEventHotKey (works without Accessibility permission).
final class HotKey {
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void
    private static var instances: [UInt32: HotKey] = [:]
    private static var nextID: UInt32 = 1

    /// keyCode: kVK_* constant. modifiers: Carbon flags (optionKey | shiftKey ...).
    init?(keyCode: Int, modifiers: Int, action: @escaping () -> Void) {
        self.action = action
        let id = HotKey.nextID
        HotKey.nextID += 1
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var hk = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
            if let target = HotKey.instances[hk.id] { DispatchQueue.main.async { target.action() } }
            return noErr
        }, 1, &spec, nil, &handler)
        guard status == noErr else { return nil }
        let hotKeyID = EventHotKeyID(signature: OSType(0x47514149 /* 'GQAI' */), id: id)
        guard RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), hotKeyID, GetApplicationEventTarget(), 0, &ref) == noErr else {
            if let handler { RemoveEventHandler(handler) }
            return nil
        }
        HotKey.instances[id] = self
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
        if let handler { RemoveEventHandler(handler) }
    }
}
