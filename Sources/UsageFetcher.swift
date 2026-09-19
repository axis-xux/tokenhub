import Foundation
import WebKit

struct LiveUsageData {
    let fiveHourUtilization: Double   // 0-100
    let fiveHourResetsAt: Date?
    let sevenDayUtilization: Double   // 0-100
    let sevenDayResetsAt: Date?
}

// WKWebView経由でclaude.aiのAPIから実際の使用率を取得
class UsageFetcher: NSObject {

    private var webView: WKWebView?
    private var orgUUID: String?
    private var completion: ((Result<LiveUsageData, Error>) -> Void)?
    private var isLoading = false
    private var fetchToken: UUID?
    // タイムアウト後も裏で継続していた古いnavigationのコールバックが、
    // 次のfetch()サイクルの結果を横取りするレースを防ぐため、直近で
    // 発行したnavigationのみ処理対象にする。
    private var activeNavigation: WKNavigation?
    // didFinishのnavigation識別チェックだけでは不十分（evaluateJavaScriptの
    // 非同期completionはdidFinish通過後に発火するため、その間に次の
    // fetch()が始まっているとdidFinish時点のチェックが無意味になる）。
    // evaluateJavaScriptのcompletion自身の中でも必ずこのtokenで
    // 現在のfetchToken一致を再確認する。
    private var pendingToken: UUID?

    static let shared = UsageFetcher()

    private override init() {
        super.init()
        setupWebView()
    }

    private func setupWebView() {
        let config = WKWebViewConfiguration()
        // システムのWebKit共有データストアを使用（Safariのログイン状態を共有）
        config.websiteDataStore = .default()
        // このWebViewはclaude.aiの認証Cookieを持つため、ポップアップ等で
        // 別ウィンドウを勝手に開かせない。
        config.preferences.javaScriptCanOpenWindowsAutomatically = false

        webView = WKWebView(frame: .zero, configuration: config)
        webView?.navigationDelegate = self
    }

    func fetch(completion: @escaping (Result<LiveUsageData, Error>) -> Void) {
        // 呼び出し側が「completionは必ず呼ばれる」と期待しても不整合に
        // ならないよう、進行中でも黙って無視せず明示的に知らせる。
        guard !isLoading else {
            completion(.failure(FetchError.busy))
            return
        }
        isLoading = true
        self.completion = completion

        // didFailProvisionalNavigation等、ナビゲーション失敗の一部経路を
        // 拾い損ねてisLoadingが固まると以後ずっと再取得できなくなる
        // （5時間リセットが永遠に反映されない不具合の実際の原因だった）。
        // ウォッチドッグで必ず一定時間後には解放する。
        let token = UUID()
        fetchToken = token
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
            guard let self = self, self.fetchToken == token else { return }
            // 待つのを諦めるだけでなく実際に読み込みを止め、後から遅れて
            // 届くコールバックが次のfetchサイクルに混入しないようにする。
            self.webView?.stopLoading()
            self.activeNavigation = nil
            self.finish(token: token, .failure(FetchError.timeout))
        }

        // まずorgUUIDを取得してから使用量を取得
        fetchOrgUUID(token: token) { [weak self] uuid in
            guard let self = self, self.fetchToken == token else { return }
            if let uuid = uuid {
                self.orgUUID = uuid
                self.fetchUsage(token: token, orgUUID: uuid)
            } else {
                self.finish(token: token, .failure(FetchError.notAuthenticated))
            }
        }
    }

    // 成功・失敗どの経路でも一度だけ呼ばれるようにして、isLoadingの
    // 解放漏れ（＝以後の再取得が永久に止まる）を防ぐ。tokenが現在の
    // fetchTokenと一致しない場合は古いサイクルの結果なので無視する。
    private func finish(token: UUID, _ result: Result<LiveUsageData, Error>) {
        guard isLoading, fetchToken == token else { return }
        isLoading = false
        activeNavigation = nil
        fetchToken = nil
        pendingToken = nil
        let cb = completion
        completion = nil
        orgUUIDCompletion = nil
        cb?(result)
    }

    private func fetchOrgUUID(token: UUID, completion: @escaping (String?) -> Void) {
        let url = URL(string: "https://claude.ai/api/account")!
        activeNavigation = webView?.load(noCacheRequest(url))
        pendingToken = token
        // navigationDidFinish でorgUUIDを取得し、completionを呼ぶ
        orgUUIDCompletion = completion
    }

    private var orgUUIDCompletion: ((String?) -> Void)?

    // アカウントにはAPI用組織（capabilities: api）とclaude.ai用組織
    // （capabilities: chat）が併存し、並び順は保証されない。先頭を使うと
    // API組織に使用量を問い合わせて permission_error になる
    // （2026-09に実際に発生）ため、chat権限を持つ組織を選ぶ。
    static func chatOrganization(in memberships: [[String: Any]]) -> [String: Any]? {
        let orgs = memberships.compactMap { $0["organization"] as? [String: Any] }
        return orgs.first { ($0["capabilities"] as? [String])?.contains("chat") == true } ?? orgs.first
    }

    private func fetchUsage(token: UUID, orgUUID: String) {
        // orgUUIDはclaude.aiのレスポンスから来る外部データなので、想定外の
        // 文字が含まれていてもURL(string:)!のクラッシュにしない。
        guard let encoded = orgUUID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://claude.ai/api/organizations/\(encoded)/usage")
        else {
            finish(token: token, .failure(FetchError.parseError))
            return
        }
        activeNavigation = webView?.load(noCacheRequest(url))
        pendingToken = token
    }

    // WKWebViewはデフォルトのcachePolicyだとCache-Controlヘッダ次第で
    // 古いusageレスポンスを返し続け、5時間リセットが画面に反映されない。
    // 毎回サーバーから取り直す。
    private func noCacheRequest(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData)
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        return request
    }
}

// MARK: - WKNavigationDelegate
extension UsageFetcher: WKNavigationDelegate {
    // このWebViewはclaude.aiの認証Cookieを保持しているため、想定外の
    // ドメインへの遷移（万一のリダイレクトやDNS/中間者攻撃）は
    // evaluateJavaScriptで内容を読む前に必ず遮断する。
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url,
              url.scheme == "https",
              url.host == "claude.ai" || url.host == "www.claude.ai"
        else {
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard navigation === activeNavigation, let token = pendingToken else { return }
        // decidePolicyForでhttps以外は既に遮断済みだが、読み取り直前にも
        // 再確認して防御を重ねる。
        guard let url = webView.url, url.scheme == "https",
              url.host == "claude.ai" || url.host == "www.claude.ai" else {
            // 想定外パスに来た場合、20秒のタイムアウト待ちにせず即座に失敗させる。
            finish(token: token, .failure(FetchError.parseError))
            return
        }

        if url.path == "/api/account" {
            // orgUUIDを取得
            webView.evaluateJavaScript("document.body.innerText") { [weak self] result, _ in
                // didFinish通過後、この非同期completionが発火するまでの間に
                // 次のfetch()サイクルが始まっている可能性があるため、
                // ここでも必ずtokenを再確認する（didFinish時点のnavigation
                // チェックだけでは不十分だった＝Codexセキュリティレビュー指摘）。
                guard let self = self, self.fetchToken == token else { return }
                guard let text = result as? String,
                      let data = text.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let memberships = json["memberships"] as? [[String: Any]],
                      let org = Self.chatOrganization(in: memberships),
                      let uuid = org["uuid"] as? String
                else {
                    self.orgUUIDCompletion?(nil)
                    return
                }
                self.orgUUIDCompletion?(uuid)
            }
        } else if url.path.hasPrefix("/api/organizations/") && url.path.hasSuffix("/usage") {
            // 使用量データを取得
            webView.evaluateJavaScript("document.body.innerText") { [weak self] result, _ in
                guard let self = self, self.fetchToken == token else { return }

                guard let text = result as? String,
                      let data = text.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                else {
                    self.finish(token: token, .failure(FetchError.parseError))
                    return
                }

                let isoFull = ISO8601DateFormatter()
                isoFull.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                let isoBasic = ISO8601DateFormatter()
                isoBasic.formatOptions = [.withInternetDateTime]

                func parseDate(in dict: [String: Any]?) -> Date? {
                    guard let s = dict?["resets_at"] as? String else { return nil }
                    return isoFull.date(from: s) ?? isoBasic.date(from: s)
                }

                // utilizationが欠落/型不正のときに0扱い（＝「残り100%」の
                // 誤表示）にしてしまうfail-openを避け、解析失敗として扱う。
                guard let fiveHour = json["five_hour"] as? [String: Any],
                      let fiveHourUtil = fiveHour["utilization"] as? Double,
                      let sevenDay = json["seven_day"] as? [String: Any],
                      let sevenDayUtil = sevenDay["utilization"] as? Double
                else {
                    self.finish(token: token, .failure(FetchError.parseError))
                    return
                }

                let usage = LiveUsageData(
                    fiveHourUtilization: fiveHourUtil,
                    fiveHourResetsAt: parseDate(in: fiveHour),
                    sevenDayUtilization: sevenDayUtil,
                    sevenDayResetsAt: parseDate(in: sevenDay)
                )
                self.finish(token: token, .success(usage))
            }
        } else {
            // claude.ai内だが想定していないパス。タイムアウト待ちにせず即失敗。
            finish(token: token, .failure(FetchError.parseError))
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard navigation === activeNavigation, let token = pendingToken else { return }
        finish(token: token, .failure(error))
    }

    // 読み込み開始直後の失敗（DNS/接続不可・前のロードが新しいloadで
    // 中断された場合等）はこちらに来る。既存はdidFailのみ処理していた
    // ためこの経路の失敗を拾えず、isLoadingが解放されずに固まっていた。
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        guard navigation === activeNavigation, let token = pendingToken else { return }
        finish(token: token, .failure(error))
    }
}

// MARK: - Errors
enum FetchError: LocalizedError, Equatable {
    case notAuthenticated
    case parseError
    case timeout
    case busy

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "claude.aiにログインが必要です"
        case .parseError: return "データ解析エラー"
        case .timeout: return "タイムアウトしました"
        case .busy: return "更新中です"
        }
    }
}
