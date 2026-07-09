import Cocoa
import WebKit

class LoginWindowController: NSWindowController, WKNavigationDelegate {
    static let shared = LoginWindowController()

    private var webView: WKWebView!
    private var statusLabel: NSTextField!

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
        cv.addSubview(webView)

        webView.load(URLRequest(url: URL(string: "https://claude.ai/login")!))
    }

    // https以外（javascript:/file:等）は無条件拒否。httpsでも
    // claude.ai本体と主要SSOプロバイダ以外への遷移は拒否する
    // （未知のドメインを経由したフィッシング対策）。
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url,
              url.scheme == "https",
              let host = url.host,
              Self.allowedHosts.contains(host)
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

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let url = webView.url else { return }

        // ログイン後にホームに遷移したことを検知
        let isHome = (url.host == "claude.ai" || url.host == "www.claude.ai")
                     && (url.path == "/" || url.path == "" || url.path.hasPrefix("/new"))
        if isHome {
            statusLabel.stringValue = "ログイン成功！ウィンドウを閉じています..."
            statusLabel.textColor = .systemGreen
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.window?.close()
                NotificationCenter.default.post(name: .preferencesChanged, object: nil)
            }
        } else {
            // 現在地を常に表示（フィッシング対策：想定外のページに
            // 気づけるようにする）
            statusLabel.stringValue = "現在のURL: \(url.absoluteString)"
            statusLabel.textColor = .secondaryLabelColor
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        statusLabel.stringValue = "エラー: \(error.localizedDescription)"
        statusLabel.textColor = .systemRed
    }
}
