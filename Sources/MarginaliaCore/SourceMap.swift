import Foundation

/// Maps swift-markdown's (line, UTF-8 column) locations to UTF-16 offsets for NSAttributedString,
/// and knows every line's UTF-16 range. Built once per parse, O(n).
public struct SourceMap {
    public let bytes: [UInt8]
    public let lineStartsUTF8: [Int]
    public let lineStartsUTF16: [Int]
    public let lineIsASCII: [Bool]
    public let utf16Count: Int

    public init(_ text: String) {
        let bytes = Array(text.utf8)
        var starts8 = [0], starts16 = [0], ascii: [Bool] = []
        var j = 0, lineASCII = true
        var i = 0
        let n = bytes.count
        while i < n {
            let b = bytes[i]
            if b == 0x0A {
                ascii.append(lineASCII); lineASCII = true
                j += 1
                starts8.append(i + 1); starts16.append(j)
            } else if b < 0x80 {
                j += 1
            } else {
                lineASCII = false
                if b >= 0xF0 { j += 2 } else if b >= 0xC0 { j += 1 }
            }
            i += 1
        }
        ascii.append(lineASCII)
        self.bytes = bytes
        lineStartsUTF8 = starts8
        lineStartsUTF16 = starts16
        lineIsASCII = ascii
        utf16Count = j
    }

    public var lineCount: Int { lineStartsUTF8.count }

    /// 1-based line and column (UTF-8 bytes, 1-based) to a UTF-16 offset.
    public func utf16Offset(line: Int, column: Int) -> Int {
        let li = max(0, min(line - 1, lineCount - 1))
        let byteOff = lineStartsUTF8[li] + column - 1
        if lineIsASCII[li] { return min(lineStartsUTF16[li] + column - 1, utf16Count) }
        var u = lineStartsUTF16[li]
        var k = lineStartsUTF8[li]
        let end = min(byteOff, bytes.count)
        while k < end {
            let b = bytes[k]
            if b < 0x80 || b >= 0xC0 { u += (b >= 0xF0) ? 2 : 1 }
            k += 1
        }
        return u
    }

    /// UTF-16 range of a 0-based line, excluding its newline.
    public func lineRange(_ index: Int) -> NSRange {
        let start = lineStartsUTF16[index]
        let end = index + 1 < lineCount ? lineStartsUTF16[index + 1] - 1 : utf16Count
        return NSRange(location: start, length: max(0, end - start))
    }

    /// Bytes of a 0-based line, excluding its newline.
    public func lineBytes(_ index: Int) -> ArraySlice<UInt8> {
        let start = lineStartsUTF8[index]
        let end = index + 1 < lineCount ? lineStartsUTF8[index + 1] - 1 : bytes.count
        return bytes[start..<max(start, end)]
    }

    /// 0-based line index containing a UTF-16 offset.
    public func lineIndex(forUTF16 offset: Int) -> Int {
        var lo = 0, hi = lineCount - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if lineStartsUTF16[mid] <= offset { lo = mid } else { hi = mid - 1 }
        }
        return lo
    }
}
