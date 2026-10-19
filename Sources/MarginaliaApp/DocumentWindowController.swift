import AppKit
import MarginaliaCore

final class DocumentWindowController: NSWindowController, NSWindowDelegate {
    let doc: Document
    let textView: EditorTextView
    let scrollView: NSScrollView
    var onClose: (() -> Void)?
    var reading: Bool
    private(set) var loadMs: Double = 0

    init(document: Document, reading: Bool) {
        self.doc = document
        self.reading = reading
        let t0 = CFAbsoluteTimeGetCurrent()

        scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 860, height: 980))
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.borderType = .noBorder
        scrollView.autoresizingMask = [.width, .height]

        textView = EditorTextView(usingTextLayoutManager: true)
        textView.frame = scrollView.bounds
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: scrollView.bounds.width, height: CGFloat.greatestFiniteMagnitude)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.textContainerInset = NSSize(width: 48, height: 48)
        textView.font = NSFont(name: "Google Sans Flex", size: 17) ?? NSFont.systemFont(ofSize: 17)
        textView.string = doc.text
        scrollView.documentView = textView

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 860, height: 980),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .visible
        window.title = doc.url.lastPathComponent
        window.representedURL = doc.url
        window.contentView = scrollView
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.delegate = self
        assert(textView.textLayoutManager != nil, "TextKit 2 fell back to TextKit 1")
        loadMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000
    }

    required init?(coder: NSCoder) { fatalError() }

    func windowWillClose(_ notification: Notification) { onClose?() }

    func printPerf() {
        let launch = ProcessClock.msSinceProcessStart()
        print(String(format: "launch_to_first_paint_ms=%.1f", launch))
        print(String(format: "window_setup_ms=%.1f", loadMs))
        print("chars=\(doc.text.utf16.count)")
    }

    @objc func saveNow(_ sender: Any?) {}
    @objc func toggleReading(_ sender: Any?) {}
    @objc func cycleTheme(_ sender: Any?) {}
    @objc func zoomIn(_ sender: Any?) {}
    @objc func zoomOut(_ sender: Any?) {}
    @objc func zoomReset(_ sender: Any?) {}
}
