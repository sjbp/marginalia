import Foundation

public enum LineKind: Equatable {
    case blank, text, heading, listItem, listContinuation, code, codeFence, table, tableSeparator, rule, frontmatter, html, footnoteDef, linkDef
}

public struct LineInfo: Equatable {
    public var range: NSRange
    public var kind: LineKind = .text
    /// UTF-16 length of the leading run that hangs in the gutter (indent + markers).
    public var prefixLength: Int = 0
    public var quoteDepth: Int = 0
    public var listDepth: Int = 0
    /// Content column (UTF-16 units from line start) of the innermost enclosing list item.
    public var contentIndent: Int = 0
    public var headingLevel: Int = 0
    public var ordered = false
    /// 0 none, 1 unchecked, 2 checked
    public var checkbox = 0
    public var afterHeading = false
    public var inFence = false
}

public enum InlineKind: Equatable {
    case strong, emphasis, strike, code, linkText, linkURL, autolink, imageAlt, marker, html, footnoteRef
    case criticHighlight, criticComment, criticAuthor, criticAdd, criticDel, criticSubstOld, criticSubstNew, criticMarker
}

public struct InlineSpan: Equatable {
    public var range: NSRange
    public var kind: InlineKind
    public init(_ range: NSRange, _ kind: InlineKind) { self.range = range; self.kind = kind }
}

public struct CodeBlockInfo: Equatable {
    public var lineRange: Range<Int>
    public var language: String?
    public var fenced: Bool
}

public struct TablePad: Equatable {
    /// Absolute UTF-16 offset of the character that receives padding kern.
    public var offset: Int
    /// Pad width in monospaced characters.
    public var chars: Int
}

public struct TableLine: Equatable {
    public var line: Int
    public var pads: [TablePad]
}

public struct TableInfo: Equatable {
    public var lineRange: Range<Int>
    public var lines: [TableLine]
}

public struct Comment: Equatable {
    public var range: NSRange          // whole {>> ... <<}
    public var textRange: NSRange      // the comment body after the author tag
    public var author: String?
    public var text: String
    public var anchorRange: NSRange?   // content inside a directly preceding {== ==}
    public var anchorMarkupRange: NSRange?
}

public struct HeadingInfo: Equatable {
    public var level: Int
    public var title: String
    public var range: NSRange
}

public struct DocumentModel {
    public var lines: [LineInfo] = []
    public var inlines: [InlineSpan] = []
    public var codeBlocks: [CodeBlockInfo] = []
    public var tables: [TableInfo] = []
    public var comments: [Comment] = []
    public var headings: [HeadingInfo] = []
    public var frontmatterLines: Range<Int>? = nil
    public var map: SourceMap
    public init(map: SourceMap) { self.map = map }
}
