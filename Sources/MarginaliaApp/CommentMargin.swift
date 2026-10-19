import AppKit
import MarginaliaCore

/// One thread, rendered in the right margin: every comment in the chain, then a reply box.
final class ThreadCard: NSView, NSTextFieldDelegate {
    static let minWidth: CGFloat = 272
    static let maxWidth: CGFloat = 360
    static var width: CGFloat = 272 { didSet { if width != oldValue { NotificationCenter.default.post(name: .threadCardWidthChanged, object: nil) } } }
    private let pad: CGFloat = 12
    private var entryViews: [NSView] = []
    private let composer = NSTextField(wrappingLabelWithString: "")
    private let replyButton = NSButton(title: "Reply", target: nil, action: nil)
    private let resolveButton = NSButton(title: "Resolve", target: nil, action: nil)
    private var tracking: NSTrackingArea?
    private(set) var thread: [Comment]
    var isActive = false { didSet { needsDisplay = true } }
    var isComposing = false
    var onSelect: (() -> Void)?
    var onResolve: (() -> Void)?
    var onReply: ((String) -> Void)?
    var onCancelCompose: (() -> Void)?

    var threadStart: Int { thread.first?.threadStart ?? 0 }
    var anchorLocation: Int { thread.first.map { $0.anchorRange?.location ?? $0.range.location } ?? 0 }

    init(thread: [Comment]) {
        self.thread = thread
        super.init(frame: NSRect(x: 0, y: 0, width: ThreadCard.width, height: 60))
        wantsLayer = true
        layer?.cornerRadius = 8
        composer.font = ChromeFont.regular(13)
        composer.textColor = Palette.fg
        composer.isEditable = true
        composer.isSelectable = true
        composer.drawsBackground = false
        composer.isBordered = false
        composer.focusRingType = .none
        composer.lineBreakMode = .byWordWrapping
        composer.maximumNumberOfLines = 0
        composer.placeholderAttributedString = NSAttributedString(string: "Reply…", attributes: [.font: ChromeFont.regular(13), .foregroundColor: Palette.fgMuted])
        composer.delegate = self
        composer.isHidden = true
        addSubview(composer)
        for b in [replyButton, resolveButton] {
            b.isBordered = false
            b.font = ChromeFont.medium(11)
            b.contentTintColor = Palette.fgMuted
            b.alphaValue = 0
            b.setButtonType(.momentaryChange)
            b.target = self
            addSubview(b)
        }
        replyButton.action = #selector(replyTapped)
        resolveButton.action = #selector(resolveTapped)
        apply(thread)
    }
    required init?(coder: NSCoder) { fatalError() }

    func apply(_ t: [Comment]) {
        thread = t
        for v in entryViews { v.removeFromSuperview() }
        entryViews.removeAll()
        for c in t {
            let who = NSTextField(labelWithString: c.author.map { "@\($0)" } ?? "note")
            who.font = ChromeFont.medium(11)
            who.textColor = c.author == "claude" ? Palette.accent : Palette.fgMuted
            let body = NSTextField(wrappingLabelWithString: c.text)
            body.font = ChromeFont.regular(13)
            body.textColor = Palette.fg
            body.isSelectable = true
            body.lineBreakMode = .byWordWrapping
            body.maximumNumberOfLines = 0
            addSubview(who); addSubview(body)
            entryViews.append(who); entryViews.append(body)
        }
        relayout()
    }

    override var isFlipped: Bool { true }

    func relayout() {
        let w = ThreadCard.width
        if frame.width != w { frame.size.width = w }
        let bodyWidth = w - 2 * pad
        var y: CGFloat = 10
        var i = 0
        while i + 1 < entryViews.count {
            let who = entryViews[i], body = entryViews[i + 1]
            if i > 0 { y += 8 }
            who.frame = NSRect(x: pad, y: y, width: bodyWidth, height: 14)
            y += 16
            if let b = body as? NSTextField {
                b.preferredMaxLayoutWidth = bodyWidth
                let h = max(16, b.sizeThatFits(NSSize(width: bodyWidth, height: 10_000)).height)
                b.frame = NSRect(x: pad, y: y, width: bodyWidth, height: h)
                y += h
            }
            i += 2
        }
        if isComposing {
            y += 10
            composer.isHidden = false
            composer.preferredMaxLayoutWidth = bodyWidth
            let h = max(18, composer.sizeThatFits(NSSize(width: bodyWidth, height: 10_000)).height)
            composer.frame = NSRect(x: pad, y: y, width: bodyWidth, height: h)
            y += h
        } else {
            composer.isHidden = true
        }
        y += 10
        replyButton.sizeToFit(); resolveButton.sizeToFit()
        let buttonsH: CGFloat = 18
        resolveButton.frame.origin = NSPoint(x: w - pad - resolveButton.frame.width, y: y - 2)
        replyButton.frame.origin = NSPoint(x: resolveButton.frame.minX - 12 - replyButton.frame.width, y: y - 2)
        frame.size = NSSize(width: w, height: y + buttonsH)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: r, xRadius: 8, yRadius: 8)
        Palette.bgElevated.setFill(); path.fill()
        (isActive ? Palette.accent.withAlphaComponent(0.6) : Palette.fgFaint.withAlphaComponent(0.7)).setStroke()
        path.lineWidth = 1
        path.stroke()
        if isComposing {
            let y = composer.frame.minY - 5
            Palette.fgFaint.setFill()
            NSRect(x: pad, y: y, width: bounds.width - 2 * pad, height: 1).fill()
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracking { removeTrackingArea(t) }
        tracking = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(tracking!)
    }
    override func mouseEntered(with event: NSEvent) { setButtons(visible: true) }
    override func mouseExited(with event: NSEvent) { if !isComposing { setButtons(visible: false) } }
    private func setButtons(visible: Bool) {
        NSAnimationContext.runAnimationGroup { ctx in ctx.duration = 0.12; replyButton.animator().alphaValue = visible ? 1 : 0; resolveButton.animator().alphaValue = visible ? 1 : 0 }
    }

    override func mouseDown(with event: NSEvent) { onSelect?() }
    @objc private func replyTapped() { beginReply() }
    @objc private func resolveTapped() { onResolve?() }

    // MARK: Composing

    func beginReply() {
        guard !isComposing else { window?.makeFirstResponder(composer); return }
        isComposing = true
        composer.stringValue = ""
        relayout()
        setButtons(visible: true)
        superview?.needsLayout = true
        (superview as? NSTextView)?.needsDisplay = true
        DispatchQueue.main.async { [weak self] in guard let self else { return }; self.window?.makeFirstResponder(self.composer) }
    }

    func commitComposer(_ text: String? = nil) {
        guard isComposing else { return }
        let t = (text ?? composer.stringValue).trimmingCharacters(in: .whitespacesAndNewlines)
        isComposing = false
        composer.isHidden = true
        relayout()
        if t.isEmpty { onCancelCompose?() } else { onReply?(t) }
        setButtons(visible: false)
    }

    func cancelComposer() {
        guard isComposing else { return }
        isComposing = false
        composer.isHidden = true
        relayout()
        onCancelCompose?()
        setButtons(visible: false)
    }

    func controlTextDidChange(_ obj: Notification) { relayout(); (superview as? NSTextView)?.needsDisplay = true; superview?.needsLayout = true }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        if sel == #selector(NSResponder.insertNewline(_:)) {
            if NSApp.currentEvent?.modifierFlags.contains(.shift) == true { textView.insertNewlineIgnoringFieldEditor(nil); return true }
            commitComposer(); return true
        }
        if sel == #selector(NSResponder.cancelOperation(_:)) { cancelComposer(); return true }
        return false
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        // Focus left the composer (click elsewhere): keep typed text as a reply, drop empty ones.
        if isComposing { commitComposer() }
    }

    func dropSilently() {
        guard isComposing else { return }
        isComposing = false
        onReply = nil; onCancelCompose = nil
        if window?.firstResponder == composer.currentEditor() { window?.makeFirstResponder(nil) }
    }
}

/// Owns thread cards, positions them against their anchors, resolves overlaps top to bottom.
final class CommentMargin {
    unowned let textView: EditorTextView
    private(set) var cards: [ThreadCard] = []
    var enabled = false
    var x: CGFloat = 0
    var activeIndex: Int? = nil { didSet { if activeIndex != oldValue { for (i, c) in cards.enumerated() { c.isActive = activeThreadStart.map { $0 == c.threadStart } ?? false; _ = i } } } }
    var onSelect: ((Comment) -> Void)?
    var onResolveThread: (([Comment]) -> Void)?
    var onReplyText: (([Comment], String) -> Void)?
    var onCommit: ((Comment, String) -> Void)?
    var onReply: ((Comment) -> Void)?
    var onResolve: ((Comment) -> Void)?
    private var pendingCompose: (threadStart: Int, initial: String?)?
    private var comments: [Comment] = []

    init(textView: EditorTextView) { self.textView = textView }

    private var activeThreadStart: Int? { activeIndex.flatMap { $0 < comments.count ? comments[$0].threadStart : nil } }

    /// Opens the reply box on the thread starting at `threadStart` once it exists.
    func editSoon(threadStart: Int, initial: String? = nil) { pendingCompose = (threadStart, initial) }

    func beginReply(threadStart: Int) {
        if let c = cards.first(where: { $0.threadStart == threadStart }) { c.beginReply() } else { pendingCompose = (threadStart, nil) }
    }

    func update(comments all: [Comment]) {
        comments = all
        guard enabled else { clear(); return }
        var threads: [[Comment]] = []
        for c in all {
            if let last = threads.last, last.first?.threadStart == c.threadStart { threads[threads.count - 1].append(c) } else { threads.append([c]) }
        }
        var reusable = cards
        var next: [ThreadCard] = []
        for t in threads {
            let start = t.first!.threadStart
            var idx = reusable.firstIndex { $0.threadStart == start }
            if idx == nil {
                // text before it may have shifted: same authors + texts, nearest position
                let sig = t.map { ($0.author ?? "") + "|" + $0.text }
                idx = reusable.enumerated().filter { $0.element.thread.map { ($0.author ?? "") + "|" + $0.text } == sig }
                    .min { abs($0.element.threadStart - start) < abs($1.element.threadStart - start) }?.offset
            }
            if idx == nil, let composing = reusable.firstIndex(where: { $0.isComposing && $0.thread.count + 1 == t.count }) { idx = composing }
            if let i = idx {
                let card = reusable.remove(at: i)
                card.apply(t)
                next.append(card)
            } else {
                let card = ThreadCard(thread: t)
                wire(card)
                textView.addSubview(card)
                card.alphaValue = 0
                NSAnimationContext.runAnimationGroup { ctx in ctx.duration = 0.1; card.animator().alphaValue = 1 }
                next.append(card)
            }
        }
        for r in reusable { r.dropSilently(); r.removeFromSuperview() }
        cards = next
        for c in cards { c.isActive = activeThreadStart == c.threadStart }
        layout()
        if let p = pendingCompose, let card = cards.min(by: { abs($0.threadStart - p.threadStart) < abs($1.threadStart - p.threadStart) }), abs(card.threadStart - p.threadStart) < 6 {
            pendingCompose = nil
            card.beginReply()
        }
    }

    private func wire(_ card: ThreadCard) {
        card.onSelect = { [weak self, weak card] in if let c = card?.thread.first { self?.onSelect?(c) } }
        card.onResolve = { [weak self, weak card] in if let t = card?.thread { self?.onResolveThread?(t) } }
        card.onReply = { [weak self, weak card] text in
            guard let self, let t = card?.thread else { return }
            // A fresh thread is one empty comment: the first text fills it instead of replying to it.
            if t.count == 1, t[0].text.isEmpty { self.onCommit?(t[0], text) } else { self.onReplyText?(t, text) }
        }
        card.onCancelCompose = { [weak self, weak card] in
            // A brand new thread with no text yet: cancelling removes the empty comment.
            guard let self, let card, card.thread.count == 1, card.thread[0].text.isEmpty else { return }
            self.onResolveThread?(card.thread)
        }
    }

    func clear() {
        for c in cards { c.removeFromSuperview() }
        cards.removeAll()
    }

    func layout() {
        guard enabled, !cards.isEmpty, let tlm = textView.textLayoutManager, let tcs = textView.textContentStorage else { return }
        let origin = textView.textContainerOrigin
        let docStart = tcs.documentRange.location
        let visible = textView.visibleRect.insetBy(dx: 0, dy: -textView.visibleRect.height)
        var near = 0..<Int.max
        if let vr = tlm.textViewportLayoutController.viewportRange {
            let a = tcs.offset(from: docStart, to: vr.location), b = tcs.offset(from: docStart, to: vr.endLocation)
            near = max(0, a - 12_000)..<(b + 12_000)
        }
        var lastBottom: CGFloat = -.greatestFiniteMagnitude
        for card in cards {
            let anchor = card.anchorLocation
            guard near.contains(anchor), let loc = tcs.location(docStart, offsetBy: anchor) else { card.isHidden = true; continue }
            var y: CGFloat? = nil
            tlm.enumerateTextLayoutFragments(from: loc, options: [.ensuresLayout]) { f in
                let inFrag = anchor - tcs.offset(from: docStart, to: f.rangeInElement.location)
                var yy = f.layoutFragmentFrame.minY
                for lf in f.textLineFragments where NSLocationInRange(inFrag, lf.characterRange) || lf.characterRange.location + lf.characterRange.length == inFrag {
                    yy = f.layoutFragmentFrame.minY + lf.typographicBounds.minY; break
                }
                y = yy; return false
            }
            guard var top = y.map({ $0 + origin.y - 2 }) else { card.isHidden = true; continue }
            top = max(top, lastBottom + 8)
            card.frame.origin = NSPoint(x: x, y: top)
            card.isHidden = !card.frame.intersects(visible)
            lastBottom = top + card.frame.height
        }
    }

    func drawConnectors(colRight: CGFloat) {
        guard enabled else { return }
        for card in cards where !card.isHidden {
            let y = card.frame.minY + 12
            let r = NSRect(x: colRight + 6, y: y, width: max(0, x - colRight - 10), height: 1)
            (card.isActive ? Palette.accent.withAlphaComponent(0.5) : Palette.fgFaint).setFill()
            r.fill()
        }
    }
}


extension Notification.Name { static let threadCardWidthChanged = Notification.Name("marginalia.threadCardWidthChanged") }
