import AppKit
import MarginaliaCore

final class EditorTextView: NSTextView {
    /// Set by the window controller after each parse.
    var model: DocumentModel?
    var metrics: Metrics?
    weak var controller: DocumentWindowController?
    var margin: CommentMargin?
    var overlays: ReadingOverlays?
    var isReading = false
    /// Flags for the current text, for stripping hidden runs when copying in reading mode.
    var flagsProvider: (() -> [UInt32])?

    override func copy(_ sender: Any?) {
        guard isReading, let flags = flagsProvider?() else { super.copy(sender); return }
        let sel = selectedRange()
        guard sel.length > 0 else { return }
        let ns = string as NSString
        var out = ""
        var i = sel.location
        let end = min(sel.location + sel.length, ns.length, flags.count)
        while i < end {
            if flags[i] & (Flag.hiddenInReading | Flag.criticComment | Flag.criticAuthor) == 0 { out.append(Character(UnicodeScalar(ns.character(at: i)) ?? " ")) }
            i += 1
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(out, forType: .string)
    }

    override func cancelOperation(_ sender: Any?) {
        if let c = controller, !c.changeMarks.isEmpty { c.clearChangeMarks(); return }
        super.cancelOperation(sender)
    }

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
        // Outside an event (script mode, timers), make sure a group is open for the undo registration.
        var opened = false
        if let um = undoManager, !um.groupsByEvent, um.groupingLevel == 0 { um.beginUndoGrouping(); opened = true }
        defer { if opened { undoManager?.endUndoGrouping() } }
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

    /// Reading mode: typographic bullets, numbers, and task boxes in the gutter, replacing the hidden source markers.
    private func drawReadingMarkers(model: DocumentModel, metrics: Metrics, origin: NSPoint, colLeft: CGFloat, viewport: NSRect, frame: (Range<Int>) -> NSRect?) {
        let ns = string as NSString
        let unit = metrics.unit
        let font = controller?.styler.bodyFont() ?? NSFont.systemFont(ofSize: metrics.bodySize)
        let ps = NSMutableParagraphStyle(); ps.minimumLineHeight = unit; ps.maximumLineHeight = unit; ps.alignment = .right
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: Palette.fgMuted, .paragraphStyle: ps]
        for (li, line) in model.lines.enumerated() where line.kind == .listItem {
            guard let f = frame(li..<(li + 1)) else { continue }
            let head = colLeft + metrics.textEdge + CGFloat(max(0, line.listDepth - 1)) * metrics.listIndent + CGFloat(line.quoteDepth) * metrics.quoteIndent
            let top = f.minY + origin.y
            guard NSRect(x: head - 40, y: top, width: 40, height: unit).intersects(viewport) else { continue }
            if line.checkbox != 0 {
                let size: CGFloat = (metrics.bodySize * 0.8).rounded()
                let box = NSRect(x: head - size - 10, y: top + (unit - size) / 2 - 1, width: size, height: size)
                let path = NSBezierPath(roundedRect: box, xRadius: 3.5, yRadius: 3.5)
                if line.checkbox == 2 {
                    Palette.accent.withAlphaComponent(0.9).setFill(); path.fill()
                    let check = NSBezierPath()
                    check.move(to: NSPoint(x: box.minX + size * 0.26, y: box.minY + size * 0.52))
                    check.line(to: NSPoint(x: box.minX + size * 0.44, y: box.minY + size * 0.70))
                    check.line(to: NSPoint(x: box.minX + size * 0.76, y: box.minY + size * 0.32))
                    check.lineWidth = 1.8; check.lineCapStyle = .round; check.lineJoinStyle = .round
                    NSColor.white.setStroke(); check.stroke()
                } else {
                    Palette.fgMuted.withAlphaComponent(0.8).setStroke(); path.lineWidth = 1.2; path.stroke()
                }
            } else if line.ordered {
                let prefix = ns.substring(with: NSRange(location: line.range.location, length: line.prefixLength)).trimmingCharacters(in: .whitespaces)
                NSAttributedString(string: prefix, attributes: attrs).draw(in: NSRect(x: head - 80, y: top, width: 80 - 8, height: unit))
            } else {
                let dot = NSRect(x: head - 14, y: top + unit / 2 - 2.5, width: 5, height: 5)
                Palette.fgMuted.setFill(); NSBezierPath(ovalIn: dot).fill()
            }
        }
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
        margin?.drawConnectors(colRight: colLeft + metrics.columnWidth)
        if isReading { drawReadingMarkers(model: model, metrics: metrics, origin: origin, colLeft: colLeft, viewport: viewport, frame: frame) }
        // Change bars from external reloads, fading over the last two seconds of their life.
        if let marks = controller?.changeMarks, !marks.isEmpty {
            let now = Date()
            let barX = colLeft + 6
            for mk in marks {
                let age = now.timeIntervalSince(mk.at)
                let life = DocumentWindowController.markLifetime
                let alpha = age < life - 2 ? 1 : max(0, (life - age) / 2)
                switch mk.kind {
                case .added, .conflict:
                    guard mk.line < model.lines.count, let f = frame(forLines: mk.line..<(mk.line + 1)) else { continue }
                    let r = NSRect(x: barX, y: f.minY + origin.y + 1, width: 3, height: f.height - 2)
                    guard r.intersects(viewport) else { continue }
                    (mk.kind == .conflict ? Palette.removed : Palette.added).withAlphaComponent(alpha).setFill()
                    NSBezierPath(roundedRect: r, xRadius: 1.5, yRadius: 1.5).fill()
                case .removed:
                    let y: CGFloat
                    if mk.line < model.lines.count, let f = frame(forLines: mk.line..<(mk.line + 1)) { y = f.minY + origin.y - 1 }
                    else if model.lines.count > 0, let f = frame(forLines: (model.lines.count - 1)..<model.lines.count) { y = f.maxY + origin.y }
                    else { continue }
                    let r = NSRect(x: barX, y: y, width: 22, height: 2)
                    guard r.intersects(viewport) else { continue }
                    Palette.removed.withAlphaComponent(alpha).setFill()
                    r.fill()
                }
            }
        }
        NSGraphicsContext.restoreGraphicsState()
    }
}
