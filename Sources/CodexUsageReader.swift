import Foundation

struct CodexRateLimits {
    // 2026-07-13にCodex CLI側の仕様変更でprimary/secondaryの割り当てが
    // 入れ替わり、5時間側がnullになる（＝primaryが週間を指すようになる）
    // ケースが確認された。以後、両方ともnullになり得る前提にしている。
    let fiveHourPercent: Double?
    let fiveHourResetsAt: Date?
    let weeklyPercent: Double?
    let weeklyResetsAt: Date?
}

// Codex CLI (~/.codex/sessions/**/*.jsonl) は各ターン完了後にOpenAIから
// 返ってきたレート制限スナップショットをそのままログへ書き出している。
// Claudeと違い専用APIを叩く必要はなく、ローカルファイルを読むだけでよい。
class CodexUsageReader {
    static let shared = CodexUsageReader()

    private let sessionsDir: URL

    private init() {
        sessionsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/sessions")
    }

    func readLatestRateLimits() -> CodexRateLimits? {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: sessionsDir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        var jsonlFiles: [(url: URL, mtime: Date)] = []
        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl" else { continue }
            let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            jsonlFiles.append((url, mtime))
        }
        jsonlFiles.sort { $0.mtime > $1.mtime }

        // rate_limitsが記録されるのはターン完了後なので、最新ファイルが
        // まだ空（開始直後のセッション）の場合は一つ前のファイルへ
        // フォールバックする。
        for file in jsonlFiles.prefix(5) {
            if let limits = parseLatestRateLimits(in: file.url) {
                return limits
            }
        }
        return nil
    }

    private func parseLatestRateLimits(in url: URL) -> CodexRateLimits? {
        // セッションログ全体ではなく末尾だけ読む（大きいログでも毎回全文
        // ロードしない）。欲しいのは常に一番最後のrate_limitsなので十分。
        guard let content = readTail(of: url, maxBytes: 200_000) else { return nil }
        let lines = content.components(separatedBy: "\n")

        struct Window { let usedPercent: Double; let windowMinutes: Double; let resetsAt: Date? }

        func parseWindow(_ dict: [String: Any]?) -> Window? {
            // used_percent/window_minutesが欠落/型不正なら0扱い（＝実際は
            // 不明なのに「残り100%」等の誤表示）にせず、このwindowは無視する。
            guard let dict = dict,
                  let usedPercent = dict["used_percent"] as? Double,
                  let windowMinutes = dict["window_minutes"] as? Double
            else { return nil }
            let resetsAt = (dict["resets_at"] as? Double).map { Date(timeIntervalSince1970: $0) }
            return Window(usedPercent: usedPercent, windowMinutes: windowMinutes, resetsAt: resetsAt)
        }

        // primary/secondaryどちらが5時間でどちらが週間かはCodex CLI側の
        // 仕様変更で入れ替わることがある（2026-07-13に実際に発生し、
        // primaryが週間・secondaryがnullになった）ため、固定の対応関係に
        // 頼らずwindow_minutesの値で判定する。1日(1440分)未満を5時間、
        // 以上を週間とみなす。
        let dayThresholdMinutes: Double = 1440

        for line in lines.reversed() {
            guard !line.isEmpty, line.contains("\"rate_limits\""),
                  let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let payload = json["payload"] as? [String: Any],
                  let rateLimits = payload["rate_limits"] as? [String: Any]
            else { continue }

            // ここまで来たら"rate_limits"を持つ最新の行が見つかったということ
            // なので、primary/secondaryが両方ともパース不能でもここで確定
            // させる。continueして過去の行にフォールバックすると、今は
            // データがないのに古いstale%を最新値として表示してしまう。
            let windows = [
                parseWindow(rateLimits["primary"] as? [String: Any]),
                parseWindow(rateLimits["secondary"] as? [String: Any]),
            ].compactMap { $0 }

            let fiveHour = windows.filter { $0.windowMinutes < dayThresholdMinutes }
                .min { $0.windowMinutes < $1.windowMinutes }
            let weekly = windows.filter { $0.windowMinutes >= dayThresholdMinutes }
                .max { $0.windowMinutes < $1.windowMinutes }

            return CodexRateLimits(
                fiveHourPercent: fiveHour?.usedPercent,
                fiveHourResetsAt: fiveHour?.resetsAt,
                weeklyPercent: weekly?.usedPercent,
                weeklyResetsAt: weekly?.resetsAt
            )
        }
        return nil
    }

    private func readTail(of url: URL, maxBytes: Int) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let fileSize = try? handle.seekToEnd() else { return nil }
        let readSize = min(Int(fileSize), maxBytes)
        let offset = fileSize > UInt64(readSize) ? fileSize - UInt64(readSize) : 0
        do {
            try handle.seek(toOffset: offset)
        } catch { return nil }
        guard var data = try? handle.readToEnd() else { return nil }

        // 途中のオフセットから読んでいるため、先頭がUTF-8マルチバイト
        // 文字の途中で切れている可能性がある。String(data:encoding:)は
        // 一部でも無効なバイト列だと全体がnilになるため、改行(0x0A)は
        // UTF-8の続きバイトには出現しない性質を使って最初の改行より
        // 前を安全に捨ててから文字列化する。
        if offset > 0, let firstNewline = data.firstIndex(of: 0x0A) {
            data = data[data.index(after: firstNewline)...]
        }
        return String(data: data, encoding: .utf8)
    }
}
