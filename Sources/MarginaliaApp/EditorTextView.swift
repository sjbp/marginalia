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

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        guard let model, let metrics, let tlm = textLayoutManager, let tcs = textContentStorage else { return }
        let origin = textContainerOrigin
        let viewport = visibleRect
        // Only touch blocks that intersect the viewport; TextKit 2 lays out lazily.
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
        // Code blocks: full-width soft panel from the text edge to the right edge of the column.
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
        // Blockquote rules.
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
        // Thematic breaks: a hairline instead of the dashes' baseline.
        for (li, line) in model.lines.enumerated() where line.kind == .rule {
            guard let f = frame(forLines: li..<(li + 1)) else { continue }
            let r = NSRect(x: colLeft + metrics.textEdge, y: f.midY + origin.y, width: metrics.measure, height: 1)
            Palette.fgFaint.setFill(); r.fill()
        }
        NSGraphicsContext.restoreGraphicsState()
    }
}
