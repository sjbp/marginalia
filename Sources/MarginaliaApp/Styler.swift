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

enum StyleMode { case source, rendered }

struct Metrics {
    let theme: ThemeSpec
    let bodySize: CGFloat
    /// Left edge of the column inside the text container (the container spans the window).
    var columnLeft: CGFloat = 0
    var leading: CGFloat = 1.55
    var unit: CGFloat { (bodySize * leading).rounded() }           // one line of body text
    var textEdge: CGFloat { (bodySize * 4.2).rounded() }             // gutter width for hanging markers
    var measure: CGFloat { (bodySize * 34).rounded() }               // ~68ch
    var columnWidth: CGFloat { textEdge + measure }
    var listIndent: CGFloat { (bodySize * 1.6).rounded() }
    var quoteIndent: CGFloat { (bodySize * 1.4).rounded() }
    func headingSize(_ level: Int) -> CGFloat {
        switch level { case 1: return (bodySize * 2.1).rounded(); case 2: return (bodySize * 1.55).rounded(); case 3: return (bodySize * 1.2).rounded(); default: return bodySize }
    }
    /// Negative tracking tightens display sizes the way Geist and Google Sans Flex are meant to be set.
    func headingTracking(_ level: Int) -> CGFloat {
        switch level { case 1: return -0.025; case 2: return -0.015; case 3: return -0.005; default: return 0 }
    }
}

final class Styler {
    var theme: ThemeSpec
    var bodySize: CGFloat
    var columnLeft: CGFloat = 0 { didSet { if columnLeft != oldValue { paragraphCache.removeAll() } } }
    var mode: StyleMode = .rendered { didSet { if mode != oldValue { invalidate() } } }
    /// Rendered mode: lines whose Markdown is shown because the caret is in them.
    var activeLines: Range<Int> = 0..<0
    /// Reading mode: line index → height to reserve for an overlay (table, image).
    var reservedHeights: [Int: CGFloat] = [:]
    var baseURL: URL? = nil
    var isDark = false
    var effectiveBodySize: CGFloat { bodySize }
    private var paragraphCache: [String: NSParagraphStyle] = [:]
    private var attrCache: [UInt64: [NSAttributedString.Key: Any]] = [:]

    init(theme: ThemeSpec, bodySize: CGFloat) { self.theme = theme; self.bodySize = bodySize }

    var metrics: Metrics { Metrics(theme: theme, bodySize: effectiveBodySize, columnLeft: columnLeft, leading: theme.leading) }

    func invalidate() { paragraphCache.removeAll(); attrCache.removeAll(); inlineCache.removeAll() }

    // MARK: Fonts

    private var weightBoost: CGFloat { isDark ? theme.darkWeightBoost : 0 }

    func bodyFont(weight: CGFloat = 400, italic: Bool = false, size: CGFloat? = nil) -> NSFont {
        let s = size ?? effectiveBodySize
        let slant: CGFloat? = { if case .slant(let v) = theme.italic { return v } else { return nil } }()
        return FontCache.font(FontKey(family: theme.bodyFamily, size: s, weight: min(weight + weightBoost, 900), italic: italic, slant: slant, opsz: theme.hasOpsz, onum: theme.onum))
    }

    func monoFont(weight: CGFloat = 400, italic: Bool = false, size: CGFloat? = nil) -> NSFont {
        let s = size ?? (effectiveBodySize * theme.monoScale).rounded(.toNearestOrEven)
        return FontCache.font(FontKey(family: theme.monoFamily, size: s, weight: min(weight + weightBoost * 0.5, 800), italic: italic, slant: nil, opsz: false, onum: false))
    }

    func headingFont(_ level: Int, italic: Bool = false) -> NSFont {
        let m = metrics
        return bodyFont(weight: 600, italic: italic, size: m.headingSize(level))
    }

    var baseAttributes: [NSAttributedString.Key: Any] {
        [.font: bodyFont(), .foregroundColor: Palette.fg, .paragraphStyle: paragraphStyle(kind: .text, level: 0, listDepth: 0, quoteDepth: 0, prefixWidth: 0, afterHeading: false)]
    }

    // MARK: Paragraph styles

    func paragraphStyle(kind: LineKind, level: Int, listDepth: Int, quoteDepth: Int, prefixWidth: CGFloat, afterHeading: Bool, reserved: CGFloat? = nil, collapsed: Bool = false) -> NSParagraphStyle {
        let key = "\(kind)|\(level)|\(listDepth)|\(quoteDepth)|\(Int(prefixWidth * 4))|\(afterHeading)|\(Int(reserved ?? 0))|\(collapsed)"
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
            lh = (size * (level <= 2 ? 1.1 : 1.2)).rounded()
            switch level { case 1: before = m.unit * 1.0; case 2: before = m.unit * 0.7; case 3: before = m.unit * 0.45; default: before = m.unit * 0.15 }
        case .blank:
            lh = afterHeading ? (m.unit * 0.3).rounded() : (m.unit * 0.55).rounded()
        case .code, .codeFence, .table, .tableSeparator, .frontmatter:
            lh = (m.unit * 0.92).rounded()
        default: break
        }
        if let reserved { lh = reserved; before = 0 }
        if collapsed { lh = kind == .codeFence ? 10 : 1; before = 0 }   // hidden fences become the panel's inner padding
        ps.minimumLineHeight = lh
        ps.maximumLineHeight = lh
        ps.paragraphSpacingBefore = before
        let head = m.columnLeft + m.textEdge + CGFloat(max(0, listDepth - 1)) * m.listIndent + CGFloat(quoteDepth) * m.quoteIndent
        ps.headIndent = head
        ps.firstLineHeadIndent = max(0, head - prefixWidth - (quoteDepth > 0 && prefixWidth > 0 ? 14 : 0))
        switch kind {
        case .table, .tableSeparator: break                           // tables may run past the measure
        case .code, .codeFence:
            ps.lineBreakMode = .byWordWrapping                        // long lines wrap inside the panel
            ps.tailIndent = m.columnLeft + m.columnWidth
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
        for s in model.inlines where s.kind == .footnoteRef && s.range.length > 3 {
            // "[^id]" → hide the brackets in reading mode, mute them in edit mode
            let text = s.range
            if text.location + 1 < length { flags[text.location] |= Flag.marker; flags[text.location + 1] |= Flag.marker }
            let last = text.location + text.length - 1
            if last < length { flags[last] |= Flag.marker }
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
            let isActive = activeLines.contains(li)
            let rendered = mode == .rendered && !isActive
            let reserved = rendered ? reservedHeights[li] : nil
            let collapsed = rendered && reserved == nil && (line.kind == .codeFence || line.kind == .frontmatter || line.kind == .linkDef || line.kind == .tableSeparator || line.kind == .table)
            let ps = paragraphStyle(kind: line.kind, level: line.headingLevel, listDepth: line.listDepth, quoteDepth: line.quoteDepth, prefixWidth: rendered ? 0 : pw, afterHeading: line.afterHeading, reserved: reserved, collapsed: collapsed)
            let paraRange = NSRange(location: lr.location, length: min(lr.length + 1, length - lr.location))
            storage.addAttribute(.paragraphStyle, value: ps, range: paraRange)
            guard lr.length > 0 else { continue }
            if rendered, reserved != nil, line.kind != .table {   // image line: the overlay replaces the text
                storage.addAttributes(hiddenAttributes, range: lr); continue
            }
            let active = isActive
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
        // Table pipe alignment via kern on the last character of each short cell (source view, or the active table).
        do {
            let mono = monoFont()
            let adv = FontCache.advance(of: mono)
            for t in model.tables where t.lineRange.overlaps(r) && (mode == .source || activeLines.overlaps(t.lineRange)) {
                for tl in t.lines where r.contains(tl.line) {
                    for p in tl.pads where p.offset < length {
                        storage.addAttribute(.kern, value: adv * CGFloat(p.chars), range: NSRange(location: p.offset, length: 1))
                    }
                }
            }
        }
        // Clickable links in rendered mode.
        if mode == .rendered {
            let first = model.lines[r.lowerBound].range.location
            let spans = model.inlines
            for (i, sp) in spans.enumerated() where sp.range.location >= first && sp.range.location < last {
                var target: String? = nil
                if sp.kind == .autolink { target = text.substring(with: sp.range) }
                else if sp.kind == .linkText, i + 1 < spans.count {
                    // the URL span follows the "](" marker
                    if let u = spans[(i + 1)..<min(spans.count, i + 4)].first(where: { $0.kind == .linkURL }) {
                        target = text.substring(with: u.range).components(separatedBy: " \"").first
                    }
                }
                guard let t = target?.trimmingCharacters(in: .whitespaces), !t.isEmpty else { continue }
                let url = t.contains("://") || t.hasPrefix("mailto:") ? URL(string: t) : baseURL.map { URL(fileURLWithPath: t, relativeTo: $0).standardizedFileURL }
                if let url { storage.addAttribute(.link, value: url, range: sp.range) }
            }
        }
        _ = m
        storage.endEditing()
    }

    /// Renders a one-line Markdown fragment (table cell) as an attributed string with markers removed.
    private var inlineCache: [String: NSAttributedString] = [:]
    func renderInline(_ text: String, bold: Bool, baseURL: URL?) -> NSAttributedString {
        let key = "\(bold)|\(text)"
        if let c = inlineCache[key] { return c }
        defer { if inlineCache.count > 5000 { inlineCache.removeAll() } }
        let m = MarkdownParser.parse(text)
        let fl = paintFlags(model: m, length: (text as NSString).length)
        let out = NSMutableAttributedString()
        let ns = text as NSString
        let line = LineInfo(range: NSRange(location: 0, length: ns.length), kind: .text)
        let size = (effectiveBodySize * 0.9).rounded()
        var i = 0
        while i < ns.length {
            var j = i
            while j < ns.length, fl[j] == fl[i] { j += 1 }
            let f = fl[i]
            if f & Flag.hiddenInReading == 0 {
                var a: [NSAttributedString.Key: Any] = attributes(line: line, flags: f, active: false)
                let isMono = f & Flag.code != 0
                a[.font] = isMono ? monoFont(weight: (bold || f & Flag.strong != 0) ? 700 : 400, size: (size * theme.monoScale / 0.9).rounded())
                                  : bodyFont(weight: (bold || f & Flag.strong != 0) ? 600 : 400, italic: f & Flag.emphasis != 0, size: size)
                a.removeValue(forKey: .paragraphStyle)
                out.append(NSAttributedString(string: ns.substring(with: NSRange(location: i, length: j - i)), attributes: a))
            }
            i = j
        }
        inlineCache[key] = out
        return out
    }

    private func fontFor(line: LineInfo, flags: UInt32) -> NSFont {
        attributes(line: line, flags: flags, active: false)[.font] as! NSFont
    }

    /// Zero-size, clear run. The character stays in the storage (offsets never change) but takes no space.
    var hiddenAttributes: [NSAttributedString.Key: Any] {
        [.font: NSFont(descriptor: bodyFont().fontDescriptor, size: 0.1) ?? bodyFont(), .foregroundColor: NSColor.clear, .kern: 0, .baselineOffset: 0]
    }

    func isHiddenInReading(line: LineInfo, flags f: UInt32) -> Bool {
        if f & Flag.hiddenInReading != 0 { return true }
        if f & (Flag.criticComment | Flag.criticAuthor) != 0 { return true }
        switch line.kind { case .codeFence, .rule, .tableSeparator, .table, .frontmatter, .linkDef: return true; default: return false }
    }

    /// Attributes for a run. Cached by (line kind, heading level, flags, active, mode).
    func attributes(line: LineInfo, flags f: UInt32, active: Bool) -> [NSAttributedString.Key: Any] {
        if mode == .rendered, !active, isHiddenInReading(line: line, flags: f) { return hiddenAttributes }
        let kindCode: UInt64 = { switch line.kind {
            case .blank: return 0; case .text: return 1; case .heading: return 2; case .listItem: return 3; case .listContinuation: return 4
            case .code: return 5; case .codeFence: return 6; case .table: return 7; case .tableSeparator: return 8; case .rule: return 9
            case .frontmatter: return 10; case .html: return 11; case .footnoteDef: return 12; case .linkDef: return 13 } }()
        let key = kindCode | UInt64(line.headingLevel) << 8 | UInt64(f) << 16 | (active ? 1 : 0) << 48 | (mode == .rendered ? 1 : 0) << 49
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
            let tr = metrics.headingTracking(line.headingLevel)
            if tr != 0 { a[.kern] = tr * metrics.headingSize(line.headingLevel) }
            if line.headingLevel >= 5 { color = Palette.fgMuted }
        } else if isMono || f & Flag.code != 0 || f & Flag.html != 0 {
            a[.font] = monoFont(weight: bold ? 700 : 400, italic: italic)
            if f & Flag.code != 0 && !isMono { a[.backgroundColor] = Palette.inlineCodeFill }
            if line.kind == .codeFence || line.kind == .tableSeparator || line.kind == .frontmatter || f & Flag.html != 0 { color = Palette.fgMuted }
        } else if f & Flag.linkURL != 0 {
            a[.font] = bodyFont(weight: 400, italic: false, size: (effectiveBodySize * 0.85).rounded())
            color = Palette.fgMuted
        } else if f & Flag.criticComment != 0 || f & Flag.criticAuthor != 0 {
            a[.font] = bodyFont(weight: bold ? 600 : 400, italic: italic, size: (effectiveBodySize * 0.9).rounded())
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
        if f & Flag.footnoteRef != 0 { color = Palette.accent; a[.baselineOffset] = effectiveBodySize * 0.25; a[.font] = bodyFont(weight: 500, size: (effectiveBodySize * 0.75).rounded()) }
        if f & Flag.imageAlt != 0 { color = Palette.fgMuted }
        if f & Flag.criticHighlight != 0 { a[.backgroundColor] = Palette.commentFill }
        if f & Flag.criticAdd != 0 || f & Flag.criticSubstNew != 0 { color = Palette.added }
        if f & Flag.criticDel != 0 || f & Flag.criticSubstOld != 0 { color = Palette.removed }
        if f & Flag.criticMarker != 0 { color = Palette.fgMuted.withAlphaComponent(active ? 0.9 : 0.6) }
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
