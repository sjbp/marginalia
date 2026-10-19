import Foundation
import Markdown

public enum MarkdownParser {
    public static func parse(_ text: String) -> DocumentModel {
        let map = SourceMap(text)
        var model = DocumentModel(map: map)
        model.lines = (0..<map.lineCount).map { LineInfo(range: map.lineRange($0)) }
        for i in 0..<map.lineCount where map.lineBytes(i).allSatisfy({ $0 == 0x20 || $0 == 0x09 || $0 == 0x0D }) {
            model.lines[i].kind = .blank
        }

        let doc = Markdown.Document(parsing: text)
        var walker = Walker(model: model, text: text as NSString)
        walker.visit(doc, quoteDepth: 0, listDepth: 0, contentIndent: 0)
        model = walker.model

        detectFrontmatter(&model)
        detectDefinitionLines(&model)
        computePrefixes(&model)
        CriticMarkup.scan(text as NSString, into: &model)
        detectFootnoteRefs(text as NSString, &model)
        if model.lines.count > 1 {
            for i in 1..<model.lines.count where model.lines[i - 1].kind == .heading { model.lines[i].afterHeading = true }
        }
        return model
    }

    // MARK: - Tree walk

    struct Walker {
        var model: DocumentModel
        let text: NSString

        func lines(of m: Markup) -> Range<Int>? {
            guard let r = m.range else { return nil }
            var last = r.upperBound.line
            if r.upperBound.column == 1 && last > r.lowerBound.line { last -= 1 }
            let lo = r.lowerBound.line - 1, hi = min(last, model.lines.count)
            return lo < hi ? lo..<hi : nil
        }

        func nsRange(_ m: Markup) -> NSRange? {
            guard let r = m.range else { return nil }
            let a = model.map.utf16Offset(line: r.lowerBound.line, column: r.lowerBound.column)
            let b = model.map.utf16Offset(line: r.upperBound.line, column: r.upperBound.column)
            return NSRange(location: a, length: max(0, b - a))
        }

        func childrenUnion(_ m: Markup) -> NSRange? {
            var lo = Int.max, hi = Int.min
            for c in m.children { if let r = nsRange(c) { lo = min(lo, r.location); hi = max(hi, r.location + r.length) } }
            return lo <= hi ? NSRange(location: lo, length: hi - lo) : nil
        }

        mutating func add(_ range: NSRange, _ kind: InlineKind) {
            guard range.length > 0 else { return }
            model.inlines.append(InlineSpan(range, kind))
        }

        mutating func wrapped(_ m: Markup, _ kind: InlineKind) {
            guard let r = nsRange(m), let c = childrenUnion(m) else { return }
            add(NSRange(location: r.location, length: c.location - r.location), .marker)
            add(NSRange(location: c.location + c.length, length: r.location + r.length - (c.location + c.length)), .marker)
            add(c, kind)
        }

        mutating func visit(_ m: Markup, quoteDepth: Int, listDepth: Int, contentIndent: Int) {
            var qd = quoteDepth, ld = listDepth, ci = contentIndent
            switch m {
            case let h as Heading:
                if let ls = lines(of: h) {
                    for i in ls { model.lines[i].kind = .heading; model.lines[i].headingLevel = h.level; model.lines[i].quoteDepth = qd }
                    model.headings.append(HeadingInfo(level: h.level, title: h.plainText, range: model.map.lineRange(ls.lowerBound)))
                }
            case let li as ListItem:
                ld += 1
                if let ls = lines(of: li) {
                    let first = ls.lowerBound
                    if let c = li.children.first(where: { $0.range != nil }), let cr = c.range {
                        ci = model.map.utf16Offset(line: cr.lowerBound.line, column: cr.lowerBound.column) - model.map.lineRange(first).location
                    }
                    for i in ls where model.lines[i].kind == .text { model.lines[i].kind = .listContinuation }
                    for i in ls { model.lines[i].listDepth = ld; model.lines[i].contentIndent = ci; model.lines[i].quoteDepth = qd }
                    model.lines[first].kind = .listItem
                    model.lines[first].ordered = li.parent is OrderedList
                    if let cb = li.checkbox { model.lines[first].checkbox = cb == .checked ? 2 : 1 }
                }
            case let q as BlockQuote:
                qd += 1
                if let ls = lines(of: q) { for i in ls { model.lines[i].quoteDepth = qd } }
            case let cb as CodeBlock:
                if let ls = lines(of: cb) {
                    let fenced = isFence(model.map.lineBytes(ls.lowerBound))
                    for i in ls {
                        model.lines[i].kind = .code
                        model.lines[i].inFence = fenced
                        model.lines[i].listDepth = ld; model.lines[i].contentIndent = ci; model.lines[i].quoteDepth = qd
                    }
                    if fenced {
                        model.lines[ls.lowerBound].kind = .codeFence
                        if ls.count > 1, isFence(model.map.lineBytes(ls.upperBound - 1)) { model.lines[ls.upperBound - 1].kind = .codeFence }
                    }
                    model.codeBlocks.append(CodeBlockInfo(lineRange: ls, language: cb.language, fenced: fenced))
                }
                return
            case let t as Table:
                if let ls = lines(of: t) {
                    for i in ls { model.lines[i].kind = .table; model.lines[i].listDepth = ld; model.lines[i].contentIndent = ci; model.lines[i].quoteDepth = qd }
                    if ls.count > 1 { model.lines[ls.lowerBound + 1].kind = .tableSeparator }
                    model.tables.append(TableLayout.layout(lines: ls, map: model.map))
                }
            case is ThematicBreak:
                if let ls = lines(of: m) { for i in ls { model.lines[i].kind = .rule; model.lines[i].quoteDepth = qd } }
            case is HTMLBlock:
                if let ls = lines(of: m) { for i in ls { model.lines[i].kind = .html; model.lines[i].quoteDepth = qd } }
                return
            case is Paragraph:
                if let ls = lines(of: m) {
                    for i in ls {
                        model.lines[i].quoteDepth = qd
                        if ld > 0 { model.lines[i].listDepth = max(model.lines[i].listDepth, ld); model.lines[i].contentIndent = ci }
                    }
                }
            case is Strong: wrapped(m, .strong)
            case is Emphasis: wrapped(m, .emphasis)
            case is Strikethrough: wrapped(m, .strike)
            case let ic as InlineCode:
                if let r = nsRange(ic) {
                    var n = 0
                    while n < r.length, text.character(at: r.location + n) == 0x60 { n += 1 }
                    add(NSRange(location: r.location, length: n), .marker)
                    add(NSRange(location: r.location + r.length - n, length: n), .marker)
                    add(NSRange(location: r.location + n, length: max(0, r.length - 2 * n)), .code)
                }
                return
            case let l as Link:
                if let r = nsRange(l) {
                    let raw = text.substring(with: r)
                    if raw.hasPrefix("<") {
                        add(NSRange(location: r.location, length: 1), .marker)
                        add(NSRange(location: r.location + r.length - 1, length: 1), .marker)
                        add(NSRange(location: r.location + 1, length: max(0, r.length - 2)), .autolink)
                        return
                    }
                    if raw.hasPrefix("[^") { add(r, .footnoteRef); return }
                    if let c = childrenUnion(l) { linkParts(r, c, image: false) } else { add(r, .linkText) }
                }
            case let im as Image:
                if let r = nsRange(im) {
                    if let c = childrenUnion(im) { linkParts(r, c, image: true) } else { add(r, .imageAlt) }
                }
            case is InlineHTML:
                if let r = nsRange(m) { add(r, .html) }
                return
            default: break
            }
            for c in m.children { visit(c, quoteDepth: qd, listDepth: ld, contentIndent: ci) }
        }

        /// Splits `[text](url "title")` or `![alt](src)` into marker / text / url spans.
        mutating func linkParts(_ r: NSRange, _ c: NSRange, image: Bool) {
            let textEnd = c.location + c.length
            add(NSRange(location: r.location, length: c.location - r.location), .marker)
            add(c, image ? .imageAlt : .linkText)
            let rEnd = r.location + r.length
            if textEnd + 1 < rEnd, text.character(at: textEnd) == 0x5D, text.character(at: textEnd + 1) == 0x28 {
                add(NSRange(location: textEnd, length: 2), .marker)
                add(NSRange(location: textEnd + 2, length: max(0, rEnd - 1 - (textEnd + 2))), .linkURL)
                add(NSRange(location: rEnd - 1, length: 1), .marker)
            } else {
                add(NSRange(location: textEnd, length: rEnd - textEnd), .marker)
            }
        }
    }

    static func isFence(_ line: ArraySlice<UInt8>) -> Bool {
        var i = line.startIndex
        var spaces = 0
        while i < line.endIndex, line[i] == 0x20, spaces < 3 { i += 1; spaces += 1 }
        guard i < line.endIndex else { return false }
        let ch = line[i]
        guard ch == 0x60 || ch == 0x7E else { return false }
        var n = 0
        while i < line.endIndex, line[i] == ch { n += 1; i += 1 }
        return n >= 3
    }

    // MARK: - Post passes

    static func detectFrontmatter(_ model: inout DocumentModel) {
        guard model.lines.count > 2, isDashes(model.map.lineBytes(0)) else { return }
        for i in 1..<min(model.lines.count, 120) {
            let b = model.map.lineBytes(i)
            if isDashes(b) || Array(b) == Array("...".utf8) {
                model.frontmatterLines = 0..<(i + 1)
                for j in 0...i { model.lines[j] = LineInfo(range: model.lines[j].range, kind: .frontmatter) }
                let end = model.lines[i].range.location + model.lines[i].range.length
                model.inlines.removeAll { $0.range.location < end }
                model.headings.removeAll { $0.range.location < end }
                return
            }
        }
    }

    static func isDashes(_ b: ArraySlice<UInt8>) -> Bool {
        let t = b.drop(while: { $0 == 0x20 }).reversed().drop(while: { $0 == 0x20 || $0 == 0x0D })
        return t.count >= 3 && t.allSatisfy { $0 == 0x2D }
    }

    /// Lines cmark drops from the tree: footnote definitions and link reference definitions.
    static func detectDefinitionLines(_ model: inout DocumentModel) {
        for i in 0..<model.lines.count where model.lines[i].kind == .text || model.lines[i].kind == .blank {
            let b = model.map.lineBytes(i)
            guard b.first == 0x5B, let close = b.firstIndex(of: 0x5D), close + 1 < b.endIndex, b[close + 1] == 0x3A else { continue }
            model.lines[i].kind = (b.count > 2 && b[b.startIndex + 1] == 0x5E) ? .footnoteDef : .linkDef
        }
    }

    static let footnoteRef = try! NSRegularExpression(pattern: #"\[\^[^\]\s]+\]"#)
    static func detectFootnoteRefs(_ text: NSString, _ model: inout DocumentModel) {
        let covered = model.inlines.filter { $0.kind == .footnoteRef || $0.kind == .code }.map { $0.range }
        for m in footnoteRef.matches(in: text as String, range: NSRange(location: 0, length: text.length)) {
            let line = model.lines[model.map.lineIndex(forUTF16: m.range.location)]
            guard line.kind != .code, line.kind != .codeFence, line.kind != .footnoteDef else { continue }
            if covered.contains(where: { NSIntersectionRange($0, m.range).length > 0 }) { continue }
            model.inlines.append(InlineSpan(m.range, .footnoteRef))
        }
    }

    static func computePrefixes(_ model: inout DocumentModel) {
        for i in 0..<model.lines.count {
            model.lines[i].prefixLength = prefixLength(line: model.map.lineBytes(i), info: model.lines[i])
        }
    }

    /// Number of leading UTF-16 units that hang in the gutter. Prefix characters are ASCII, so bytes == units.
    static func prefixLength(line: ArraySlice<UInt8>, info: LineInfo) -> Int {
        var i = line.startIndex
        let end = line.endIndex
        func skipSpaces(max: Int = Int.max) { var n = 0; while i < end, (line[i] == 0x20 || line[i] == 0x09), n < max { i += 1; n += 1 } }
        func peek() -> UInt8? { i < end ? line[i] : nil }

        for _ in 0..<info.quoteDepth {
            let save = i
            skipSpaces(max: 3)
            if peek() == 0x3E { i += 1; if peek() == 0x20 { i += 1 } } else { i = save; break }
        }
        switch info.kind {
        case .heading:
            skipSpaces(max: 3)
            var n = 0
            while peek() == 0x23, n < 6 { i += 1; n += 1 }
            if n == 0 { return 0 }
            skipSpaces()
        case .listItem:
            skipSpaces()
            if let c = peek(), c == 0x2D || c == 0x2A || c == 0x2B {
                i += 1
            } else {
                while let c = peek(), c >= 0x30, c <= 0x39 { i += 1 }
                if let c = peek(), c == 0x2E || c == 0x29 { i += 1 }
            }
            skipSpaces()
            if info.checkbox != 0, peek() == 0x5B, i + 2 < end, line[i + 2] == 0x5D { i += 3; skipSpaces() }
        case .listContinuation, .text, .table, .tableSeparator, .html, .rule:
            if info.listDepth > 0 { skipSpaces(max: info.contentIndent) } else if info.kind == .listContinuation { skipSpaces() }
        case .code, .codeFence:
            if info.listDepth > 0 { skipSpaces(max: info.contentIndent) }
            else if info.kind == .code, !info.inFence, line.starts(with: [0x20, 0x20, 0x20, 0x20]) { skipSpaces(max: 4) }
        default: break
        }
        return i - line.startIndex
    }
}

enum TableLayout {
    /// Pads each cell so pipes align when the table is set in a monospaced font.
    static func layout(lines: Range<Int>, map: SourceMap) -> TableInfo {
        var rows: [(line: Int, cells: [(start: Int, end: Int)])] = []
        for li in lines {
            let b = map.lineBytes(li)
            var cells: [(Int, Int)] = []
            var k = b.startIndex
            while k < b.endIndex, b[k] == 0x20 { k += 1 }
            var cellStart = k
            if k < b.endIndex, b[k] == 0x7C { cellStart = k + 1; k += 1 }
            var inCode = false
            while k < b.endIndex {
                let c = b[k]
                if c == 0x60 { inCode.toggle() }
                if c == 0x7C, !inCode, (k == b.startIndex || b[k - 1] != 0x5C) {
                    cells.append((cellStart, k)); cellStart = k + 1
                }
                k += 1
            }
            if cellStart < b.endIndex, !b[cellStart..<b.endIndex].allSatisfy({ $0 == 0x20 }) { cells.append((cellStart, b.endIndex)) }
            rows.append((li, cells))
        }
        let colCount = rows.map { $0.cells.count }.max() ?? 0
        var widths = Array(repeating: 0, count: colCount)
        func width(_ b: ArraySlice<UInt8>) -> Int { b.reduce(0) { $0 + (($1 & 0xC0) == 0x80 ? 0 : 1) } }
        for r in rows { for (ci, c) in r.cells.enumerated() { widths[ci] = max(widths[ci], width(map.bytes[c.start..<c.end])) } }
        var out: [TableLine] = []
        for r in rows {
            var pads: [TablePad] = []
            let lineStart8 = map.lineStartsUTF8[r.line]
            for (ci, c) in r.cells.enumerated() {
                let pad = widths[ci] - width(map.bytes[c.start..<c.end])
                guard pad > 0 else { continue }
                let targetByte = c.end > c.start ? c.end - 1 : c.start - 1
                guard targetByte >= lineStart8 else { continue }
                // step back to the start of a multi-byte scalar
                var tb = targetByte
                while tb > lineStart8, (map.bytes[tb] & 0xC0) == 0x80 { tb -= 1 }
                let off = map.utf16Offset(line: r.line + 1, column: tb - lineStart8 + 1)
                pads.append(TablePad(offset: off, chars: pad))
            }
            out.append(TableLine(line: r.line, pads: pads))
        }
        return TableInfo(lineRange: lines, lines: out)
    }
}
