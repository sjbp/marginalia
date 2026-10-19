import AppKit
import MarginaliaCore

/// Per-character flags painted from inline spans. One UInt32 per UTF-16 unit.
struct Flag {
    static let strong: UInt32 = 1 << 0
    static let emphasis: UInt32 = 1 << 1
    static let code: UInt32 = 1 << 2
    static let strike: UInt32 = 1 << 3
    static let linkText: UInt32 = 1 << 4
    static let linkURL: UInt32 = 1 << 5
    static let marker: UInt32 = 1 << 6
    static let autolink: UInt32 = 1 << 7
    static let imageAlt: UInt32 = 1 << 8
    static let html: UInt32 = 1 << 9
    static let footnoteRef: UInt32 = 1 << 10
    static let criticHighlight: UInt32 = 1 << 11
    static let criticComment: UInt32 = 1 << 12
    static let criticAuthor: UInt32 = 1 << 13
    static let criticAdd: UInt32 = 1 << 14
    static let criticDel: UInt32 = 1 << 15
    static let criticSubstOld: UInt32 = 1 << 16
    static let criticSubstNew: UInt32 = 1 << 17
    static let criticMarker: UInt32 = 1 << 18
    static let prefix: UInt32 = 1 << 19

    static func of(_ k: InlineKind) -> UInt32 {
        switch k {
        case .strong: return strong
        case .emphasis: return emphasis
        case .code: return code
        case .strike: return strike
        case .linkText: return linkText
        case .linkURL: return linkURL
        case .marker: return marker
        case .autolink: return autolink
        case .imageAlt: return imageAlt
        case .html: return html
        case .footnoteRef: return footnoteRef
        case .criticHighlight: return criticHighlight
        case .criticComment: return criticComment
        case .criticAuthor: return criticAuthor
        case .criticAdd: return criticAdd
        case .criticDel: return criticDel
        case .criticSubstOld: return criticSubstOld
        case .criticSubstNew: return criticSubstNew
        case .criticMarker: return criticMarker
        }
    }
    /// Characters that disappear in reading mode.
    static let hiddenInReading: UInt32 = marker | linkURL | criticMarker | prefix
}

struct Metrics {
    let theme: ThemeSpec
    let bodySize: CGFloat
    /// Left edge of the column inside the text container (the container spans the window).
    var columnLeft: CGFloat = 0
    var unit: CGFloat { (bodySize * theme.leading).rounded() }      // one line of body text
    var textEdge: CGFloat { (bodySize * 4.2).rounded() }             // gutter width for hanging markers
    var measure: CGFloat { (bodySize * 34).rounded() }               // ~68ch
    var columnWidth: CGFloat { textEdge + measure }
    var listIndent: CGFloat { (bodySize * 1.6).rounded() }
    var quoteIndent: CGFloat { (bodySize * 1.4).rounded() }
    func headingSize(_ level: Int) -> CGFloat {
        switch level { case 1: return (bodySize * 1.75).rounded(); case 2: return (bodySize * 1.4).rounded(); case 3: return (bodySize * 1.15).rounded(); default: return bodySize }
    }
}

final class Styler {
    var theme: ThemeSpec
    var bodySize: CGFloat
    var columnLeft: CGFloat = 0 { didSet { if columnLeft != oldValue { paragraphCache.removeAll() } } }
    var isDark = false
    private var paragraphCache: [String: NSParagraphStyle] = [:]
    private var attrCache: [UInt64: [NSAttributedString.Key: Any]] = [:]

    init(theme: ThemeSpec, bodySize: CGFloat) { self.theme = theme; self.bodySize = bodySize }

    var metrics: Metrics { Metrics(theme: theme, bodySize: bodySize, columnLeft: columnLeft) }

    func invalidate() { paragraphCache.removeAll(); attrCache.removeAll() }

    // MARK: Fonts

    private var weightBoost: CGFloat { isDark ? theme.darkWeightBoost : 0 }

    func bodyFont(weight: CGFloat = 400, italic: Bool = false, size: CGFloat? = nil) -> NSFont {
        let s = size ?? bodySize
        let slant: CGFloat? = { if case .slant(let v) = theme.italic { return v } else { return nil } }()
        return FontCache.font(FontKey(family: theme.bodyFamily, size: s, weight: min(weight + weightBoost, 900), italic: italic, slant: slant, opsz: theme.hasOpsz, onum: theme.onum))
    }

    func monoFont(weight: CGFloat = 400, italic: Bool = false, size: CGFloat? = nil) -> NSFont {
        let s = size ?? (bodySize * theme.monoScale).rounded(.toNearestOrEven)
        return FontCache.font(FontKey(family: theme.monoFamily, size: s, weight: min(weight + weightBoost * 0.5, 800), italic: italic, slant: nil, opsz: false, onum: false))
    }

    func headingFont(_ level: Int, italic: Bool = false) -> NSFont {
        let m = metrics
        let w: CGFloat = level <= 3 ? 700 : 600
        return bodyFont(weight: w, italic: italic, size: m.headingSize(level))
    }

    var baseAttributes: [NSAttributedString.Key: Any] {
        [.font: bodyFont(), .foregroundColor: Palette.fg, .paragraphStyle: paragraphStyle(kind: .text, level: 0, listDepth: 0, quoteDepth: 0, prefixWidth: 0, afterHeading: false)]
    }

    // MARK: Paragraph styles

    func paragraphStyle(kind: LineKind, level: Int, listDepth: Int, quoteDepth: Int, prefixWidth: CGFloat, afterHeading: Bool) -> NSParagraphStyle {
        let key = "\(kind)|\(level)|\(listDepth)|\(quoteDepth)|\(Int(prefixWidth * 4))|\(afterHeading)"
        if let p = paragraphCache[key] { return p }
        let m = metrics
        let ps = NSMutableParagraphStyle()
        ps.lineBreakMode = .byWordWrapping
        ps.hyphenationFactor = 0
        var lh = m.unit
        var before: CGFloat = 0
        switch kind {
        case .heading:
            let size = m.headingSize(level)
            lh = (size * 1.2).rounded()
            switch level { case 1: before = m.unit * 1.0; case 2: before = m.unit * 0.6; case 3: before = m.unit * 0.3; default: before = m.unit * 0.1 }
        case .blank:
            lh = afterHeading ? (m.unit * 0.3).rounded() : (m.unit * 0.55).rounded()
        case .code, .codeFence, .table, .tableSeparator, .frontmatter:
            lh = (m.unit * 0.92).rounded()
        default: break
        }
        ps.minimumLineHeight = lh
        ps.maximumLineHeight = lh
        ps.paragraphSpacingBefore = before
        let head = m.columnLeft + m.textEdge + CGFloat(max(0, listDepth - 1)) * m.listIndent + CGFloat(quoteDepth) * m.quoteIndent
        ps.headIndent = head
        ps.firstLineHeadIndent = max(0, head - prefixWidth - (quoteDepth > 0 && prefixWidth > 0 ? 14 : 0))
        switch kind {
        case .code, .codeFence: ps.lineBreakMode = .byCharWrapping   // full container width
        case .table, .tableSeparator: break                           // full container width
        default: ps.tailIndent = m.columnLeft + m.columnWidth         // body stays on the measure
        }
        paragraphCache[key] = ps
        return ps
    }

    // MARK: Flags

    func paintFlags(model: DocumentModel, length: Int) -> [UInt32] {
        var flags = [UInt32](repeating: 0, count: length + 1)
        for s in model.inlines {
            let f = Flag.of(s.kind)
            let lo = max(0, s.range.location), hi = min(length, s.range.location + s.range.length)
            if lo < hi { for i in lo..<hi { flags[i] |= f } }
        }
        for line in model.lines where line.prefixLength > 0 {
            let lo = line.range.location, hi = min(length, lo + line.prefixLength)
            if lo < hi { for i in lo..<hi { flags[i] |= Flag.prefix } }
        }
        return flags
    }

    // MARK: Apply

    /// Styles the given line indices (or all) in place. Expects `flags` from `paintFlags` for the same text.
    func apply(model: DocumentModel, flags: [UInt32], to storage: NSTextStorage, lines: Range<Int>? = nil, activeLine: Int? = nil) {
        let text = storage.string as NSString
        let length = storage.length
        let range = lines ?? 0..<model.lines.count
        guard !model.lines.isEmpty, range.lowerBound < model.lines.count else { return }
        let r = range.clamped(to: 0..<model.lines.count)
        let m = metrics
        storage.beginEditing()
        let first = model.lines[r.lowerBound].range.location
        let lastLine = model.lines[r.upperBound - 1]
        let last = min(length, lastLine.range.location + lastLine.range.length + 1)
        if first < last { storage.setAttributes(baseAttributes, range: NSRange(location: first, length: last - first)) }

        for li in r {
            let line = model.lines[li]
            let lr = line.range
            guard lr.location <= length else { break }
            let prefixFont = fontFor(line: line, flags: Flag.prefix | Flag.marker)
            let prefix = line.prefixLength > 0 && lr.location + line.prefixLength <= length ? text.substring(with: NSRange(location: lr.location, length: line.prefixLength)) : ""
            let pw = prefix.isEmpty ? 0 : FontCache.width(of: prefix, in: prefixFont)
            let ps = paragraphStyle(kind: line.kind, level: line.headingLevel, listDepth: line.listDepth, quoteDepth: line.quoteDepth, prefixWidth: pw, afterHeading: line.afterHeading)
            let paraRange = NSRange(location: lr.location, length: min(lr.length + 1, length - lr.location))
            storage.addAttribute(.paragraphStyle, value: ps, range: paraRange)
            guard lr.length > 0 else { continue }
            let active = li == activeLine
            var runStart = lr.location
            var f = flags[runStart]
            var i = runStart + 1
            let end = lr.location + lr.length
            while i <= end {
                let nf = i < end ? flags[i] : ~f
                if nf != f {
                    storage.addAttributes(attributes(line: line, flags: f, active: active), range: NSRange(location: runStart, length: i - runStart))
                    runStart = i; f = nf
                }
                i += 1
            }
        }
        // Table pipe alignment via kern on the last character of each short cell.
        let mono = monoFont()
        let adv = FontCache.advance(of: mono)
        for t in model.tables where t.lineRange.overlaps(r) {
            for tl in t.lines where r.contains(tl.line) {
                for p in tl.pads where p.offset < length {
                    storage.addAttribute(.kern, value: adv * CGFloat(p.chars), range: NSRange(location: p.offset, length: 1))
                }
            }
        }
        _ = m
        storage.endEditing()
    }

    private func fontFor(line: LineInfo, flags: UInt32) -> NSFont {
        attributes(line: line, flags: flags, active: false)[.font] as! NSFont
    }

    /// Attributes for a run. Cached by (line kind, heading level, flags, active).
    func attributes(line: LineInfo, flags f: UInt32, active: Bool) -> [NSAttributedString.Key: Any] {
        let kindCode: UInt64 = { switch line.kind {
            case .blank: return 0; case .text: return 1; case .heading: return 2; case .listItem: return 3; case .listContinuation: return 4
            case .code: return 5; case .codeFence: return 6; case .table: return 7; case .tableSeparator: return 8; case .rule: return 9
            case .frontmatter: return 10; case .html: return 11; case .footnoteDef: return 12; case .linkDef: return 13 } }()
        let key = kindCode | UInt64(line.headingLevel) << 8 | UInt64(f) << 16 | (active ? 1 : 0) << 48
        if let a = attrCache[key] { return a }

        var a: [NSAttributedString.Key: Any] = [:]
        let isMono: Bool
        switch line.kind {
        case .code, .codeFence, .table, .tableSeparator, .frontmatter, .html, .linkDef: isMono = true
        default: isMono = false
        }
        let bold = f & Flag.strong != 0 || f & Flag.criticAuthor != 0
        let italic = f & Flag.emphasis != 0
        var color: NSColor = Palette.fg

        if line.kind == .heading {
            a[.font] = headingFont(line.headingLevel, italic: italic)
            if line.headingLevel >= 5 { color = Palette.fgMuted }
        } else if isMono || f & Flag.code != 0 || f & Flag.html != 0 {
            a[.font] = monoFont(weight: bold ? 700 : 400, italic: italic)
            if f & Flag.code != 0 && !isMono { a[.backgroundColor] = Palette.inlineCodeFill }
            if line.kind == .codeFence || line.kind == .tableSeparator || line.kind == .frontmatter || f & Flag.html != 0 { color = Palette.fgMuted }
        } else if f & Flag.linkURL != 0 {
            a[.font] = bodyFont(weight: 400, italic: false, size: (bodySize * 0.85).rounded())
            color = Palette.fgMuted
        } else if f & Flag.criticComment != 0 || f & Flag.criticAuthor != 0 {
            a[.font] = bodyFont(weight: bold ? 600 : 400, italic: italic, size: (bodySize * 0.9).rounded())
            color = Palette.commentText
        } else {
            a[.font] = bodyFont(weight: bold ? 700 : 400, italic: italic)
        }

        if f & Flag.strike != 0 || f & Flag.criticDel != 0 || f & Flag.criticSubstOld != 0 {
            a[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            a[.strikethroughColor] = Palette.fgMuted
        }
        if f & Flag.linkText != 0 || f & Flag.autolink != 0 {
            color = Palette.accent
            a[.underlineStyle] = NSUnderlineStyle.single.rawValue
            a[.underlineColor] = Palette.accent.withAlphaComponent(0.35)
        }
        if f & Flag.footnoteRef != 0 { color = Palette.accent; a[.baselineOffset] = bodySize * 0.25; a[.font] = bodyFont(weight: 500, size: (bodySize * 0.75).rounded()) }
        if f & Flag.imageAlt != 0 { color = Palette.fgMuted }
        if f & Flag.criticHighlight != 0 { a[.backgroundColor] = Palette.commentFill }
        if f & Flag.criticAdd != 0 || f & Flag.criticSubstNew != 0 { color = Palette.added }
        if f & Flag.criticDel != 0 || f & Flag.criticSubstOld != 0 { color = Palette.removed }
        if f & Flag.criticMarker != 0 { color = Palette.commentText.withAlphaComponent(active ? 0.9 : 0.5) }
        if f & (Flag.marker | Flag.prefix) != 0 && f & Flag.criticMarker == 0 {
            color = active ? Palette.fg.withAlphaComponent(0.75) : Palette.fgMuted
            if line.kind == .heading { a[.font] = headingFont(line.headingLevel) }
        }
        if line.kind == .rule { color = Palette.fgFaint }
        a[.foregroundColor] = color
        attrCache[key] = a
        return a
    }
}
