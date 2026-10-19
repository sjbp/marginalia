import Foundation

/// Pure editing rules. The app turns an `Edit` into an undoable text view change.
public enum SmartEdit {
    public struct Edit: Equatable {
        public var range: NSRange          // in document coordinates
        public var replacement: String
        public var caret: Int              // absolute caret location after the edit
        public init(range: NSRange, replacement: String, caret: Int) { self.range = range; self.replacement = replacement; self.caret = caret }
    }

    static let listMarker = try! NSRegularExpression(pattern: #"^(\s*)([-*+]|(\d+)([.)]))(\s+)(\[[ xX]\]\s+)?"#)
    static let quoteMarker = try! NSRegularExpression(pattern: #"^((?:\s{0,3}>\s?)+)"#)
    static let leadingSpace = try! NSRegularExpression(pattern: #"^[ \t]*"#)
    static let heading = try! NSRegularExpression(pattern: #"^(#{1,6})(\s+)"#)

    /// Return pressed with the caret inside `line` (no trailing newline) at `caretInLine`.
    /// `lineStart` is the line's absolute location. Returns nil for a plain newline.
    public static func newline(line: String, lineStart: Int, caretInLine: Int, info: LineInfo) -> Edit? {
        let ns = line as NSString
        let full = NSRange(location: 0, length: ns.length)
        let caret = lineStart + caretInLine

        var quotePrefix = ""
        var rest = line
        var restOffset = 0
        if info.quoteDepth > 0, let m = quoteMarker.firstMatch(in: line, range: full) {
            quotePrefix = ns.substring(with: m.range)
            restOffset = m.range.length
            rest = ns.substring(from: restOffset)
        }
        let restNS = rest as NSString

        if info.kind == .listItem, let m = listMarker.firstMatch(in: rest, range: NSRange(location: 0, length: restNS.length)) {
            let markerLen = m.range.length
            let content = restNS.substring(from: markerLen).trimmingCharacters(in: .whitespaces)
            if content.isEmpty {
                // Empty item: Return removes the marker (and the quote prefix stays).
                let r = NSRange(location: lineStart + restOffset, length: ns.length - restOffset)
                return Edit(range: r, replacement: "", caret: lineStart + restOffset)
            }
            if caretInLine < restOffset + markerLen { return nil }
            let indent = restNS.substring(with: m.range(at: 1))
            var marker = restNS.substring(with: m.range(at: 2))
            if m.range(at: 3).location != NSNotFound, let n = Int(restNS.substring(with: m.range(at: 3))) {
                marker = "\(n + 1)" + restNS.substring(with: m.range(at: 4))
            }
            let space = restNS.substring(with: m.range(at: 5))
            let box = m.range(at: 6).location != NSNotFound ? "[ ] " : ""
            let insert = "\n" + quotePrefix + indent + marker + space + box
            return Edit(range: NSRange(location: caret, length: 0), replacement: insert, caret: caret + (insert as NSString).length)
        }

        if info.quoteDepth > 0 {
            if rest.trimmingCharacters(in: .whitespaces).isEmpty {
                return Edit(range: NSRange(location: lineStart, length: ns.length), replacement: "", caret: lineStart)
            }
            if caretInLine < restOffset { return nil }
            let insert = "\n" + quotePrefix
            return Edit(range: NSRange(location: caret, length: 0), replacement: insert, caret: caret + (insert as NSString).length)
        }

        if info.kind == .listContinuation || info.kind == .code {
            let m = leadingSpace.firstMatch(in: line, range: full)!
            let ws = ns.substring(with: m.range)
            guard caretInLine >= m.range.length else { return nil }
            let insert = "\n" + ws
            return Edit(range: NSRange(location: caret, length: 0), replacement: insert, caret: caret + (insert as NSString).length)
        }
        return nil
    }

    /// Tab / Shift-Tab on a list line: indent or outdent by two spaces.
    public static func shiftIndent(line: String, lineStart: Int, caret: Int, outdent: Bool) -> Edit? {
        let ns = line as NSString
        if outdent {
            var n = 0
            while n < 2, n < ns.length, ns.character(at: n) == 0x20 { n += 1 }
            guard n > 0 else { return nil }
            return Edit(range: NSRange(location: lineStart, length: n), replacement: "", caret: max(lineStart, caret - n))
        }
        return Edit(range: NSRange(location: lineStart, length: 0), replacement: "  ", caret: caret + 2)
    }

    /// Wraps or unwraps the selection with a delimiter such as `**`, `_`, or `` ` ``.
    public static func toggleWrap(text: NSString, selection: NSRange, delimiter: String) -> Edit {
        let d = delimiter as NSString
        let dl = d.length
        // Already wrapped inside the selection?
        if selection.length >= 2 * dl {
            let s = text.substring(with: selection) as NSString
            if s.hasPrefix(delimiter), s.hasSuffix(delimiter) {
                let inner = s.substring(with: NSRange(location: dl, length: s.length - 2 * dl))
                return Edit(range: selection, replacement: inner, caret: selection.location + (inner as NSString).length)
            }
        }
        // Wrapped around the selection?
        if selection.location >= dl, selection.location + selection.length + dl <= text.length {
            let before = text.substring(with: NSRange(location: selection.location - dl, length: dl))
            let after = text.substring(with: NSRange(location: selection.location + selection.length, length: dl))
            if before == delimiter, after == delimiter {
                let inner = text.substring(with: selection)
                let r = NSRange(location: selection.location - dl, length: selection.length + 2 * dl)
                return Edit(range: r, replacement: inner, caret: r.location + (inner as NSString).length)
            }
        }
        let inner = text.substring(with: selection)
        let rep = delimiter + inner + delimiter
        // Caret: after the selection when wrapping, between delimiters when empty.
        let caret = selection.length == 0 ? selection.location + dl : selection.location + (rep as NSString).length
        return Edit(range: selection, replacement: rep, caret: caret)
    }

    /// `[selection](url)` with the caret inside the parentheses, or a URL from the clipboard filled in.
    public static func link(text: NSString, selection: NSRange, clipboardURL: String?) -> Edit {
        let inner = text.substring(with: selection)
        if let u = clipboardURL {
            let rep = "[\(inner)](\(u))"
            return Edit(range: selection, replacement: rep, caret: selection.location + (rep as NSString).length)
        }
        let rep = "[\(inner)]()"
        return Edit(range: selection, replacement: rep, caret: selection.location + (rep as NSString).length - 1)
    }

    /// Raises or lowers the heading level of a line. Level 0 means paragraph.
    public static func shiftHeading(line: String, lineStart: Int, caret: Int, up: Bool) -> Edit? {
        let ns = line as NSString
        if let m = heading.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) {
            let level = m.range(at: 1).length
            let newLevel = up ? min(6, level + 1) : level - 1
            if newLevel == level { return nil }
            let rep = newLevel == 0 ? "" : String(repeating: "#", count: newLevel) + " "
            let delta = (rep as NSString).length - m.range.length
            return Edit(range: NSRange(location: lineStart, length: m.range.length), replacement: rep, caret: max(lineStart, caret + delta))
        }
        guard up else { return nil }
        return Edit(range: NSRange(location: lineStart, length: 0), replacement: "# ", caret: caret + 2)
    }

    /// Toggles `- [ ]` / `- [x]`, adding a task marker when the line is not a task yet.
    public static func toggleTask(line: String, lineStart: Int, caret: Int) -> Edit {
        let ns = line as NSString
        if let m = listMarker.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) {
            if m.range(at: 6).location != NSNotFound {
                let boxRange = m.range(at: 6)
                let box = ns.substring(with: boxRange)
                let isDone = box.contains("x") || box.contains("X")
                let r = NSRange(location: lineStart + boxRange.location + 1, length: 1)
                return Edit(range: r, replacement: isDone ? " " : "x", caret: caret)
            }
            let at = lineStart + m.range.length
            return Edit(range: NSRange(location: at, length: 0), replacement: "[ ] ", caret: caret + (caret >= at ? 4 : 0))
        }
        let m = leadingSpace.firstMatch(in: line, range: NSRange(location: 0, length: ns.length))!
        let at = lineStart + m.range.length
        return Edit(range: NSRange(location: at, length: 0), replacement: "- [ ] ", caret: caret + (caret >= at ? 6 : 0))
    }

    /// Moves the lines covering `selection` up or down by one line. Returns the edit and the new selection.
    public static func moveLines(text: NSString, selection: NSRange, up: Bool) -> (Edit, NSRange)? {
        let block = text.lineRange(for: selection)
        if up {
            guard block.location > 0 else { return nil }
            let prev = text.lineRange(for: NSRange(location: block.location - 1, length: 0))
            var blockText = text.substring(with: block)
            var prevText = text.substring(with: prev)
            if !blockText.hasSuffix("\n") { blockText += "\n"; prevText = String(prevText.dropLast()) }
            let r = NSRange(location: prev.location, length: prev.length + block.length)
            let rep = blockText + prevText
            let newSel = NSRange(location: selection.location - prev.length, length: selection.length)
            return (Edit(range: r, replacement: rep, caret: newSel.location), newSel)
        } else {
            let end = block.location + block.length
            guard end < text.length else { return nil }
            let next = text.lineRange(for: NSRange(location: end, length: 0))
            var blockText = text.substring(with: block)
            var nextText = text.substring(with: next)
            if !nextText.hasSuffix("\n") { nextText += "\n"; blockText = String(blockText.dropLast()) }
            let r = NSRange(location: block.location, length: block.length + next.length)
            let rep = nextText + blockText
            let newSel = NSRange(location: selection.location + (nextText as NSString).length, length: selection.length)
            return (Edit(range: r, replacement: rep, caret: newSel.location), newSel)
        }
    }
}

// MARK: - Block formatting (format bar)

public enum BlockKind: Equatable { case bullet, number, task, quote, heading(Int) }

extension SmartEdit {
    static let anyListMarker = try! NSRegularExpression(pattern: #"^(\s*)([-*+]|\d+[.)])\s+(\[[ xX]\]\s+)?"#)
    static let headingMarker = try! NSRegularExpression(pattern: #"^(\s{0,3})#{1,6}\s+"#)
    static let quoteOnly = try! NSRegularExpression(pattern: #"^(\s{0,3}>\s?)"#)

    struct LineParts { var quote: String; var block: String; var rest: String }

    /// Splits a line into its quote prefix, its block prefix (list marker or heading), and the content.
    static func parts(_ line: String) -> LineParts {
        var s = line
        var quote = ""
        while let m = quoteOnly.firstMatch(in: s, range: NSRange(location: 0, length: (s as NSString).length)) {
            quote += (s as NSString).substring(with: m.range)
            s = (s as NSString).substring(from: m.range.length)
        }
        let ns = s as NSString
        if let m = anyListMarker.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) {
            return LineParts(quote: quote, block: ns.substring(with: m.range), rest: ns.substring(from: m.range.length))
        }
        if let m = headingMarker.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) {
            return LineParts(quote: quote, block: ns.substring(with: m.range), rest: ns.substring(from: m.range.length))
        }
        return LineParts(quote: quote, block: "", rest: s)
    }

    static func kind(ofBlock block: String, quote: String) -> BlockKind? {
        let t = block.trimmingCharacters(in: .whitespaces)
        if t.isEmpty { return quote.isEmpty ? nil : .quote }
        if t.hasPrefix("#") { return .heading(t.filter { $0 == "#" }.count) }
        if t.contains("[") { return .task }
        if let f = t.first, f.isNumber { return .number }
        return .bullet
    }

    /// Applies or removes a block kind on every line the selection touches. Returns the edit and the new selection.
    public static func toggleBlock(text: NSString, selection: NSRange, kind: BlockKind) -> (Edit, NSRange) {
        let block = text.lineRange(for: selection)
        var raw = text.substring(with: block)
        let hadNewline = raw.hasSuffix("\n")
        if hadNewline { raw.removeLast() }
        let lines = raw.components(separatedBy: "\n")
        let parsed = lines.map(parts)
        let allAlready = parsed.allSatisfy { p in
            switch kind {
            case .quote: return !p.quote.isEmpty
            default: return SmartEdit.kind(ofBlock: p.block, quote: "") == kind
            }
        }
        var out: [String] = []
        var n = 1
        for p in parsed {
            switch kind {
            case .quote:
                out.append(allAlready ? p.block + p.rest : "> " + p.quote + p.block + p.rest)
            case .bullet:
                out.append(p.quote + (allAlready ? "" : "- ") + p.rest)
            case .task:
                out.append(p.quote + (allAlready ? "" : "- [ ] ") + p.rest)
            case .number:
                out.append(p.quote + (allAlready ? "" : "\(n). ") + p.rest); n += 1
            case .heading(let level):
                out.append(p.quote + (allAlready ? "" : String(repeating: "#", count: level) + " ") + p.rest)
            }
        }
        var rep = out.joined(separator: "\n")
        if hadNewline { rep += "\n" }
        let newSel = NSRange(location: block.location, length: (rep as NSString).length - (hadNewline ? 1 : 0))
        return (Edit(range: block, replacement: rep, caret: newSel.location + newSel.length), newSel)
    }
}

extension SmartEdit {
    /// `toggleWrap` plus the range to select afterwards (the inner text), so a format bar stays attached.
    public static func toggleWrapSelecting(text: NSString, selection: NSRange, delimiter: String) -> (Edit, NSRange) {
        let e = toggleWrap(text: text, selection: selection, delimiter: delimiter)
        let dl = (delimiter as NSString).length
        let rep = e.replacement as NSString
        if selection.length == 0 { return (e, NSRange(location: e.caret, length: 0)) }
        if rep.length == selection.length + 2 * dl { return (e, NSRange(location: e.range.location + dl, length: selection.length)) }   // wrapped
        return (e, NSRange(location: e.range.location, length: rep.length))                                                          // unwrapped
    }
}
