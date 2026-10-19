import AppKit
import MarginaliaCore

final class EditorTextView: NSTextView {
    /// Set by the window controller after each parse.
    var model: DocumentModel?
    var metrics: Metrics?

    override var isOpaque: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if ProcessClock.firstPaintMs < 0 { ProcessClock.firstPaintMs = ProcessClock.msSinceProcessStart() }
    }

    // MARK: - Smart editing

    struct LineContext { let line: String; let lineStart: Int; let caretInLine: Int; let info: LineInfo; let lineRange: NSRange }

    /// Fresh view of the caret's line. Re-parses when the cached model is stale.
    func lineContext() -> LineContext? {
        guard let storage = textStorage else { return nil }
        let ns = storage.string as NSString
        let sel = selectedRange()
        var m = model
        if m == nil || m!.map.utf16Count != ns.length { m = MarkdownParser.parse(storage.string); model = m }
        guard let model = m else { return nil }
        let li = model.map.lineIndex(forUTF16: min(sel.location, ns.length))
        guard li < model.lines.count else { return nil }
        let info = model.lines[li]
        let r = info.range
        return LineContext(line: ns.substring(with: r), lineStart: r.location, caretInLine: sel.location - r.location, info: info, lineRange: r)
    }

    func perform(_ e: SmartEdit.Edit, select: NSRange? = nil) {
        guard shouldChangeText(in: e.range, replacementString: e.replacement) else { return }
        textStorage?.replaceCharacters(in: e.range, with: e.replacement)
        didChangeText()
        setSelectedRange(select ?? NSRange(location: e.caret, length: 0))
    }

    override func insertNewline(_ sender: Any?) {
        if NSApp.currentEvent?.modifierFlags.contains(.shift) == true { insertText("\n", replacementRange: selectedRange()); return }
        if selectedRange().length == 0, let c = lineContext(),
           let e = SmartEdit.newline(line: c.line, lineStart: c.lineStart, caretInLine: c.caretInLine, info: c.info) {
            perform(e); return
        }
        insertText("\n", replacementRange: selectedRange())
    }

    override func insertLineBreak(_ sender: Any?) { insertText("\n", replacementRange: selectedRange()) }
    override func insertNewlineIgnoringFieldEditor(_ sender: Any?) { insertNewline(sender) }

    override func insertTab(_ sender: Any?) {
        if let c = lineContext(), c.info.listDepth > 0 || c.info.kind == .listItem,
           let e = SmartEdit.shiftIndent(line: c.line, lineStart: c.lineStart, caret: selectedRange().location, outdent: false) { perform(e); return }
        super.insertTab(sender)
    }

    override func insertBacktab(_ sender: Any?) {
        if let c = lineContext(), let e = SmartEdit.shiftIndent(line: c.line, lineStart: c.lineStart, caret: selectedRange().location, outdent: true) { perform(e) }
    }

    @objc func toggleBold(_ sender: Any?) { wrap("**") }
    @objc func toggleItalic(_ sender: Any?) { wrap("_") }
    @objc func toggleCodeSpan(_ sender: Any?) { wrap("`") }
    @objc func toggleStrike(_ sender: Any?) { wrap("~~") }

    private func wrap(_ d: String) {
        guard let s = textStorage?.string as NSString? else { return }
        perform(SmartEdit.toggleWrap(text: s, selection: selectedRange(), delimiter: d))
    }

    @objc func insertLink(_ sender: Any?) {
        guard let s = textStorage?.string as NSString? else { return }
        var clip: String? = nil
        if let p = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
           p.hasPrefix("http://") || p.hasPrefix("https://"), !p.contains(" ") { clip = p }
        perform(SmartEdit.link(text: s, selection: selectedRange(), clipboardURL: clip))
    }

    @objc func headingUp(_ sender: Any?) { shiftHeading(up: true) }
    @objc func headingDown(_ sender: Any?) { shiftHeading(up: false) }
    private func shiftHeading(up: Bool) {
        guard let c = lineContext(), let e = SmartEdit.shiftHeading(line: c.line, lineStart: c.lineStart, caret: selectedRange().location, up: up) else { return }
        perform(e)
    }

    @objc func toggleTask(_ sender: Any?) {
        guard let c = lineContext() else { return }
        perform(SmartEdit.toggleTask(line: c.line, lineStart: c.lineStart, caret: selectedRange().location))
    }

    @objc func moveLineUp(_ sender: Any?) { moveLines(up: true) }
    @objc func moveLineDown(_ sender: Any?) { moveLines(up: false) }
    private func moveLines(up: Bool) {
        guard let s = textStorage?.string as NSString?, let (e, sel) = SmartEdit.moveLines(text: s, selection: selectedRange(), up: up) else { return }
        perform(e, select: sel)
    }

    // MARK: - Background drawing

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        guard let model, let metrics, let tlm = textLayoutManager, let tcs = textContentStorage else { return }
        let origin = textContainerOrigin
        let viewport = visibleRect
        guard let vr = tlm.textViewportLayoutController.viewportRange else { return }
        let docStart = tcs.documentRange.location
        let vlo = tcs.offset(from: docStart, to: vr.location), vhi = tcs.offset(from: docStart, to: vr.endLocation)

        func frame(forLines lines: Range<Int>) -> NSRect? {
            guard lines.lowerBound < model.lines.count else { return nil }
            let a = model.lines[lines.lowerBound].range.location
            let lastL = model.lines[min(lines.upperBound, model.lines.count) - 1]
            let b = lastL.range.location + lastL.range.length
            guard b > vlo, a < vhi else { return nil }
            guard let s = tcs.location(docStart, offsetBy: max(a, vlo)), let e = tcs.location(docStart, offsetBy: min(b, vhi)), let tr = NSTextRange(location: s, end: e) else { return nil }
            var union: NSRect? = nil
            tlm.enumerateTextSegments(in: tr, type: .standard, options: [.rangeNotRequired]) { _, f, _, _ in
                union = union.map { $0.union(f) } ?? f
                return true
            }
            return union
        }

        NSGraphicsContext.saveGraphicsState()
        let colLeft = origin.x + metrics.columnLeft
        for cb in model.codeBlocks {
            guard let f = frame(forLines: cb.lineRange) else { continue }
            let x = colLeft + metrics.textEdge - 12
            let rightEdge = max(colLeft + metrics.columnWidth, f.maxX + origin.x) + 12
            let r = NSRect(x: x, y: f.minY + origin.y - 4, width: max(0, rightEdge - x), height: f.height + 8)
            guard r.intersects(viewport) else { continue }
            Palette.codeFill.setFill()
            NSBezierPath(roundedRect: r, xRadius: 6, yRadius: 6).fill()
        }
        var i = 0
        while i < model.lines.count {
            let d = model.lines[i].quoteDepth
            if d > 0 {
                var j = i
                while j < model.lines.count, model.lines[j].quoteDepth == d { j += 1 }
                if let f = frame(forLines: i..<j) {
                    let listOff = CGFloat(max(0, model.lines[i].listDepth - 1)) * metrics.listIndent
                    for q in 0..<d {
                        let x = colLeft + metrics.textEdge + listOff + CGFloat(q) * metrics.quoteIndent + metrics.quoteIndent - 9
                        let r = NSRect(x: x, y: f.minY + origin.y + 2, width: 2, height: f.height - 4)
                        if r.intersects(viewport) { Palette.quoteRule.setFill(); NSBezierPath(roundedRect: r, xRadius: 1, yRadius: 1).fill() }
                    }
                }
                i = j
            } else { i += 1 }
        }
        for (li, line) in model.lines.enumerated() where line.kind == .rule {
            guard let f = frame(forLines: li..<(li + 1)) else { continue }
            let r = NSRect(x: colLeft + metrics.textEdge, y: f.midY + origin.y, width: metrics.measure, height: 1)
            Palette.fgFaint.setFill(); r.fill()
        }
        NSGraphicsContext.restoreGraphicsState()
    }
}
