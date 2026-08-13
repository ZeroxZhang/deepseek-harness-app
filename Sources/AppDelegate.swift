/**
 * DeepSeek Harness — app delegate: main menu, single-instance guard, the
 * WKWebView window, and the bridge to the server controller.
 *
 * Window policy: the window appears immediately with a spinner page; when the
 * server is ready (or failed) the web view is pointed at the real UI. Closing
 * the last window quits the app, which stops a server this app spawned.
 */

import Cocoa
import WebKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let server = ServerController()
    private var window: NSWindow?
    private var webView: WKWebView?
    private let frameDefaultsKey = "MainWindowFrame"

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppLog.info("app: launched (\(AppConfig.appName) v\(AppConfig.version))")
        installMainMenu()
        guard becomeSoleInstance() else { return }

        showWindow()
        server.start { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let outcome):
                AppLog.info("window: loading \(outcome.url.absoluteString)")
                self.webView?.load(URLRequest(url: outcome.url))
            case .failure(let error):
                AppLog.error("window: startup failed — \(error.message)")
                self.showOfflinePage(detail: error.message)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppLog.info("app: terminating")
        server.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    // MARK: single instance

    /** @returns false when another copy already runs and this one must exit. */
    private func becomeSoleInstance() -> Bool {
        let myPid = ProcessInfo.processInfo.processIdentifier
        guard let other = NSWorkspace.shared.runningApplications
            .first(where: { $0.bundleIdentifier == AppConfig.bundleId && $0.processIdentifier != myPid })
        else { return true }
        AppLog.info("app: another instance is running — activating it and exiting")
        other.activate(options: [])
        NSApp.terminate(nil)
        return false
    }

    // MARK: window

    private func showWindow() {
        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        webView.navigationDelegate = self
        webView.uiDelegate = self
        self.webView = webView

        let window = NSWindow(
            contentRect: savedFrame(),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false)
        window.title = AppConfig.appName
        window.minSize = NSSize(width: 900, height: 600)
        window.contentView = webView
        window.delegate = self
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window

        showStartingPage(in: webView)
    }

    private func savedFrame() -> NSRect {
        let stored = UserDefaults.standard.string(forKey: frameDefaultsKey).map(NSRectFromString)
        if let stored = stored, stored.width >= 900, stored.height >= 600 {
            // Refuse frames dragged almost entirely off-screen.
            let visible = NSScreen.screens.first?.visibleFrame
                ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
            let overlap = stored.intersection(visible)
            if overlap.width >= 400 && overlap.height >= 300 { return stored }
        }
        return NSRect(x: 0, y: 0, width: 1280, height: 840)
    }

    private func showStartingPage(in webView: WKWebView) {
        let html = """
        <!doctype html><html><head><meta charset="utf-8"><style>
        body { font-family: -apple-system, sans-serif; display: flex; align-items: center; justify-content: center; height: 100vh; margin: 0; background: #0f1115; color: #e6e8ee; }
        .box { text-align: center; }
        .spinner { width: 28px; height: 28px; margin: 0 auto 16px; border: 3px solid rgba(255,255,255,.15); border-top-color: #4d6bfe; border-radius: 50%; animation: spin 0.9s linear infinite; }
        @keyframes spin { to { transform: rotate(360deg); } }
        p { color: #9aa0ac; font-size: 13px; }
        </style></head><body><div class="box">
        <div class="spinner"></div>
        <p>正在启动 DeepSeek Harness…</p>
        </div></body></html>
        """
        webView.loadHTMLString(html, baseURL: nil)
    }

    private func showOfflinePage(detail: String) {
        guard let webView = webView else { return }
        let retry = "http://127.0.0.1:\(AppConfig.port)/"
        let html = """
        <!doctype html><html><head><meta charset="utf-8"><style>
        body { font-family: -apple-system, sans-serif; display: flex; align-items: center; justify-content: center; height: 100vh; margin: 0; background: #0f1115; color: #e6e8ee; }
        .box { text-align: center; max-width: 520px; padding: 32px; }
        h1 { font-size: 20px; }
        p { color: #9aa0ac; font-size: 13px; line-height: 1.7; }
        button { margin-top: 16px; padding: 8px 22px; border-radius: 8px; border: none; background: #4d6bfe; color: #fff; font-size: 13px; cursor: pointer; }
        </style></head><body><div class="box">
        <h1>DeepSeek Harness 服务不可用</h1>
        <p>\(detail)</p>
        <p>日志：~/Library/Logs/DeepSeekHarness/</p>
        <button onclick="location.href='\(retry)'">重试连接</button>
        </div></body></html>
        """
        webView.loadHTMLString(html, baseURL: nil)
    }

    // MARK: menu

    private func installMainMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appItem.submenu = appMenu
        appMenu.addItem(withTitle: "关于 \(AppConfig.appName)", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "隐藏 \(AppConfig.appName)", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出 \(AppConfig.appName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "编辑")
        editItem.submenu = editMenu
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        let viewItem = NSMenuItem()
        mainMenu.addItem(viewItem)
        let viewMenu = NSMenu(title: "显示")
        viewItem.submenu = viewMenu
        let reload = viewMenu.addItem(withTitle: "重新载入页面", action: #selector(reloadAction), keyEquivalent: "r")
        reload.target = self

        let windowItem = NSMenuItem()
        mainMenu.addItem(windowItem)
        let windowMenu = NSMenu(title: "窗口")
        windowItem.submenu = windowMenu
        windowMenu.addItem(withTitle: "最小化", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "关闭窗口", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = mainMenu
    }

    @objc private func reloadAction() {
        webView?.reload()
    }
}

// MARK: window delegate

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        window = nil
        webView = nil
    }

    func windowDidMove(_ notification: Notification) { persistFrame() }
    func windowDidResize(_ notification: Notification) { persistFrame() }

    private func persistFrame() {
        guard let window = window, !window.isMiniaturized else { return }
        UserDefaults.standard.set(NSStringFromRect(window.frame), forKey: frameDefaultsKey)
    }
}

// MARK: navigation

extension AppDelegate: WKNavigationDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }
        if navigationAction.targetFrame?.isMainFrame == true {
            let isHarness = url.host == "127.0.0.1" && url.port == Int(AppConfig.port)
            let isLocalPage = url.scheme == "about"
            if isHarness || isLocalPage {
                decisionHandler(.allow)
            } else {
                // Main-frame navigation away from the harness opens externally.
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
            }
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation?, withError error: Error) {
        if (error as NSError).code == NSURLErrorCancelled { return }
        AppLog.error("window: navigation failed — \(error.localizedDescription)")
        showOfflinePage(detail: "无法连接到本地服务（\(error.localizedDescription)）。")
    }
}

extension AppDelegate: WKUIDelegate {
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        // window.open / target=_blank: hand the URL to the default browser.
        if let url = navigationAction.request.url {
            NSWorkspace.shared.open(url)
        }
        return nil
    }
}
