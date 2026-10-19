import AppKit
import MarginaliaCore

/// A GFM table drawn natively: measured columns, wrapped cells, hairlines. Sits on top of the hidden source lines.
final class TableOverlay: NSView {
    struct Cell { let text: NSAttributedString; var height: CGFloat = 0 }
    private var rows: [[Cell]] = []
    private var alignments: [NSTextAlignment] = []
    private var colWidths: [CGFloat] = []
    private var rowHeights: [CGFloat] = []
    let padX: CGFloat = 10, padY: CGFloat = 7

    init(rows: [[NSAttributedString]], alignments: [NSTextAlignment], maxWidth: CGFloat, minWidth: CGFloat) {
        super.init(frame: .zero)
        wantsLayer = false
        self.alignments = alignments
        let cols = rows.map { $0.count }.max() ?? 0
        self.rows = rows.map { r in (0..<cols).map { i in Cell(text: i < r.count ? r[i] : NSAttributedString(string: "")) } }
        // Natural widths, then shrink the widest columns until the table fits.
        var natural = Array(repeating: CGFloat(0), count: cols)
        for r in self.rows { for (i, c) in r.enumerated() { natural[i] = max(natural[i], ceil(c.text.size().width) + 2 * padX) } }
        var widths = natural
        let total = widths.reduce(0, +)
        if total > maxWidth {
            // Columns narrower than their fair share keep their width; the rest share what remains.
            let fair = maxWidth / CGFloat(max(1, cols))
            let fixed = widths.filter { $0 <= fair }.reduce(0, +)
            let flexCount = widths.filter { $0 > fair }.count
            let flexTotal = widths.filter { $0 > fair }.reduce(0, +)
            let remaining = max(0, maxWidth - fixed)
            widths = widths.map { w in w <= fair ? w : max(fair * 0.8, remaining * (w / max(flexTotal, 1))) }
            _ = flexCount
        } else if total < minWidth {
            // keep natural widths; the table simply does not span the column
        }
        colWidths = widths
        rowHeights = self.rows.map { r in
            var h: CGFloat = 0
            for (i, c) in r.enumerated() {
                let rect = c.text.boundingRect(with: NSSize(width: max(10, widths[i] - 2 * padX), height: 10_000), options: [.usesLineFragmentOrigin, .usesFontLeading])
                h = max(h, ceil(rect.height))
            }
            return h + 2 * padY
        }
        frame.size = NSSize(width: widths.reduce(0, +), height: rowHeights.reduce(0, +) + 1)
    }
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        var y: CGFloat = 0
        for (ri, r) in rows.enumerated() {
            var x: CGFloat = 0
            let h = rowHeights[ri]
            for (ci, c) in r.enumerated() {
                let w = colWidths[ci]
                let align = ci < alignments.count ? alignments[ci] : .left
                let ps = NSMutableParagraphStyle(); ps.alignment = align; ps.lineBreakMode = .byWordWrapping
                let ms = NSMutableAttributedString(attributedString: c.text)
                ms.addAttribute(.paragraphStyle, value: ps, range: NSRange(location: 0, length: ms.length))
                ms.draw(with: NSRect(x: x + padX, y: y + padY, width: w - 2 * padX, height: h - 2 * padY), options: [.usesLineFragmentOrigin, .usesFontLeading])
                x += w
            }
            y += h
            let rule = NSRect(x: 0, y: y - 0.5, width: bounds.width, height: ri == 0 ? 1 : 0.5)
            (ri == 0 ? Palette.fgMuted : Palette.fgFaint).setFill()
            rule.fill()
        }
    }
}

/// Builds and positions the native views that replace tables and images in reading mode.
final class ReadingOverlays {
    unowned let textView: EditorTextView
    private(set) var views: [(line: Int, view: NSView)] = []
    static let imageMatch = try! NSRegularExpression(pattern: #"^\s*!\[([^\]]*)\]\(([^)\s]+)(?:\s+"[^"]*")?\)\s*$"#)

    init(textView: EditorTextView) { self.textView = textView }

    func clear() {
        for v in views { v.view.removeFromSuperview() }
        views.removeAll()
    }

    /// Creates the overlay views and returns the height each source line must reserve.
    func rebuild(model: DocumentModel, text: NSString, styler: Styler, baseURL: URL, maxWidth: CGFloat) -> [Int: CGFloat] {
        clear()
        var reserved: [Int: CGFloat] = [:]
        let m = styler.metrics
        for t in model.tables {
            let lines = Array(t.lineRange)
            guard lines.count >= 2 else { continue }
            let header = TableLayout.cells(line: lines[0], map: model.map)
            let aligns = TableLayout.alignments(separatorLine: lines[1], map: model.map).map { a -> NSTextAlignment in
                switch a { case 1: return .center; case 2: return .right; default: return .left }
            }
            var rows: [[NSAttributedString]] = [header.map { styler.renderInline($0, bold: true, baseURL: baseURL) }]
            for li in lines.dropFirst(2) { rows.append(TableLayout.cells(line: li, map: model.map).map { styler.renderInline($0, bold: false, baseURL: baseURL) }) }
            let v = TableOverlay(rows: rows, alignments: aligns, maxWidth: maxWidth, minWidth: m.measure)
            views.append((lines[0], v))
            textView.addSubview(v)
            reserved[lines[0]] = v.frame.height + 12
            for li in lines.dropFirst() { reserved[li] = 1 }
        }
        for (li, line) in model.lines.enumerated() where line.kind == .text || line.kind == .listContinuation {
            let s = text.substring(with: line.range)
            guard let mm = ReadingOverlays.imageMatch.firstMatch(in: s, range: NSRange(location: 0, length: (s as NSString).length)) else { continue }
            let src = (s as NSString).substring(with: mm.range(at: 2))
            let url = src.hasPrefix("http") ? URL(string: src) : URL(fileURLWithPath: src, relativeTo: baseURL)
            guard let url, !src.hasPrefix("http"), let img = NSImage(contentsOf: url), img.size.width > 0 else { continue }
            let w = min(m.measure, img.size.width)
            let h = (img.size.height * (w / img.size.width)).rounded()
            let iv = NSImageView(frame: NSRect(x: 0, y: 0, width: w, height: h))
            iv.image = img
            iv.imageScaling = .scaleProportionallyUpOrDown
            iv.wantsLayer = true
            iv.layer?.cornerRadius = 4
            iv.layer?.masksToBounds = true
            views.append((li, iv))
            textView.addSubview(iv)
            reserved[li] = h + 12
        }
        return reserved
    }

    /// Positions overlays on their reserved lines using the same fragment geometry the text is drawn with.
    func layout(model: DocumentModel?, metrics: Metrics, activeLines: Range<Int> = 0..<0) {
        guard let model, !views.isEmpty, let tlm = textView.textLayoutManager, let tcs = textView.textContentStorage else { return }
        let origin = textView.textContainerOrigin
        let docStart = tcs.documentRange.location
        var near = 0..<Int.max
        if let vr = tlm.textViewportLayoutController.viewportRange {
            let a = tcs.offset(from: docStart, to: vr.location), b = tcs.offset(from: docStart, to: vr.endLocation)
            near = max(0, a - 12_000)..<(b + 12_000)
        }
        for (li, v) in views {
            if activeLines.contains(li) { v.isHidden = true; continue }   // the caret is in this block: source is showing
            guard li < model.lines.count, near.contains(model.lines[li].range.location), let loc = tcs.location(docStart, offsetBy: model.lines[li].range.location) else { v.isHidden = true; continue }
            var y: CGFloat? = nil
            tlm.enumerateTextLayoutFragments(from: loc, options: [.ensuresLayout]) { f in y = f.layoutFragmentFrame.minY; return false }
            guard let yy = y else { v.isHidden = true; continue }
            v.frame.origin = NSPoint(x: origin.x + metrics.columnLeft + metrics.textEdge, y: yy + origin.y + 6)
            v.isHidden = false
        }
    }
}
