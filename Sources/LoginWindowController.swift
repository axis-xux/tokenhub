import Cocoa
import WebKit

class LoginWindowController: NSWindowController, WKNavigationDelegate, WKUIDelegate, NSWindowDelegate {
    static let shared = LoginWindowController()

    private var webView: WKWebView!
    private var statusLabel: NSTextField!
    // Google/Appleログインはwindow.openのポップアップで動くため、
    // 開かれたポップアップを保持する（同時に1つだけ）。
    private var popupWindow: NSWindow?
    private var popupWebView: WKWebView?

    // claude.ai本体＋主要SSOプロバイダのみ許可する。ログイン画面は
    // ユーザーが認証情報を入力する場所なので、未知のドメインへ静かに
    // 遷移できてしまうとフィッシングに使われうる（Codexセキュリティ
    // レビューで高severity指摘）。
    private static let allowedHosts: Set<String> = [
        "claude.ai", "www.claude.ai",
        "accounts.google.com",
        "appleid.apple.com",
        "login.microsoftonline.com"
    ]

    // claude.aiのログインページはhCaptcha/Cloudflareのボット判定を
    // iframeで埋め込む。これらをブロックするとログインが進まないため、
    // メインフレームではなくサブフレーム（iframe）の遷移に限って許可する。
    // メインフレームをこれらのドメインへ遷移させることは引き続き禁止。
    // a.claude.ai（ページが読み込む補助フレーム）もサブフレーム限定で許可する。
    // ワイルドカード（*.claude.ai）はメインフレームの攻撃面が広がるため使わない。
    private static let allowedFrameHosts: Set<String> = [
        "hcaptcha.com", "challenges.cloudflare.com", "a.claude.ai"
    ]

    private var loginCompleted = false

    private static func isAllowedFrameHost(_ host: String) -> Bool {
        allowedFrameHosts.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 700),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Claude.ai ログイン — TokenHub"
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        buildUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func showWindow(_ sender: Any?) {
        loginCompleted = false
        super.showWindow(sender)
    }

    private func buildUI() {
        guard let cv = window?.contentView else { return }

        // ステータスバー（上部）— 現在のURLを常に表示し、フィッシング
        // ページへ遷移していないか利用者が目視確認できるようにする。
        statusLabel = NSTextField(labelWithString: "claude.ai にログインしてください。ログイン後、ウィンドウは自動的に閉じます。")
        statusLabel.frame = NSRect(x: 12, y: cv.bounds.height - 28, width: cv.bounds.width - 24, height: 20)
        statusLabel.autoresizingMask = [.width, .minYMargin]
        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingMiddle
        cv.addSubview(statusLabel)

        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        // ログイン中に勝手なポップアップウィンドウを開かせない。
        config.preferences.javaScriptCanOpenWindowsAutomatically = false

        let webFrame = NSRect(x: 0, y: 0, width: cv.bounds.width, height: cv.bounds.height - 32)
        webView = WKWebView(frame: webFrame, configuration: config)
        webView.autoresizingMask = [.width, .height]
        webView.navigationDelegate = self
        webView.uiDelegate = self
        cv.addSubview(webView)

        webView.load(URLRequest(url: URL(string: "https://claude.ai/login")!))
    }

    // https以外（javascript:/file:等）は無条件拒否。httpsでも
    // claude.ai本体と主要SSOプロバイダ以外への遷移は拒否する
    // （未知のドメインを経由したフィッシング対策）。
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        // targetFrameがnilなのは新規ウィンドウ向けの遷移。メイン扱いにする。
        let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? true
        guard let url = navigationAction.request.url,
              url.scheme == "https",
              let host = url.host,
              Self.allowedHosts.contains(host)
                || (!isMainFrame && Self.isAllowedFrameHost(host))
        else {
            decisionHandler(.cancel)
            if let host = navigationAction.request.url?.host {
                statusLabel.stringValue = "未対応のドメインへの遷移をブロックしました: \(host)"
                statusLabel.textColor = .systemRed
            }
            return
        }
        decisionHandler(.allow)
    }

    // MARK: - WKUIDelegate（Google/Appleログインのポップアップ対応）

    // ユーザー操作で開かれるwindow.openのみ、許可リスト内ドメイン限定で
    // 子ウィンドウとして開く。openerと接続するため、渡されたconfigurationを
    // そのまま使う必要がある。
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard let url = navigationAction.request.url,
              url.scheme == "https",
              let host = url.host,
              Self.allowedHosts.contains(host)
        else { return nil }

        popupWindow?.close()

        let popup = WKWebView(frame: .zero, configuration: configuration)
        popup.navigationDelegate = self
        popup.uiDelegate = self

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 680),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "ログイン"
        window.isReleasedWhenClosed = false
        window.contentView = popup
        window.delegate = self
        window.center()
        window.makeKeyAndOrderFront(nil)

        popupWindow = window
        popupWebView = popup
        return popup
    }

    // ポップアップ側のスクリプトがwindow.close()した場合。
    func webViewDidClose(_ webView: WKWebView) {
        guard webView === popupWebView else { return }
        popupWindow?.close()
    }

    // ユーザーが×で閉じた場合もここに来る。読み込みを止めて参照を解放し、
    // 非表示のWebViewやOAuth状態が残らないようにする。
    func windowWillClose(_ notification: Notification) {
        guard let w = notification.object as? NSWindow, w === popupWindow else { return }
        popupWebView?.stopLoading()
        popupWindow?.delegate = nil
        popupWindow = nil
        popupWebView = nil
        // ポップアップSSO完了後はSPAが状態更新するだけの場合があるので再判定する。
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.checkLoginStatus()
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // ポップアップ内の遷移ではホーム判定・ステータス更新をしない。
        guard webView === self.webView, let url = webView.url else { return }

        // 現在地を常に表示（フィッシング対策：想定外のページに
        // 気づけるようにする）
        statusLabel.stringValue = "現在のURL: \(url.absoluteString)"
        statusLabel.textColor = .secondaryLabelColor

        // ログイン成功の判定。着地ページのパスは仕様変更で変わりうる
        // （/new以外に着地して窓が閉じなかった）ため、パスではなく
        // /api/account が認証済みで返るかで判定する。
        // ログイン済みでもURLが/loginのままSPAがホームを描画することがある
        // ため、パスでは除外しない。
        guard !loginCompleted,
              url.host == "claude.ai" || url.host == "www.claude.ai"
        else { return }

        checkLoginStatus()
    }

    // /api/account が認証済みで返るかでログイン成功を判定する。
    // メインフレームのdidFinishだけでは、ポップアップSSO後にSPAが
    // 状態更新するだけでナビゲーションが起きないケースを拾えないため、
    // ポップアップを閉じた時にも呼ぶ。
    private func checkLoginStatus() {
        guard !loginCompleted, let url = webView.url,
              url.host == "claude.ai" || url.host == "www.claude.ai"
        else { return }
        webView.callAsyncJavaScript(
            "const r = await fetch('/api/account', {credentials: 'include'}); return r.status;",
            arguments: [:], in: nil, in: .page
        ) { [weak self] result in
            guard let self = self, !self.loginCompleted,
                  case .success(let value) = result,
                  (value as? Int) == 200
            else { return }
            self.loginCompleted = true
            self.statusLabel.stringValue = "ログイン成功！ウィンドウを閉じています..."
            self.statusLabel.textColor = .systemGreen
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.popupWindow?.close()
                self?.window?.close()
                NotificationCenter.default.post(name: .preferencesChanged, object: nil)
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        statusLabel.stringValue = "エラー: \(error.localizedDescription)"
        statusLabel.textColor = .systemRed
    }
}
