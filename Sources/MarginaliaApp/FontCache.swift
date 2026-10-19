import AppKit

struct FontKey: Hashable {
    var family: String
    var size: CGFloat
    var weight: CGFloat
    var italic: Bool
    var slant: CGFloat?
    var opsz: Bool
    var onum: Bool
}

/// Builds fonts through CoreText descriptors so variable axes (wght, opsz, slnt) are set explicitly
/// instead of relying on named instances. Caches by key.
enum FontCache {
    private static var cache: [FontKey: NSFont] = [:]
    private static var widthCache: [String: CGFloat] = [:]

    static let wght: NSNumber = 0x77676874
    static let opsz: NSNumber = 0x6F70737A
    static let slnt: NSNumber = 0x736C6E74

    static func font(_ key: FontKey) -> NSFont {
        if let f = cache[key] { return f }
        var attrs: [CFString: Any] = [kCTFontFamilyNameAttribute: key.family]
        var variation: [NSNumber: NSNumber] = [wght: NSNumber(value: Double(key.weight))]
        if key.opsz { variation[opsz] = NSNumber(value: Double(key.size)) }
        if key.italic, let s = key.slant { variation[slnt] = NSNumber(value: Double(s)) }
        attrs[kCTFontVariationAttribute] = variation
        if key.italic, key.slant == nil {
            attrs[kCTFontTraitsAttribute] = [kCTFontSymbolicTrait: CTFontSymbolicTraits.traitItalic.rawValue]
        }
        var features: [[CFString: Any]] = [
            [kCTFontOpenTypeFeatureTag: "kern", kCTFontOpenTypeFeatureValue: 1],
            [kCTFontOpenTypeFeatureTag: "liga", kCTFontOpenTypeFeatureValue: 1],
            [kCTFontOpenTypeFeatureTag: "calt", kCTFontOpenTypeFeatureValue: 1],
        ]
        if key.onum { features.append([kCTFontOpenTypeFeatureTag: "onum", kCTFontOpenTypeFeatureValue: 1]) }
        attrs[kCTFontFeatureSettingsAttribute] = features
        let desc = CTFontDescriptorCreateWithAttributes(attrs as CFDictionary)
        var font = CTFontCreateWithFontDescriptor(desc, key.size, nil) as NSFont
        if (font.familyName ?? "") != key.family {
            NSLog("font fallback: wanted \(key.family) got \(font.familyName ?? "?")")
            font = key.family.lowercased().contains("mono") || key.family.contains("Code")
                ? NSFont.monospacedSystemFont(ofSize: key.size, weight: .regular)
                : NSFont.systemFont(ofSize: key.size)
        }
        cache[key] = font
        return font
    }

    /// Width of a short string in a font, cached. Used for hanging prefixes.
    static func width(of s: String, in font: NSFont) -> CGFloat {
        let k = "\(font.fontName)|\(font.pointSize)|\(s)"
        if let w = widthCache[k] { return w }
        let w = (s as NSString).size(withAttributes: [.font: font]).width
        widthCache[k] = w
        return w
    }

    static func advance(of font: NSFont) -> CGFloat { width(of: "0", in: font) }
}
