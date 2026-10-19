import AppKit
import MarginaliaCore

/// Icon button with hover and pressed fills, the baseline for any modern toolbar.
final class HoverButton: NSButton {
    private var hovering = false { didSet { needsDisplay = true } }
    private var tracking: NSTrackingArea?
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracking { removeTrackingArea(t) }
        tracking = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(tracking!)
    }
    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func draw(_ dirtyRect: NSRect) {
        if isHighlighted || hovering {
            Palette.fg.withAlphaComponent(isHighlighted ? 0.14 : 0.07).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 6, yRadius: 6).fill()
        }
        super.draw(dirtyRect)
    }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .arrow) }
}

/// Floating formatting bar shown above a text selection. Lives inside the text view so it scrolls with the text.
final class FormatBar: NSView {
    unowned let textView: EditorTextView
    private var buttons: [NSButton] = []
    private let headingMenu = NSPopUpButton(frame: .zero, pullsDown: true)
    private let h: CGFloat = 34
    var onComment: (() -> Void)?

    struct Item { let symbol: String; let tip: String; let action: Selector }

    init(textView: EditorTextView) {
        self.textView = textView
        super.init(frame: NSRect(x: 0, y: 0, width: 10, height: 34))
        wantsLayer = true
        layer?.cornerRadius = 8
        shadow = NSShadow()
        shadow?.shadowColor = NSColor.black.withAlphaComponent(0.14)
        shadow?.shadowBlurRadius = 10
        shadow?.shadowOffset = NSSize(width: 0, height: -3)
        isHidden = true

        let items: [Item?] = [
            Item(symbol: "bold", tip: "Bold ⌘B", action: #selector(EditorTextView.toggleBold(_:))),
            Item(symbol: "italic", tip: "Italic ⌘I", action: #selector(EditorTextView.toggleItalic(_:))),
            Item(symbol: "strikethrough", tip: "Strikethrough", action: #selector(EditorTextView.toggleStrike(_:))),
            Item(symbol: "chevron.left.forwardslash.chevron.right", tip: "Code ⌘E", action: #selector(EditorTextView.toggleCodeSpan(_:))),
            Item(symbol: "link", tip: "Link ⌘⇧K", action: #selector(EditorTextView.insertLink(_:))),
            nil,
            Item(symbol: "list.bullet", tip: "Bulleted list ⌘⇧8", action: #selector(EditorTextView.toggleBulletList(_:))),
            Item(symbol: "list.number", tip: "Numbered list ⌘⇧7", action: #selector(EditorTextView.toggleNumberList(_:))),
            Item(symbol: "checklist", tip: "Task list ⌘⇧9", action: #selector(EditorTextView.toggleTaskList(_:))),
            Item(symbol: "text.quote", tip: "Quote ⌘⇧.", action: #selector(EditorTextView.toggleQuote(_:))),
            nil,
            Item(symbol: "text.bubble", tip: "Comment ⌘⇧M", action: #selector(DocumentWindowController.addComment(_:))),
        ]
        var x: CGFloat = 6
        // Heading pull-down first.
        headingMenu.isBordered = false
        headingMenu.font = ChromeFont.medium(13)
        headingMenu.contentTintColor = Palette.fg
        let menu = NSMenu()
        let top = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        top.image = NSImage(systemSymbolName: "textformat.size", accessibilityDescription: "Heading")
        menu.addItem(top)
        for (title, tag) in [("Heading 1", 1), ("Heading 2", 2), ("Heading 3", 3), ("Paragraph", 0)] {
            let mi = NSMenuItem(title: title, action: #selector(EditorTextView.setHeadingLevel(_:)), keyEquivalent: "")
            mi.tag = tag
            mi.target = textView
            menu.addItem(mi)
        }
        headingMenu.menu = menu
        headingMenu.frame = NSRect(x: x, y: 3, width: 44, height: 28)
        headingMenu.toolTip = "Heading"
        addSubview(headingMenu)
        x += 46
        x = addSeparator(at: x)
        for it in items {
            guard let it else { x = addSeparator(at: x); continue }
            let b = HoverButton(frame: NSRect(x: x, y: 3, width: 28, height: 28))
            b.isBordered = false
            b.image = NSImage(systemSymbolName: it.symbol, accessibilityDescription: it.tip)?.withSymbolConfiguration(.init(pointSize: 13, weight: .medium))
            b.imagePosition = .imageOnly
            b.contentTintColor = Palette.fg
            b.toolTip = it.tip
            b.target = nil
            b.action = it.action
            b.setButtonType(.momentaryChange)
            addSubview(b)
            buttons.append(b)
            x += 30
        }
        frame.size = NSSize(width: x + 4, height: h)
        textView.addSubview(self)
    }
    required init?(coder: NSCoder) { fatalError() }

    private func addSeparator(at x: CGFloat) -> CGFloat {
        let v = NSView(frame: NSRect(x: x + 3, y: 9, width: 1, height: h - 18))
        v.wantsLayer = true
        v.layer?.backgroundColor = Palette.fgFaint.cgColor
        addSubview(v)
        return x + 8
    }

    override func draw(_ dirtyRect: NSRect) {
        let p = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8)
        Palette.bgElevated.setFill(); p.fill()
        Palette.fgFaint.withAlphaComponent(0.8).setStroke(); p.stroke()
    }

    override func viewDidChangeEffectiveAppearance() {
        for v in subviews where v.wantsLayer && !(v is NSControl) { v.layer?.backgroundColor = Palette.fgFaint.cgColor }
        needsDisplay = true
    }

    /// Shows the bar above the selection. Call after a mouse-up or a keyboard selection change.
    func update(selection: NSRange) {
        guard selection.length > 0, textView.window != nil, textView.isEditable,
              let tlm = textView.textLayoutManager, let tcs = textView.textContentStorage,
              let s = tcs.location(tcs.documentRange.location, offsetBy: selection.location),
              let e = tcs.location(tcs.documentRange.location, offsetBy: selection.location + selection.length),
              let tr = NSTextRange(location: s, end: e) else { hide(); return }
        var first: NSRect? = nil
        tlm.enumerateTextSegments(in: tr, type: .selection, options: [.rangeNotRequired]) { _, f, _, _ in first = f; return false }
        guard let f = first else { hide(); return }
        let origin = textView.textContainerOrigin
        let x = max(origin.x + 8, min(f.midX + origin.x - frame.width / 2, textView.bounds.width - frame.width - 8))
        var y = f.minY + origin.y - frame.height - 10
        if y < textView.visibleRect.minY + 4 { y = f.maxY + origin.y + 10 }   // no room above: go below
        frame.origin = NSPoint(x: x.rounded(), y: y.rounded())
        if isHidden {
            alphaValue = 0
            isHidden = false
            NSAnimationContext.runAnimationGroup { ctx in ctx.duration = 0.1; animator().alphaValue = 1 }
        }
    }

    func hide() { if !isHidden { isHidden = true } }
}

/// Bottom-right "Text | Markdown" switch.
final class ModeToggle: NSView {
    var sourceMode = false { didSet { needsDisplay = true } }
    var onToggle: ((Bool) -> Void)?
    private var tracking: NSTrackingArea?
    private let labels = ["Text", "Markdown"]
    private let font = ChromeFont.medium(11)

    override init(frame: NSRect) {
        super.init(frame: NSRect(x: 0, y: 0, width: 128, height: 24))
        wantsLayer = true
        alphaValue = 0.6
        toolTip = "Switch between styled text and Markdown (⌘⇧R)"
    }
    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracking { removeTrackingArea(t) }
        tracking = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow], owner: self, userInfo: nil)
        addTrackingArea(tracking!)
    }
    override func mouseEntered(with event: NSEvent) { NSAnimationContext.runAnimationGroup { c in c.duration = 0.12; animator().alphaValue = 1 } }
    override func mouseExited(with event: NSEvent) { NSAnimationContext.runAnimationGroup { c in c.duration = 0.25; animator().alphaValue = 0.6 } }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let wantSource = p.x > bounds.width * 0.38
        if wantSource != sourceMode { onToggle?(wantSource) }
    }

    override func draw(_ dirtyRect: NSRect) {
        let pill = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: bounds.height / 2, yRadius: bounds.height / 2)
        Palette.bgElevated.setFill(); pill.fill()
        Palette.fgFaint.setStroke(); pill.stroke()
        let split = bounds.width * 0.38
        let active = sourceMode ? NSRect(x: split, y: 2, width: bounds.width - split - 2, height: bounds.height - 4) : NSRect(x: 2, y: 2, width: split - 2, height: bounds.height - 4)
        Palette.accent.withAlphaComponent(0.14).setFill()
        NSBezierPath(roundedRect: active, xRadius: active.height / 2, yRadius: active.height / 2).fill()
        let ps = NSMutableParagraphStyle(); ps.alignment = .center
        for (i, l) in labels.enumerated() {
            let on = (i == 1) == sourceMode
            let a: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: on ? Palette.fg : Palette.fgMuted, .paragraphStyle: ps]
            let r = i == 0 ? NSRect(x: 0, y: 5, width: split, height: 14) : NSRect(x: split, y: 5, width: bounds.width - split, height: 14)
            NSAttributedString(string: l, attributes: a).draw(in: r)
        }
    }
}
