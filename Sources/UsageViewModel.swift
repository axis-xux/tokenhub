import AppKit
import SwiftUI
import Combine

struct UsageCardData {
    let remainingPercent: Int
    let resetText: String
}

// AppDelegateがrefresh()のたびにこの状態を更新し、TokenHubViewはこれを
// 購読して再描画する。データ取得ロジック（UsageFetcher/CodexUsageReader）は
// 従来のまま変更しない。
class UsageViewModel: ObservableObject {
    @Published var claudeAvailable: Bool = true
    @Published var claudeFiveHour = UsageCardData(remainingPercent: 0, resetText: "--")
    @Published var claudeWeekly = UsageCardData(remainingPercent: 0, resetText: "--")

    @Published var codexAvailable: Bool = false
    // 週間制限はCodex CLI側の仕様でnullになることがあるため、5時間制限
    // とは別に可否を持つ。
    @Published var codexWeeklyAvailable: Bool = false
    @Published var codexFiveHour = UsageCardData(remainingPercent: 0, resetText: "--")
    @Published var codexWeekly = UsageCardData(remainingPercent: 0, resetText: "--")

    @Published var apiConnected: Bool = false
    @Published var apiStatusText: String = "取得中..."
    @Published var lastUpdatedText: String = "--"

    @Published var backgroundColor: Color = Color(NSColor.windowBackgroundColor)
    @Published var backgroundOpacity: Double = 0.95
}
