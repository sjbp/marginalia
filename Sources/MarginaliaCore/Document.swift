import Foundation

/// A Markdown file on disk plus what the app last saw of it. Pure model, no AppKit.
public final class Document {
    public let url: URL
    public private(set) var text: String
    public private(set) var lastLoaded: Date

    public init(url: URL) throws {
        self.url = url
        self.text = try Document.read(url)
        self.lastLoaded = Date()
    }

    public static func read(_ url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        if let s = String(data: data, encoding: .utf8) { return s }
        return String(decoding: data, as: UTF8.self)
    }
}
