import Cocoa
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var refreshTimer: Timer?

    private let viewModel = UsageViewModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        applyBackgroundPreference()
        setupPopover()
        refresh()
        startTimer()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(preferencesChanged),
            name: .preferencesChanged,
            object: nil
        )
    }

    // MARK: - Setup

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "..."
        statusItem.button?.toolTip = "TokenHub"
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)
    }

    private func setupPopover() {
        let view = TokenHubView(
            model: viewModel,
            onRefresh: { [weak self] in self?.refresh() },
            onLogin: { [weak self] in self?.openLogin() },
            onSettings: { [weak self] in self?.openSettings() },
            onQuit: { NSApplication.shared.terminate(nil) }
        )
        let hosting = NSHostingController(rootView: view)
        // SwiftUI側のサイズ変化をpreferredContentSizeへ継続反映させる。
        // これがないと初回表示時にサイズ確定前の状態で位置決めされ、
        // メニューバーの上端からはみ出て上部（ヘッダー/Claudeセクション）が
        // 隠れることがあった。
        hosting.sizingOptions = [.preferredContentSize]

        popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = hosting
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            refresh()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    // MARK: - Refresh

    @objc func refresh() {
        let timeFmt = DateFormatter()
        timeFmt.dateFormat = "HH:mm:ss"
        viewModel.lastUpdatedText = timeFmt.string(from: Date())

        // 1) WKWebView経由でリアルタイム使用率を取得
        UsageFetcher.shared.fetch { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let live):
                    self?.applyLiveData(live)
                    self?.viewModel.apiConnected = true
                    self?.viewModel.apiStatusText = "接続済み"
                case .failure(let err):
                    // busyは「前回のfetchがまだ進行中」なだけで実際の
                    // 取得失敗ではないため、表示はそのままにして無視する。
                    if let fetchErr = err as? FetchError, fetchErr == .busy { return }
                    self?.viewModel.apiConnected = false
                    self?.viewModel.apiStatusText = err.localizedDescription
                    self?.setLivePlaceholder()
                }
            }
        }

        // 2) Codex CLIのセッションログからレート制限スナップショットを取得
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let limits = CodexUsageReader.shared.readLatestRateLimits()
            DispatchQueue.main.async { self?.applyCodexData(limits) }
        }
    }

    // MARK: - Update UI

    private func applyLiveData(_ live: LiveUsageData) {
        viewModel.claudeAvailable = true

        let timeFmt = DateFormatter()
        timeFmt.locale = Locale(identifier: "ja_JP")
        timeFmt.dateFormat = "HH:mm (M/d)"

        let remaining5h = remainingPercent(from: live.fiveHourUtilization)
        let fiveResetText: String
        if let resetsAt = live.fiveHourResetsAt {
            fiveResetText = timeFmt.string(from: resetsAt)
        } else {
            fiveResetText = "--"
        }
        viewModel.claudeFiveHour = UsageCardData(remainingPercent: remaining5h, resetText: fiveResetText)

        let remaining7d = remainingPercent(from: live.sevenDayUtilization)
        let sevenResetText: String
        if let resetsAt = live.sevenDayResetsAt {
            let dateFmt = DateFormatter()
            dateFmt.locale = Locale(identifier: "ja_JP")
            dateFmt.dateFormat = "M/d HH:mm"
            sevenResetText = dateFmt.string(from: resetsAt)
        } else {
            sevenResetText = "--"
        }
        viewModel.claudeWeekly = UsageCardData(remainingPercent: remaining7d, resetText: sevenResetText)

        updateStatusBarLabel()
    }

    private func setLivePlaceholder() {
        viewModel.claudeAvailable = false
        updateStatusBarLabel()
    }

    private func applyCodexData(_ limits: CodexRateLimits?) {
        guard let limits = limits else {
            viewModel.codexAvailable = false
            viewModel.codexWeeklyAvailable = false
            updateStatusBarLabel()
            return
        }
        viewModel.codexAvailable = true

        let timeFmt = DateFormatter()
        timeFmt.locale = Locale(identifier: "ja_JP")
        timeFmt.dateFormat = "HH:mm (M/d)"

        let fiveResetText = limits.fiveHourResetsAt.map { timeFmt.string(from: $0) } ?? "--"
        viewModel.codexFiveHour = UsageCardData(
            remainingPercent: remainingPercent(from: limits.fiveHourPercent), resetText: fiveResetText)

        // 週間制限はCodex CLI側からnullで返ってくることがあるため、
        // 取れなかった場合は5時間側とは別に「データなし」表示にする。
        if let weeklyPercent = limits.weeklyPercent {
            viewModel.codexWeeklyAvailable = true
            let dateFmt = DateFormatter()
            dateFmt.locale = Locale(identifier: "ja_JP")
            dateFmt.dateFormat = "M/d HH:mm"
            let weeklyResetText = limits.weeklyResetsAt.map { dateFmt.string(from: $0) } ?? "--"
            viewModel.codexWeekly = UsageCardData(
                remainingPercent: remainingPercent(from: weeklyPercent), resetText: weeklyResetText)
        } else {
            viewModel.codexWeeklyAvailable = false
            viewModel.codexWeekly = UsageCardData(remainingPercent: 0, resetText: "--")
        }

        updateStatusBarLabel()
    }

    // メニューバーのラベルはPreferencesで選んだ指標を表示する。
    // 4つのデータソースはそれぞれ非同期に更新されるため、更新の
    // たびにこの関数を呼んで最新のviewModelから再計算する。
    private func updateStatusBarLabel() {
        let source = Preferences.shared.menuBarSource
        let data: UsageCardData
        let available: Bool
        switch source {
        case .claudeFiveHour: data = viewModel.claudeFiveHour; available = viewModel.claudeAvailable
        case .claudeWeekly: data = viewModel.claudeWeekly; available = viewModel.claudeAvailable
        case .codexFiveHour: data = viewModel.codexFiveHour; available = viewModel.codexAvailable
        case .codexWeekly:
            data = viewModel.codexWeekly
            available = viewModel.codexAvailable && viewModel.codexWeeklyAvailable
        }
        // 選択中ソースが取得不能な場合、data側に古い値が残っていても
        // それを表示せず「--」にする(取得不能時にstaleな%が出るのを防ぐ)。
        statusItem.button?.title = available ? "\(data.remainingPercent)%" : "--"
    }

    // APIの異常値（負数・100超）でメニューバーやバーグラフが壊れた
    // 表示にならないようclampする。
    private func remainingPercent(from usedPercent: Double) -> Int {
        let clampedUsed = max(0, min(100, usedPercent))
        return Int(100 - clampedUsed)
    }

    // MARK: - Actions

    private func openLogin() {
        LoginWindowController.shared.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func openSettings() {
        PreferencesWindowController.shared.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func preferencesChanged() {
        refreshTimer?.invalidate()
        startTimer()
        updateStatusBarLabel()
        applyBackgroundPreference()
        refresh()
    }

    private func applyBackgroundPreference() {
        let prefs = Preferences.shared
        viewModel.backgroundColor = Color(prefs.backgroundColor)
        viewModel.backgroundOpacity = prefs.backgroundOpacity
    }

    private func startTimer() {
        let interval = Preferences.shared.updateInterval
        refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }
}
