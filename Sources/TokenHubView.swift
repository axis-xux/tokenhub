import SwiftUI

struct TokenHubView: View {
    @ObservedObject var model: UsageViewModel
    var onRefresh: () -> Void
    var onLogin: () -> Void
    var onSettings: () -> Void
    var onQuit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            sectionLabel("Claude.ai", systemImage: "leaf.fill", color: .green)
            UsageCardView(icon: "clock.fill", iconColor: .orange, barColor: .orange,
                          title: "5時間制限", data: model.claudeFiveHour,
                          unavailableMessage: model.claudeAvailable ? nil : "ログインが必要です")
            UsageCardView(icon: "calendar", iconColor: .green, barColor: .green,
                          title: "7日間制限", data: model.claudeWeekly,
                          unavailableMessage: model.claudeAvailable ? nil : "ログインが必要です")

            sectionLabel("Codex CLI", systemImage: "chevron.left.forwardslash.chevron.right", color: .indigo)
            UsageCardView(icon: "clock.fill", iconColor: .blue, barColor: .blue,
                          title: "5時間制限", data: model.codexFiveHour,
                          unavailableMessage: model.codexAvailable ? nil : "データなし")
            UsageCardView(icon: "calendar", iconColor: .purple, barColor: .purple,
                          title: "週間制限", data: model.codexWeekly,
                          unavailableMessage: (model.codexAvailable && model.codexWeeklyAvailable) ? nil : "データなし")

            Divider()

            footer
        }
        .padding(16)
        .frame(width: 340)
        // NSPopoverはデフォルトで背景に半透明素材を使うため、デスクトップの
        // 背景次第では読みにくくなる。ユーザーが色・不透明度を設定できる
        // ようにし、ここで確実に不透明な背景を敷く。
        .background(model.backgroundColor.opacity(model.backgroundOpacity))
    }

    private var header: some View {
        HStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 40, height: 40)
                .overlay(Text("TH").font(.system(size: 15, weight: .bold)).foregroundColor(.white))

            VStack(alignment: .leading, spacing: 2) {
                Text("TokenHub").font(.system(size: 16, weight: .bold))
                Text("最終更新: \(model.lastUpdatedText)")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: onRefresh) {
                Image(systemName: "arrow.clockwise")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    private func sectionLabel(_ text: String, systemImage: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage).foregroundColor(color).font(.system(size: 12))
            Text(text).font(.system(size: 13, weight: .semibold))
        }
    }

    private var footer: some View {
        HStack {
            Circle()
                .fill(model.apiConnected ? Color.green : Color.red)
                .frame(width: 7, height: 7)
            Text("API: \(model.apiStatusText)")
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            Spacer()

            Button(action: onLogin) {
                Image(systemName: "person.crop.circle")
            }
            .buttonStyle(.plain)

            Button(action: onSettings) {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.plain)

            Button(action: onQuit) {
                Image(systemName: "power")
            }
            .buttonStyle(.plain)
        }
        .foregroundColor(.secondary)
    }
}

private struct UsageCardView: View {
    let icon: String
    let iconColor: Color
    let barColor: Color
    let title: String
    let data: UsageCardData
    var unavailableMessage: String? = nil

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(iconColor)
                .frame(width: 28, height: 28)
                .background(iconColor.opacity(0.15))
                .clipShape(Circle())

            // unavailable時も行数・高さを完全に揃える（ポップオーバーの
            // 初回表示時に高さが変わって位置がずれるのを防ぐため）。
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(title).font(.system(size: 12)).foregroundColor(.secondary)
                    Spacer()
                    if unavailableMessage == nil {
                        Text("\(data.resetText)リセット")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                if let message = unavailableMessage {
                    Text(message)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                } else {
                    HStack(spacing: 4) {
                        Text("残り").font(.system(size: 11)).foregroundColor(.secondary)
                        Text("\(data.remainingPercent)%")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(barColor)
                    }
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.secondary.opacity(0.15))
                        if unavailableMessage == nil {
                            Capsule().fill(barColor)
                                .frame(width: geo.size.width * CGFloat(max(0, min(100, data.remainingPercent))) / 100)
                        }
                    }
                }
                .frame(height: 5)
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.08))
        .cornerRadius(10)
    }
}
