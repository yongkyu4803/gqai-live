import AppKit
import Carbon.HIToolbox
import UserNotifications

/// GQAI Live for macOS: a window with the local page, a menu bar icon, the global shortcuts ⌃⌥R (dictation)
/// and ⌃⌥E (instruction mode), and "paste into the front app" after a recording.
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let server = ServerManager()
    let inserter = TextInserter()
    var web: WebWindow!
    var statusItem: NSStatusItem!
    var hotKey: HotKey?
    var commandKey: HotKey?
    var altKeys: [HotKey] = []
    var capturing = false
    var state: [String: Any] = [:]
    var ready = false
    let stateLine = NSMenuItem(title: "서버 준비 중…", action: nil, keyEquivalent: "")
    let toggleItem = NSMenuItem(title: "받아쓰기 시작", action: #selector(toggleRecording), keyEquivalent: "")
    let commandItem = NSMenuItem(title: "지시 시작", action: #selector(toggleCommand), keyEquivalent: "")

    func applicationDidFinishLaunching(_ note: Notification) {
        buildMainMenu()
        buildStatusItem()
        web = WebWindow()
        web.onMessage = { [weak self] in self?.handle($0) }
        // ⌃⌥R anywhere: start/stop dictation. ⌃⌥E: instruction mode (reads the selection, speak an instruction,
        // Claude's answer is pasted). Change keyCode/modifiers here to use other shortcuts.
        hotKey = HotKey(keyCode: kVK_ANSI_R, modifiers: controlKey | optionKey) { [weak self] in self?.toggleRecording() }
        commandKey = HotKey(keyCode: kVK_ANSI_E, modifiers: controlKey | optionKey) { [weak self] in self?.toggleCommand() }
        // ⌥⇧R / ⌥⇧E also work (the first shortcuts this app had).
        altKeys = [HotKey(keyCode: kVK_ANSI_R, modifiers: optionKey | shiftKey) { [weak self] in self?.toggleRecording() },
                   HotKey(keyCode: kVK_ANSI_E, modifiers: optionKey | shiftKey) { [weak self] in self?.toggleCommand() }].compactMap { $0 }
        server.onUnexpectedExit = { [weak self] in
            self?.ready = false
            self?.notify("로컬 서버가 종료됐습니다", "메뉴 막대 → ‘서버 다시 시작’을 눌러 주세요.")
            self?.refreshMenu()
        }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in }
        showWindow()
        startServer()
    }

    func startServer() {
        ready = false
        refreshMenu()
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            do {
                try server.start()
                DispatchQueue.main.async { self.ready = true; self.web.load(); self.refreshMenu() }
            } catch {
                DispatchQueue.main.async { self.web.showError(error.localizedDescription); self.refreshMenu() }
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return true
    }

    func applicationWillTerminate(_ note: Notification) { server.stop() }

    @objc func showWindow() {
        NSApp.setActivationPolicy(.regular)
        web.reveal()
        web.window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: Recording
    @objc func toggleRecording() {
        guard ready else { showWindow(); return }
        if state["recording"] as? Bool != true { inserter.noteStartRequest() }  // remember the front app
        web.evaluate("window.gqaiNative && window.gqaiNative.toggle('dictate')")
    }

    /// Instruction mode. Copies the front app's selection first, then starts recording; pressing again stops.
    @objc func toggleCommand() {
        guard ready else { showWindow(); return }
        if state["recording"] as? Bool == true || state["processing"] as? Bool == true {
            return web.evaluate("window.gqaiNative && window.gqaiNative.toggle('command')")
        }
        guard !capturing else { return }
        let front = NSWorkspace.shared.frontmostApplication
        guard let front, front.processIdentifier != getpid() else {  // from our own window: the page's selection
            return web.evaluate("window.gqaiNative && window.gqaiNative.toggle('command')")
        }
        inserter.noteStartRequest()
        let trusted = AXIsProcessTrusted()
        capturing = true
        inserter.captureSelection { [weak self] selection in
            guard let self else { return }
            self.capturing = false
            let ctx: [String: Any] = ["selection": selection, "app": front.localizedName ?? "앞 앱", "noAccess": !trusted]
            let json = (try? JSONSerialization.data(withJSONObject: ctx)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
            self.web.evaluate("window.gqaiNative && window.gqaiNative.toggle('command', \(json))")
        }
    }

    // MARK: Messages from the page
    func handle(_ body: [String: Any]) {
        switch body["type"] as? String {
        case "state":
            let was = state["recording"] as? Bool == true
            state = body
            if !was && body["recording"] as? Bool == true { inserter.recordingStarted() }
            refreshMenu()
        case "insertPermission":
            let ok = inserter.requestPermission()
            web.evaluate("window.gqaiNative && window.gqaiNative.insertPermission(\(ok))")
        case "insert":
            guard let text = body["text"] as? String else { return }
            inserter.insert(text, after: body["after"] as? Bool == true) { [weak self] message, ok in
                guard let self else { return }
                let js = (try? String(data: JSONSerialization.data(withJSONObject: [message]), encoding: .utf8)) ?? "[\"\"]"
                self.web.evaluate("window.gqaiNative && window.gqaiNative.inserted(\(js)[0])")
                if !ok { self.notify("입력하지 못했습니다", message) }
            }
        default: break
        }
    }

    // MARK: Menu bar
    func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        stateLine.isEnabled = false
        menu.addItem(stateLine)
        menu.addItem(.separator())
        toggleItem.target = self
        toggleItem.keyEquivalent = "r"
        toggleItem.keyEquivalentModifierMask = [.control, .option]
        menu.addItem(toggleItem)
        commandItem.target = self
        commandItem.keyEquivalent = "e"
        commandItem.keyEquivalentModifierMask = [.control, .option]
        menu.addItem(commandItem)
        menu.addItem(item("GQAI Live 창 열기", #selector(showWindow)))
        menu.addItem(.separator())
        menu.addItem(item("서버 다시 시작", #selector(restartServer)))
        menu.addItem(item("로그 폴더 열기", #selector(openLogs)))
        menu.addItem(.separator())
        menu.addItem(item("GQAI Live 종료", #selector(quit), key: "q"))
        statusItem.menu = menu
        refreshMenu()
    }

    func menuWillOpen(_ menu: NSMenu) { refreshMenu() }

    func refreshMenu() {
        let recording = state["recording"] as? Bool == true
        let busy = state["processing"] as? Bool == true || state["organizing"] as? Bool == true
        let symbol = !ready ? "waveform.slash" : recording ? "record.circle.fill" : busy ? "waveform.badge.ellipsis" : "waveform"
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "GQAI Live")
            button.image?.isTemplate = !recording
            button.contentTintColor = recording ? .systemRed : nil
        }
        if !ready { stateLine.title = "서버 준비 중…" }
        else if recording {
            let sec = state["seconds"] as? Int ?? 0
            let label = state["mode"] as? String == "command" ? "지시" : "녹음"
            stateLine.title = String(format: "● %@ 중 %d:%02d", label, sec / 60, sec % 60)
        } else if busy { stateLine.title = "처리 중" }
        else { stateLine.title = "대기 중" }
        let command = state["mode"] as? String == "command"
        toggleItem.title = recording && !command ? "받아쓰기 중지" : "받아쓰기 시작"
        commandItem.title = recording && command ? "지시 중지" : "지시 시작"
        toggleItem.isEnabled = ready && !(recording && command)
        commandItem.isEnabled = ready && !(recording && !command)
    }

    func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.target = self
        return i
    }

    @objc func restartServer() {
        DispatchQueue.global().async { [self] in
            server.stop()
            DispatchQueue.main.async { self.startServer() }
        }
    }

    @objc func openLogs() { NSWorkspace.shared.open(ServerManager.logURL.deletingLastPathComponent()) }
    @objc func quit() { NSApp.terminate(nil) }

    func notify(_ title: String, _ body: String) {
        let c = UNMutableNotificationContent()
        c.title = title
        c.body = body
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
    }

    // App menu: needed for ⌘C / ⌘V / ⌘A inside the web view.
    func buildMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem(); main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "GQAI Live 가리기", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "GQAI Live 종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        let editItem = NSMenuItem(); main.addItem(editItem)
        let edit = NSMenu(title: "편집")
        edit.addItem(withTitle: "실행 취소", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "실행 복귀", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "오려두기", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "복사하기", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "붙여넣기", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "모두 선택", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        let winItem = NSMenuItem(); main.addItem(winItem)
        let win = NSMenu(title: "윈도우")
        win.addItem(withTitle: "최소화", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        win.addItem(withTitle: "닫기", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        winItem.submenu = win
        NSApp.mainMenu = main
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
