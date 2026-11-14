import AppKit
import WebKit

/// Main window: the local page (http://127.0.0.1:<port>/) in a WKWebView, plus the JS ↔ app bridge.
/// Page → app: window.webkit.messageHandlers.gqai.postMessage({type, ...})
/// App → page: evaluate("window.gqaiNative.<method>(...)")
final class WebWindow: NSObject, WKUIDelegate, WKNavigationDelegate, WKScriptMessageHandler, NSWindowDelegate {
    let window: NSWindow
    let webView: WKWebView
    var onMessage: (([String: Any]) -> Void)?

    override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()   // keeps localStorage (mic choice, options) between launches
        let controller = WKUserContentController()
        config.userContentController = controller
        webView = WKWebView(frame: .zero, configuration: config)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 820),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        super.init()
        controller.add(self, name: "gqai")
        webView.uiDelegate = self
        webView.navigationDelegate = self
        if #available(macOS 13.3, *) { webView.isInspectable = true }  // Safari > Develop for debugging
        window.title = "GQAI Live"
        window.contentView = webView
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("GQAILiveMain")
        if window.frame.origin == .zero { window.center() }
    }

    func load() {
        webView.load(URLRequest(url: ServerManager.baseURL, cachePolicy: .reloadIgnoringLocalCacheData))
    }

    func showError(_ message: String) {
        let html = """
        <html><body style="font:15px -apple-system;padding:48px"><h2>GQAI Live를 시작하지 못했습니다</h2>
        <pre style="white-space:pre-wrap;background:#f3f3f3;padding:16px;border-radius:8px">\(message.replacingOccurrences(of: "<", with: "&lt;"))</pre>
        <p>메뉴 막대의 GQAI Live 아이콘 → ‘서버 다시 시작’으로 다시 시도하세요.</p></body></html>
        """
        webView.loadHTMLString(html, baseURL: nil)
    }

    func evaluate(_ js: String) { webView.evaluateJavaScript(js, completionHandler: nil) }

    // Closing the window keeps the app (and any recording) running in the menu bar.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        NSApp.setActivationPolicy(.accessory)
        return false
    }

    func userContentController(_ uc: WKUserContentController, didReceive message: WKScriptMessage) {
        if let body = message.body as? [String: Any] { onMessage?(body) }
    }

    // Only the local page may use the microphone.
    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        decisionHandler(origin.host == "127.0.0.1" && type == .microphone ? .grant : .deny)
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let a = NSAlert(); a.messageText = message; a.addButton(withTitle: "확인")
        a.beginSheetModal(for: window) { _ in completionHandler() }
    }

    // Stay on the local page; open external links in the default browser.
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url else { return decisionHandler(.cancel) }
        if url.host == "127.0.0.1" || url.scheme == "about" { return decisionHandler(.allow) }
        if action.navigationType == .linkActivated { NSWorkspace.shared.open(url) }
        decisionHandler(.cancel)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { load() }
}
