import Foundation

/// CriticMarkup: {==highlight==} {>>comment<<} {++add++} {--del--} {~~old~>new~~}
public enum CriticMarkup {
    static let pattern = try! NSRegularExpression(pattern:
        #"\{==([\s\S]*?)==\}|\{>>([\s\S]*?)<<\}|\{\+\+([\s\S]*?)\+\+\}|\{--([\s\S]*?)--\}|\{~~([\s\S]*?)~>([\s\S]*?)~~\}"#)
    static let author = try! NSRegularExpression(pattern: #"^\s*@([\w.-]+):\s*"#)

    public static func scan(_ text: NSString, into model: inout DocumentModel) {
        var lastHighlight: (markup: NSRange, content: NSRange)? = nil
        var lastEnd = -1
        for m in pattern.matches(in: text as String, range: NSRange(location: 0, length: text.length)) {
            let whole = m.range
            func mark(_ r: NSRange, _ k: InlineKind) { if r.length > 0 { model.inlines.append(InlineSpan(r, k)) } }
            func ends() {
                mark(NSRange(location: whole.location, length: 3), .criticMarker)
                mark(NSRange(location: whole.location + whole.length - 3, length: 3), .criticMarker)
            }
            if m.range(at: 1).location != NSNotFound {
                let c = m.range(at: 1)
                ends()
                mark(c, .criticHighlight)
                lastHighlight = (whole, c)
                lastEnd = whole.location + whole.length
            } else if m.range(at: 2).location != NSNotFound {
                let c = m.range(at: 2)
                ends()
                var body = c
                var who: String? = nil
                let s = text.substring(with: c)
                if let am = author.firstMatch(in: s, range: NSRange(location: 0, length: (s as NSString).length)) {
                    who = (s as NSString).substring(with: am.range(at: 1))
                    mark(NSRange(location: c.location, length: am.range.length), .criticAuthor)
                    body = NSRange(location: c.location + am.range.length, length: c.length - am.range.length)
                }
                mark(body, .criticComment)
                let anchored = lastHighlight != nil && lastEnd == whole.location
                let anchor = anchored ? lastHighlight : nil
                model.comments.append(Comment(range: whole, textRange: body, author: who,
                                              text: text.substring(with: body).trimmingCharacters(in: .whitespacesAndNewlines),
                                              anchorRange: anchor?.content, anchorMarkupRange: anchor?.markup))
                lastEnd = whole.location + whole.length // replies chain through the same anchor
            } else if m.range(at: 3).location != NSNotFound {
                ends(); mark(m.range(at: 3), .criticAdd); lastHighlight = nil
            } else if m.range(at: 4).location != NSNotFound {
                ends(); mark(m.range(at: 4), .criticDel); lastHighlight = nil
            } else {
                let old = m.range(at: 5), new = m.range(at: 6)
                ends()
                mark(NSRange(location: old.location + old.length, length: 2), .criticMarker)
                mark(old, .criticSubstOld)
                mark(new, .criticSubstNew)
                lastHighlight = nil
            }
        }
    }

    public static func comment(author: String, text: String) -> String { "{>>@\(author): \(text)<<}" }
    public static func highlight(_ s: String) -> String { "{==\(s)==}" }
}
