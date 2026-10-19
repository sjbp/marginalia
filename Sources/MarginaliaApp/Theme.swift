import AppKit

enum ItalicStrategy { case face, slant(CGFloat) }

struct ThemeSpec: Equatable {
    static func == (a: ThemeSpec, b: ThemeSpec) -> Bool { a.id == b.id }
    let id: String
    let name: String
    let bodyFamily: String
    let monoFamily: String
    let italic: ItalicStrategy
    let hasOpsz: Bool
    let onum: Bool
    let bodySize: CGFloat
    let leading: CGFloat
    let monoScale: CGFloat
    /// Weight added in dark mode to counter halation.
    let darkWeightBoost: CGFloat

    static let flex = ThemeSpec(id: "flex", name: "Flex", bodyFamily: "Google Sans Flex", monoFamily: "Google Sans Code",
                                italic: .slant(-10), hasOpsz: true, onum: false, bodySize: 17, leading: 1.55, monoScale: 0.88, darkWeightBoost: 40)
    static let newsreader = ThemeSpec(id: "newsreader", name: "Newsreader", bodyFamily: "Newsreader", monoFamily: "Geist Mono",
                                      italic: .face, hasOpsz: true, onum: true, bodySize: 18, leading: 1.5, monoScale: 0.82, darkWeightBoost: 40)
    static let quattro = ThemeSpec(id: "quattro", name: "Quattro", bodyFamily: "iA Writer Quattro V", monoFamily: "iA Writer Mono V",
                                   italic: .face, hasOpsz: false, onum: false, bodySize: 17, leading: 1.55, monoScale: 0.92, darkWeightBoost: 30)
    static let all = [flex, newsreader, quattro]
    static func named(_ id: String) -> ThemeSpec { all.first { $0.id == id } ?? flex }
}

/// Chrome always speaks in Google Sans Flex, regardless of the document theme.
enum ChromeFont {
    static func regular(_ size: CGFloat) -> NSFont { FontCache.font(.init(family: "Google Sans Flex", size: size, weight: 400, italic: false, slant: nil, opsz: true, onum: false)) }
    static func medium(_ size: CGFloat) -> NSFont { FontCache.font(.init(family: "Google Sans Flex", size: size, weight: 500, italic: false, slant: nil, opsz: true, onum: false)) }
}

/// Color tokens. Dynamic so they follow the effective appearance.
struct Palette {
    static func dynamic(_ light: String, _ dark: String, alpha: CGFloat = 1) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light).withAlphaComponent(alpha)
        }
    }
    static let bg = dynamic("FBFAF7", "1C1B19")
    static let bgElevated = dynamic("F3F1EC", "262522")
    static let fg = dynamic("1A1A1A", "E8E6E1")
    static let fgMuted = dynamic("8A867E", "8E8A82")
    static let fgFaint = dynamic("C9C5BC", "3A3833")
    static let accent = dynamic("4A25AA", "A199FF")
    static let commentFill = dynamic("EBB80A", "EBB80A", alpha: 0.22)
    static let commentFillDark = dynamic("EBB80A", "EBB80A", alpha: 0.18)
    static let commentText = dynamic("8C6A00", "F2D77A")
    static let added = dynamic("35974F", "5FBF78")
    static let removed = dynamic("B9283C", "E0606F")
    static let codeFill = dynamic("EFEDE7", "2A2925")
    static let inlineCodeFill = dynamic("EDEBE4", "2E2D29")
    static let selection = dynamic("4A25AA", "A199FF", alpha: 0.22)
    static let quoteRule = dynamic("4A25AA", "A199FF", alpha: 0.4)
}

extension NSColor {
    convenience init(hex: String) {
        var v: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&v)
        self.init(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }
}
