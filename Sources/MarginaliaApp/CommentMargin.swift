import AppKit
import MarginaliaCore

/// One comment, rendered in the right margin. Editable body, ghost buttons on hover.
final class CommentCard: NSView, NSTextFieldDelegate {
    static let width: CGFloat = 272
    let authorLabel = NSTextField(labelWithString: "")
    let body = NSTextField(wrappingLabelWithString: "")
    let resolveButton = NSButton(title: "Resolve", target: nil, action: nil)
    let replyButton = NSButton(title: "Reply", target: nil, action: nil)
    private var tracking: NSTrackingArea?
    var comment: Comment
    var isActive = false { didSet { needsDisplay = true } }
    var onSelect: (() -> Void)?
    var onResolve: (() -> Void)?
    var onReply: (() -> Void)?
    var onCommit: ((String) -> Void)?
    var onCancel: (() -> Void)?

    init(comment: Comment) {
        self.comment = comment
        super.init(frame: NSRect(x: 0, y: 0, width: CommentCard.width, height: 60))
        wantsLayer = true
        layer?.cornerRadius = 6
        authorLabel.font = ChromeFont.medium(11)
        authorLabel.textColor = Palette.fgMuted
        body.font = ChromeFont.regular(13)
        body.textColor = Palette.fg
        body.isEditable = false
        body.isSelectable = true
        body.drawsBackground = false
        body.isBordered = false
        body.focusRingType = .none
        body.lineBreakMode = .byWordWrapping
        body.maximumNumberOfLines = 0
        body.delegate = self
        for b in [resolveButton, replyButton] {
            b.isBordered = false
            b.font = ChromeFont.medium(11)
            b.contentTintColor = Palette.fgMuted
            b.alphaValue = 0
            b.setButtonType(.momentaryChange)
            b.target = self
        }
        resolveButton.action = #selector(resolveTapped)
        replyButton.action = #selector(replyTapped)
        addSubview(authorLabel); addSubview(body); addSubview(resolveButton); addSubview(replyButton)
        apply(comment)
    }
    required init?(coder: NSCoder) { fatalError() }

    func apply(_ c: Comment) {
        comment = c
        let who = c.author.map { "@\($0)" } ?? "note"
        authorLabel.stringValue = who
        authorLabel.textColor = c.author == "claude" ? Palette.accent : Palette.fgMuted
        if !body.isEditable { body.stringValue = c.text }
        relayout()
    }

    func relayout() {
        let w = CommentCard.width
        let pad: CGFloat = 12
        authorLabel.sizeToFit()
        authorLabel.frame = NSRect(x: pad, y: 0, width: w - 2 * pad - 110, height: authorLabel.frame.height)
        let bodyWidth = w - 2 * pad
        body.preferredMaxLayoutWidth = bodyWidth
        let h = max(18, body.sizeThatFits(NSSize(width: bodyWidth, height: 10_000)).height)
        body.frame = NSRect(x: pad, y: authorLabel.frame.height + 4 + 8, width: bodyWidth, height: h)
        authorLabel.frame.origin.y = 8
        resolveButton.sizeToFit(); replyButton.sizeToFit()
        replyButton.frame.origin = NSPoint(x: w - pad - replyButton.frame.width, y: 6)
        resolveButton.frame.origin = NSPoint(x: replyButton.frame.minX - 8 - resolveButton.frame.width, y: 6)
        frame.size = NSSize(width: w, height: body.frame.maxY + 10)
        needsDisplay = true
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: r, xRadius: 6, yRadius: 6)
        Palette.bgElevated.setFill(); path.fill()
        (isActive ? Palette.accent.withAlphaComponent(0.7) : Palette.fgFaint).setStroke()
        path.lineWidth = isActive ? 1.5 : 1
        path.stroke()
        // comment-colored edge
        let edge = NSRect(x: 0, y: 6, width: 2, height: bounds.height - 12)
        Palette.commentText.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: edge, xRadius: 1, yRadius: 1).fill()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracking { removeTrackingArea(t) }
        tracking = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(tracking!)
    }
    override func mouseEntered(with event: NSEvent) { setButtons(visible: true) }
    override func mouseExited(with event: NSEvent) { if !body.isEditable { setButtons(visible: false) } }
    private func setButtons(visible: Bool) {
        NSAnimationContext.runAnimationGroup { ctx in ctx.duration = 0.12; resolveButton.animator().alphaValue = visible ? 1 : 0; replyButton.animator().alphaValue = visible ? 1 : 0 }
    }

    override func mouseDown(with event: NSEvent) { onSelect?() }
    @objc private func resolveTapped() { onResolve?() }
    @objc private func replyTapped() { onReply?() }

    // MARK: Editing

    func beginEditing(initial: String? = nil) {
        body.isEditable = true
        if let initial { body.stringValue = initial }
        setButtons(visible: true)
        window?.makeFirstResponder(body)
        relayout()
    }

    func controlTextDidChange(_ obj: Notification) { relayout(); superview?.needsLayout = true; (superview as? NSTextView)?.needsDisplay = true }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            if NSApp.currentEvent?.modifierFlags.contains(.shift) == true { textView.insertNewlineIgnoringFieldEditor(nil); return true }
            endEditing(commit: true); return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) { endEditing(commit: false); return true }
        return false
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        if body.isEditable { endEditing(commit: true) }
    }

    /// Stops editing without committing or cancelling (the card is going away).
    func dropSilently() {
        guard body.isEditable else { return }
        body.isEditable = false
        onCommit = nil; onCancel = nil
        if window?.firstResponder == body.currentEditor() { window?.makeFirstResponder(nil) }
    }

    func endEditing(commit: Bool) {
        guard body.isEditable else { return }
        body.isEditable = false
        let text = body.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if commit { onCommit?(text) } else { onCancel?() }
        setButtons(visible: false)
    }
}

/// Owns the cards, positions them against their anchors, and resolves overlaps top to bottom.
final class CommentMargin {
    unowned let textView: EditorTextView
    private(set) var cards: [CommentCard] = []
    var enabled = false
    var x: CGFloat = 0
    var activeIndex: Int? = nil
    var onSelect: ((Comment) -> Void)?
    var onResolve: ((Comment) -> Void)?
    var onReply: ((Comment) -> Void)?
    var onCommit: ((Comment, String) -> Void)?
    private var pendingEdit: (range: NSRange, initial: String?)?

    init(textView: EditorTextView) { self.textView = textView }

    /// Asks that the card for the comment at `range` open for editing on the next layout.
    func editSoon(range: NSRange, initial: String? = nil) { pendingEdit = (range, initial) }

    func update(comments: [Comment]) {
        guard enabled else { clear(); return }
        // Reuse cards by position so an editing card survives a restyle.
        var reusable = cards
        var next: [CommentCard] = []
        for c in comments {
            // Exact position first, then same author and text nearest by position (text before it may have shifted).
            var idx = reusable.firstIndex { $0.comment.range.location == c.range.location }
            if idx == nil {
                let candidates = reusable.enumerated().filter { $0.element.comment.author == c.author && $0.element.comment.text == c.text }
                idx = candidates.min { abs($0.element.comment.range.location - c.range.location) < abs($1.element.comment.range.location - c.range.location) }?.offset
            }
            if let i = idx {
                let card = reusable.remove(at: i)
                card.apply(c)
                next.append(card)
            } else {
                let card = CommentCard(comment: c)
                wire(card)
                textView.addSubview(card)
                card.alphaValue = 0
                card.layer?.transform = CATransform3DMakeScale(0.98, 0.98, 1)
                NSAnimationContext.runAnimationGroup { ctx in ctx.duration = 0.1; card.animator().alphaValue = 1 }
                card.layer?.transform = CATransform3DIdentity
                next.append(card)
            }
        }
        for r in reusable { r.dropSilently(); r.removeFromSuperview() }
        cards = next
        layout()
        if let p = pendingEdit, let card = cards.first(where: { abs($0.comment.range.location - p.range.location) < 4 }) {
            pendingEdit = nil
            card.beginEditing(initial: p.initial)
        }
    }

    private func wire(_ card: CommentCard) {
        card.onSelect = { [weak self, weak card] in if let c = card { self?.onSelect?(c.comment) } }
        card.onResolve = { [weak self, weak card] in if let c = card { self?.onResolve?(c.comment) } }
        card.onReply = { [weak self, weak card] in if let c = card { self?.onReply?(c.comment) } }
        card.onCommit = { [weak self, weak card] text in if let c = card { self?.onCommit?(c.comment, text) } }
        card.onCancel = { [weak self, weak card] in
            guard let c = card else { return }
            if c.comment.text.isEmpty { self?.onResolve?(c.comment) } else { c.apply(c.comment) }
        }
    }

    func clear() {
        for c in cards { c.removeFromSuperview() }
        cards.removeAll()
    }

    /// Positions cards against the first line of their anchor; overlapping cards push down.
    func layout() {
        guard enabled, !cards.isEmpty, let tlm = textView.textLayoutManager, let tcs = textView.textContentStorage else { return }
        let origin = textView.textContainerOrigin
        let docStart = tcs.documentRange.location
        let visible = textView.visibleRect.insetBy(dx: 0, dy: -textView.visibleRect.height)
        // Only anchors near the viewport get positioned. Laying out a far anchor would force TextKit to lay out everything before it.
        var near = 0..<Int.max
        if let vr = tlm.textViewportLayoutController.viewportRange {
            let a = tcs.offset(from: docStart, to: vr.location), b = tcs.offset(from: docStart, to: vr.endLocation)
            near = max(0, a - 12_000)..<(b + 12_000)
        }
        var lastBottom: CGFloat = -.greatestFiniteMagnitude
        for (i, card) in cards.enumerated() {
            let anchor = card.comment.anchorRange ?? card.comment.range
            guard near.contains(anchor.location), let loc = tcs.location(docStart, offsetBy: anchor.location) else { card.isHidden = true; continue }
            var y: CGFloat? = nil
            tlm.enumerateTextLayoutFragments(from: loc, options: [.ensuresLayout]) { f in
                // Line fragment containing the anchor start, not just the paragraph.
                let inFrag = anchor.location - tcs.offset(from: docStart, to: f.rangeInElement.location)
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
            card.isActive = (i == activeIndex)
            lastBottom = top + card.frame.height
        }
    }

    /// Connector hairlines, drawn by the text view's background pass.
    func drawConnectors(colRight: CGFloat) {
        guard enabled else { return }
        for card in cards where !card.isHidden {
            let y = card.frame.minY + 10
            let r = NSRect(x: colRight + 6, y: y, width: max(0, x - colRight - 10), height: 1)
            (card.isActive ? Palette.accent.withAlphaComponent(0.5) : Palette.fgFaint).setFill()
            r.fill()
        }
    }
}
