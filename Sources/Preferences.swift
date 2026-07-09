import AppKit

enum MenuBarSource: String, CaseIterable, Equatable {
    case claudeFiveHour = "claude5h"
    case claudeWeekly = "claude7d"
    case codexFiveHour = "codex5h"
    case codexWeekly = "codexWeekly"

    var label: String {
        switch self {
        case .claudeFiveHour: return "Claude 5時間制限"
        case .claudeWeekly: return "Claude 7日間制限"
        case .codexFiveHour: return "Codex 5時間制限"
        case .codexWeekly: return "Codex 週間制限"
        }
    }
}

class Preferences {
    static let shared = Preferences()

    private let defaults = UserDefaults.standard

    private init() {
        let initial: [String: Any] = [
            "updateInterval": 30.0,
            "menuBarSource": MenuBarSource.claudeFiveHour.rawValue,
            "backgroundOpacity": 0.95
        ]
        for (key, value) in initial {
            if defaults.object(forKey: key) == nil {
                defaults.set(value, forKey: key)
            }
        }
    }

    var menuBarSource: MenuBarSource {
        get { MenuBarSource(rawValue: defaults.string(forKey: "menuBarSource") ?? "") ?? .claudeFiveHour }
        set { defaults.set(newValue.rawValue, forKey: "menuBarSource") }
    }

    var updateInterval: Double {
        get { defaults.double(forKey: "updateInterval") }
        set { defaults.set(newValue, forKey: "updateInterval") }
    }

    // ポップオーバーの背景（表示環境によっては半透明だと読みにくいため
    // 色・不透明度を自由に変えられるようにする）
    var backgroundColor: NSColor {
        get {
            if let comps = defaults.array(forKey: "backgroundColorRGB") as? [Double], comps.count == 3 {
                return NSColor(srgbRed: comps[0], green: comps[1], blue: comps[2], alpha: 1)
            }
            return NSColor.windowBackgroundColor
        }
        set {
            guard let rgb = newValue.usingColorSpace(.sRGB) else { return }
            defaults.set([Double(rgb.redComponent), Double(rgb.greenComponent), Double(rgb.blueComponent)],
                         forKey: "backgroundColorRGB")
        }
    }

    var backgroundOpacity: Double {
        get { defaults.double(forKey: "backgroundOpacity") }
        set { defaults.set(newValue, forKey: "backgroundOpacity") }
    }
}
