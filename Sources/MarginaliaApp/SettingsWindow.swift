import AppKit

/// One pane: theme, size, author tag, change-mark lifetime, keep running. Plain AppKit.
final class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()
    private let themePopup = NSPopUpButton()
    private let sizeField = NSTextField()
    private let sizeStepper = NSStepper()
    private let authorField = NSTextField()
    private let fadeField = NSTextField()
    private let keepRunning = NSButton(checkboxWithTitle: "Keep running after the last window closes", target: nil, action: nil)

    private init() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 250), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = "Settings"
        w.center()
        super.init(window: w)
        build()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func label(_ s: String, _ y: CGFloat) -> NSTextField {
        let l = NSTextField(labelWithString: s)
        l.font = ChromeFont.regular(13); l.textColor = Palette.fgMuted; l.alignment = .right
        l.frame = NSRect(x: 20, y: y, width: 130, height: 20)
        return l
    }

    private func build() {
        guard let cv = window?.contentView else { return }
        cv.wantsLayer = true
        let d = UserDefaults.standard
        var y: CGFloat = 200

        cv.addSubview(label("Theme", y))
        themePopup.frame = NSRect(x: 160, y: y - 3, width: 200, height: 26)
        for t in ThemeSpec.all { themePopup.addItem(withTitle: t.name) }
        themePopup.selectItem(withTitle: ThemeSpec.named(d.string(forKey: "theme") ?? "geist").name)
        themePopup.target = self; themePopup.action = #selector(themeChanged)
        cv.addSubview(themePopup)
        y -= 40

        cv.addSubview(label("Body size", y))
        sizeField.frame = NSRect(x: 160, y: y - 2, width: 50, height: 24)
        sizeField.alignment = .center
        let size = d.double(forKey: "bodySize")
        sizeField.integerValue = Int(size > 0 ? size : 17)
        sizeField.target = self; sizeField.action = #selector(sizeChanged)
        sizeStepper.frame = NSRect(x: 214, y: y - 3, width: 20, height: 26)
        sizeStepper.minValue = 11; sizeStepper.maxValue = 32; sizeStepper.integerValue = sizeField.integerValue
        sizeStepper.target = self; sizeStepper.action = #selector(stepperChanged)
        cv.addSubview(sizeField); cv.addSubview(sizeStepper)
        y -= 40

        cv.addSubview(label("Author tag", y))
        authorField.frame = NSRect(x: 160, y: y - 2, width: 120, height: 24)
        authorField.stringValue = d.string(forKey: "authorTag") ?? "sebo"
        authorField.placeholderString = "sebo"
        authorField.target = self; authorField.action = #selector(authorChanged)
        let at = NSTextField(labelWithString: "comments are written as {>>@tag: …<<}")
        at.font = ChromeFont.regular(11); at.textColor = Palette.fgMuted
        at.frame = NSRect(x: 160, y: y - 20, width: 240, height: 16)
        cv.addSubview(authorField); cv.addSubview(at)
        y -= 56

        cv.addSubview(label("Change marks fade", y))
        fadeField.frame = NSRect(x: 160, y: y - 2, width: 50, height: 24)
        fadeField.alignment = .center
        let fade = d.double(forKey: "changeFade")
        fadeField.doubleValue = fade > 0 ? fade : 8
        fadeField.target = self; fadeField.action = #selector(fadeChanged)
        let sec = NSTextField(labelWithString: "seconds")
        sec.font = ChromeFont.regular(13); sec.textColor = Palette.fgMuted
        sec.frame = NSRect(x: 216, y: y, width: 80, height: 20)
        cv.addSubview(fadeField); cv.addSubview(sec)
        y -= 40

        keepRunning.frame = NSRect(x: 160, y: y, width: 260, height: 20)
        keepRunning.font = ChromeFont.regular(13)
        keepRunning.state = d.object(forKey: "keepRunning") == nil ? .on : (d.bool(forKey: "keepRunning") ? .on : .off)
        keepRunning.target = self; keepRunning.action = #selector(keepChanged)
        cv.addSubview(keepRunning)
    }

    private var controllers: [DocumentWindowController] { (NSApp.delegate as? AppDelegate)?.windows ?? [] }

    @objc private func themeChanged() {
        let t = ThemeSpec.all[max(0, themePopup.indexOfSelectedItem)]
        for c in controllers { c.setTheme(t) }
        UserDefaults.standard.set(t.id, forKey: "theme")
        sizeField.integerValue = Int(t.bodySize); sizeStepper.integerValue = Int(t.bodySize)
    }
    @objc private func sizeChanged() { sizeStepper.integerValue = sizeField.integerValue; applySize() }
    @objc private func stepperChanged() { sizeField.integerValue = sizeStepper.integerValue; applySize() }
    private func applySize() {
        let s = CGFloat(max(11, min(32, sizeField.integerValue)))
        for c in controllers { c.setBodySize(s) }
        UserDefaults.standard.set(Double(s), forKey: "bodySize")
    }
    @objc private func authorChanged() {
        let tag = authorField.stringValue.trimmingCharacters(in: CharacterSet(charactersIn: "@ \t")).lowercased()
        UserDefaults.standard.set(tag.isEmpty ? "sebo" : tag, forKey: "authorTag")
    }
    @objc private func fadeChanged() { UserDefaults.standard.set(max(1, fadeField.doubleValue), forKey: "changeFade") }
    @objc private func keepChanged() { UserDefaults.standard.set(keepRunning.state == .on, forKey: "keepRunning") }

    func show() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
