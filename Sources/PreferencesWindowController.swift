import Cocoa

extension Notification.Name {
    static let preferencesChanged = Notification.Name("ClaudeTokenBarPreferencesChanged")
}

class PreferencesWindowController: NSWindowController {
    static let shared = PreferencesWindowController()

    private var updateIntervalField: NSTextField!
    private var menuBarSourcePopup: NSPopUpButton!
    private var backgroundColorWell: NSColorWell!
    private var backgroundOpacitySlider: NSSlider!
    private var backgroundOpacityValueLabel: NSTextField!

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 239),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "設定 — TokenHub"
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        buildUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func buildUI() {
        guard let cv = window?.contentView else { return }
        let prefs = Preferences.shared

        let rows: [(label: String, value: String, hint: String)] = [
            ("更新間隔 (秒):", String(Int(prefs.updateInterval)), "最低10秒")
        ]

        let labelX: CGFloat = 20
        let fieldX: CGFloat = 190
        let hintX: CGFloat = 190
        var y: CGFloat = 169
        let rowH: CGFloat = 44

        let sourceLbl = NSTextField(labelWithString: "メニューバー表示:")
        sourceLbl.frame = NSRect(x: labelX, y: y + 14, width: 165, height: 17)
        sourceLbl.alignment = .right
        sourceLbl.font = .systemFont(ofSize: 13)
        cv.addSubview(sourceLbl)

        menuBarSourcePopup = NSPopUpButton(frame: NSRect(x: fieldX, y: y + 9, width: 190, height: 25))
        for source in MenuBarSource.allCases {
            menuBarSourcePopup.addItem(withTitle: source.label)
        }
        if let index = MenuBarSource.allCases.firstIndex(of: prefs.menuBarSource) {
            menuBarSourcePopup.selectItem(at: index)
        }
        cv.addSubview(menuBarSourcePopup)
        y -= rowH

        let bgLbl = NSTextField(labelWithString: "背景:")
        bgLbl.frame = NSRect(x: labelX, y: y + 10, width: 165, height: 17)
        bgLbl.alignment = .right
        bgLbl.font = .systemFont(ofSize: 13)
        cv.addSubview(bgLbl)

        backgroundColorWell = NSColorWell(frame: NSRect(x: fieldX, y: y + 2, width: 44, height: 24))
        backgroundColorWell.color = prefs.backgroundColor
        cv.addSubview(backgroundColorWell)

        backgroundOpacitySlider = NSSlider(frame: NSRect(x: fieldX + 54, y: y + 2, width: 100, height: 24))
        backgroundOpacitySlider.minValue = 0.3
        backgroundOpacitySlider.maxValue = 1.0
        backgroundOpacitySlider.doubleValue = prefs.backgroundOpacity
        backgroundOpacitySlider.target = self
        backgroundOpacitySlider.action = #selector(opacitySliderChanged)
        cv.addSubview(backgroundOpacitySlider)

        backgroundOpacityValueLabel = NSTextField(labelWithString: "\(Int(prefs.backgroundOpacity * 100))%")
        backgroundOpacityValueLabel.frame = NSRect(x: fieldX + 160, y: y + 5, width: 40, height: 17)
        backgroundOpacityValueLabel.font = .systemFont(ofSize: 11)
        backgroundOpacityValueLabel.textColor = .secondaryLabelColor
        cv.addSubview(backgroundOpacityValueLabel)
        y -= rowH

        var fields: [NSTextField] = []
        for row in rows {
            let lbl = NSTextField(labelWithString: row.label)
            lbl.frame = NSRect(x: labelX, y: y + 14, width: 165, height: 17)
            lbl.alignment = .right
            lbl.font = .systemFont(ofSize: 13)
            cv.addSubview(lbl)

            let field = NSTextField(frame: NSRect(x: fieldX, y: y + 12, width: 150, height: 22))
            field.stringValue = row.value
            field.font = .systemFont(ofSize: 13)
            cv.addSubview(field)
            fields.append(field)

            let hint = NSTextField(labelWithString: row.hint)
            hint.frame = NSRect(x: hintX, y: y, width: 200, height: 13)
            hint.font = .systemFont(ofSize: 10)
            hint.textColor = .tertiaryLabelColor
            cv.addSubview(hint)

            y -= rowH
        }

        updateIntervalField = fields[0]

        // Buttons
        let saveBtn = NSButton(title: "保存", target: self, action: #selector(save))
        saveBtn.bezelStyle = .rounded
        saveBtn.keyEquivalent = "\r"
        saveBtn.frame = NSRect(x: 300, y: 20, width: 80, height: 28)
        cv.addSubview(saveBtn)

        let cancelBtn = NSButton(title: "キャンセル", target: self, action: #selector(cancelAction))
        cancelBtn.bezelStyle = .rounded
        cancelBtn.keyEquivalent = "\u{1b}"
        cancelBtn.frame = NSRect(x: 200, y: 20, width: 92, height: 28)
        cv.addSubview(cancelBtn)
    }

    @objc private func opacitySliderChanged() {
        backgroundOpacityValueLabel.stringValue = "\(Int(backgroundOpacitySlider.doubleValue * 100))%"
    }

    @objc private func save() {
        let prefs = Preferences.shared
        if let v = Double(updateIntervalField.stringValue), v >= 10 { prefs.updateInterval = v }
        prefs.menuBarSource = MenuBarSource.allCases[menuBarSourcePopup.indexOfSelectedItem]
        prefs.backgroundColor = backgroundColorWell.color
        prefs.backgroundOpacity = backgroundOpacitySlider.doubleValue
        window?.close()
        NotificationCenter.default.post(name: .preferencesChanged, object: nil)
    }

    @objc private func cancelAction() {
        window?.close()
    }
}
