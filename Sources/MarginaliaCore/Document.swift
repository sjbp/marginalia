import Foundation

/// A Markdown file on disk plus what the app last saw of it. Pure model, no AppKit.
public final class Document {
    public let url: URL
    public private(set) var text: String
    /// Exactly what the app last wrote or loaded, for conflict detection and self-write filtering.
    public private(set) var lastSavedText: String
    public private(set) var lastLoaded: Date

    public init(url: URL) throws {
        self.url = url
        let t = try Document.read(url)
        self.text = t
        self.lastSavedText = t
        self.lastLoaded = Date()
    }

    public static func read(_ url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        if let s = String(data: data, encoding: .utf8) { return s }
        return String(decoding: data, as: UTF8.self)
    }

    /// Atomic write. Returns false when nothing changed.
    @discardableResult
    public func write(_ newText: String) throws -> Bool {
        guard newText != lastSavedText else { return false }
        try Data(newText.utf8).write(to: url, options: .atomic)
        text = newText
        lastSavedText = newText
        return true
    }

    /// Called after an external change was adopted into the buffer.
    public func adoptExternal(_ newText: String) {
        text = newText
        lastSavedText = newText
        lastLoaded = Date()
    }
}
