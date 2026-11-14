import AppKit
import ApplicationServices

/// Pastes text into the app that was in front when recording started with ⌥⇧R (or the menu bar item).
/// Uses the clipboard + a synthesized ⌘V, then restores the previous clipboard. Needs Accessibility permission;
/// without it the text is only copied to the clipboard.
final class TextInserter {
    private var requested: (app: NSRunningApplication?, at: Date)?
    private(set) var target: NSRunningApplication?

    /// Called right before the hotkey/menu asks the page to start: remember the front app (not ourselves).
    func noteStartRequest() {
        let front = NSWorkspace.shared.frontmostApplication
        requested = (front?.processIdentifier == getpid() ? nil : front, Date())
    }

    /// Called when the page reports recording started. Started from our own window → no target.
    func recordingStarted() {
        if let r = requested, Date().timeIntervalSince(r.at) < 5 { target = r.app } else { target = nil }
        requested = nil
    }

    /// Registers the app in Settings → Accessibility (it only appears there after asking) and shows the system prompt.
    @discardableResult
    func requestPermission() -> Bool {
        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
    }

    func insert(_ text: String, done: @escaping (String, Bool) -> Void) {
        guard let app = target, !app.isTerminated else {
            return done("앱 창에서 시작해 넣을 앱이 없습니다. ⌥⇧R로 시작하면 앞 앱 입력창에 넣습니다.", false)
        }
        target = nil
        let name = app.localizedName ?? "앞 앱"
        let pb = NSPasteboard.general
        guard AXIsProcessTrusted() else {
            pb.clearContents(); pb.setString(text, forType: .string)
            // Shows the system prompt that leads to Settings; the user turns the permission on there.
            _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
            return done("손쉬운 사용 권한이 없어 클립보드에 복사만 했습니다. \(name)에서 ⌘V로 붙여 넣으세요.", false)
        }
        // Keep the user's clipboard so it can be restored after pasting.
        let saved: [[(NSPasteboard.PasteboardType, Data)]] = (pb.pasteboardItems ?? []).map { item in
            item.types.compactMap { t in item.data(forType: t).map { (t, $0) } }
        }
        pb.clearContents()
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        item.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))  // clipboard managers skip it
        pb.writeObjects([item])
        let ours = pb.changeCount
        app.activate()
        waitFront(app, tries: 20) { front in
            guard front else {
                return done("\(name)을(를) 앞으로 가져오지 못해 클립보드에 남겨 두었습니다. ⌘V로 붙여 넣으세요.", false)
            }
            Self.pressPaste()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                guard pb.changeCount == ours else { return }  // something else copied meanwhile: leave it
                pb.clearContents()
                let items = saved.map { pairs -> NSPasteboardItem in
                    let i = NSPasteboardItem(); pairs.forEach { i.setData($0.1, forType: $0.0) }; return i
                }
                if !items.isEmpty { pb.writeObjects(items) }
            }
            done("\(name) 입력창에 넣었습니다 (\(text.count)자).", true)
        }
    }

    private func waitFront(_ app: NSRunningApplication, tries: Int, then: @escaping (Bool) -> Void) {
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier {
            // Small delay so the app's window is key before the keystroke arrives.
            return DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { then(true) }
        }
        guard tries > 0 else { return then(false) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { self.waitFront(app, tries: tries - 1, then: then) }
    }

    private static func pressPaste() {
        let src = CGEventSource(stateID: .combinedSessionState)
        let v: CGKeyCode = 9  // kVK_ANSI_V
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: src, virtualKey: v, keyDown: down)
            e?.flags = .maskCommand
            e?.post(tap: .cghidEventTap)
        }
    }
}
