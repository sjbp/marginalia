import AppKit
import MarginaliaCore

final class DocumentWindowController: NSWindowController, NSWindowDelegate, NSTextStorageDelegate, NSTextViewDelegate {
    let doc: Document
    let textView: EditorTextView
    let scrollView: NSScrollView
    var onClose: (() -> Void)?
    var reading: Bool
    let styler: Styler
    private(set) var model: DocumentModel?
    private var flags: [UInt32] = []
    private var restylePending = false
    private var activeLine: Int? = nil
    private(set) var loadMs: Double = 0
    private(set) var parseMs: Double = 0
    private(set) var styleMs: Double = 0

    static var defaults: UserDefaults { .standard }

    init(document: Document, reading: Bool, themeOverride: String? = nil) {
        self.doc = document
        self.reading = reading
        let t0 = CFAbsoluteTimeGetCurrent()
        let themeId = themeOverride ?? Self.defaults.string(forKey: "theme") ?? "flex"
        let size = CGFloat(Self.defaults.double(forKey: "bodySize"))
        styler = Styler(theme: ThemeSpec.named(themeId), bodySize: size > 0 ? size : ThemeSpec.named(themeId).bodySize)

        scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 860, height: 980))
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = Palette.bg
        scrollView.borderType = .noBorder
        scrollView.autoresizingMask = [.width, .height]
        scrollView.scrollerStyle = .overlay

        textView = EditorTextView(usingTextLayoutManager: true)
        textView.frame = scrollView.bounds
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.containerSize = NSSize(width: scrollView.bounds.width, height: CGFloat.greatestFiniteMagnitude)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isRichText = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.drawsBackground = true
        textView.backgroundColor = Palette.bg
        textView.insertionPointColor = Palette.accent
        textView.selectedTextAttributes = [.backgroundColor: Palette.selection]
        textView.textContainerInset = NSSize(width: 48, height: 64)
        scrollView.documentView = textView

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 860, height: 980),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .visible
        window.title = document.url.lastPathComponent
        window.representedURL = document.url
        window.contentView = scrollView
        window.isReleasedWhenClosed = false
        window.backgroundColor = Palette.bg
        window.minSize = NSSize(width: 480, height: 320)
        window.center()
        super.init(window: window)
        window.delegate = self
        textView.delegate = self
        textView.textStorage?.delegate = self
        assert(textView.textLayoutManager != nil, "TextKit 2 fell back to TextKit 1")

        textView.string = document.text
        styler.isDark = window.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        reparseAndStyle()
        layoutColumn()
        loadMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: Layout

    private var lastColumnLeft: CGFloat = -1
    func layoutColumn() {
        let w = scrollView.contentSize.width
        let side: CGFloat = 40
        textView.textContainerInset = NSSize(width: side, height: 64)
        let available = w - 2 * side
        let left = max(0, ((available - styler.metrics.columnWidth) / 2).rounded())
        styler.columnLeft = left
        textView.metrics = styler.metrics
        if left != lastColumnLeft, model != nil {
            lastColumnLeft = left
            if let m = model, let storage = textView.textStorage { styler.apply(model: m, flags: flags, to: storage, lines: nil, activeLine: activeLine) }
        }
        lastColumnLeft = left
    }

    private var resizeTimer: Timer?
    func windowDidResize(_ notification: Notification) {
        resizeTimer?.invalidate()
        resizeTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: false) { [weak self] _ in self?.layoutColumn() }
    }
    func windowWillClose(_ notification: Notification) { onClose?() }

    // MARK: Parse + style

    func reparseAndStyle(lines: Range<Int>? = nil) {
        guard let storage = textView.textStorage else { return }
        let t0 = CFAbsoluteTimeGetCurrent()
        let m = MarkdownParser.parse(storage.string)
        let t1 = CFAbsoluteTimeGetCurrent()
        model = m
        textView.model = m
        flags = styler.paintFlags(model: m, length: storage.length)
        styler.apply(model: m, flags: flags, to: storage, lines: nil, activeLine: activeLine)
        let t2 = CFAbsoluteTimeGetCurrent()
        parseMs = (t1 - t0) * 1000; styleMs = (t2 - t1) * 1000
        textView.typingAttributes = styler.baseAttributes
        textView.needsDisplay = true
    }

    func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions, range editedRange: NSRange, changeInLength delta: Int) {
        guard editedMask.contains(.editedCharacters), !restylePending else { return }
        restylePending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.restylePending = false
            self.reparseAndStyle()
        }
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        guard let m = model, let storage = textView.textStorage else { return }
        let loc = textView.selectedRange().location
        let newActive = m.map.lineIndex(forUTF16: min(loc, max(0, storage.length)))
        guard newActive != activeLine else { return }
        let old = activeLine
        activeLine = newActive
        if let old, old < m.lines.count { styler.apply(model: m, flags: flags, to: storage, lines: old..<(old + 1), activeLine: activeLine) }
        if newActive < m.lines.count { styler.apply(model: m, flags: flags, to: storage, lines: newActive..<(newActive + 1), activeLine: activeLine) }
    }

    // MARK: Perf

    func scroll(toLine line: Int) {
        guard let m = model, line > 0, line <= m.lines.count else { return }
        let r = m.lines[line - 1].range
        textView.setSelectedRange(NSRange(location: r.location, length: 0))
        guard let tlm = textView.textLayoutManager, let tcs = textView.textContentStorage,
              let loc = tcs.location(tcs.documentRange.location, offsetBy: r.location),
              let upTo = NSTextRange(location: tcs.documentRange.location, end: loc) else { return }
        tlm.ensureLayout(for: upTo)
        var y: CGFloat = 0
        tlm.enumerateTextLayoutFragments(from: loc, options: [.ensuresLayout]) { f in y = f.layoutFragmentFrame.minY; return false }
        textView.layoutSubtreeIfNeeded()
        let target = NSPoint(x: 0, y: max(0, y + textView.textContainerInset.height - 64))
        scrollView.contentView.scroll(to: target)
        scrollView.reflectScrolledClipView(scrollView.contentView)
        if ProcessInfo.processInfo.environment["MARGINALIA_DEBUG"] != nil {
            fputs("scroll line=\(line) y=\(y) frameH=\(textView.frame.height) target=\(target) visible=\(textView.visibleRect)\n", stderr)
        }
    }

    func printPerf() {
        print(String(format: "launch_to_first_paint_ms=%.1f", ProcessClock.firstPaintMs))
        print(String(format: "window_setup_ms=%.1f", loadMs))
        print(String(format: "parse_ms=%.1f", parseMs))
        print(String(format: "style_ms=%.1f", styleMs))
        print("chars=\(doc.text.utf16.count) theme=\(styler.theme.id)")
    }

    // MARK: Actions

    @objc func saveNow(_ sender: Any?) {}
    @objc func toggleReading(_ sender: Any?) {}

    @objc func cycleTheme(_ sender: Any?) {
        let all = ThemeSpec.all
        let i = all.firstIndex(of: styler.theme) ?? 0
        setTheme(all[(i + 1) % all.count])
    }

    func setTheme(_ t: ThemeSpec) {
        styler.theme = t
        styler.bodySize = t.bodySize
        styler.invalidate()
        Self.defaults.set(t.id, forKey: "theme")
        Self.defaults.set(Double(t.bodySize), forKey: "bodySize")
        layoutColumn()
        reparseAndStyle()
    }

    @objc func zoomIn(_ sender: Any?) { setBodySize(styler.bodySize + 1) }
    @objc func zoomOut(_ sender: Any?) { setBodySize(styler.bodySize - 1) }
    @objc func zoomReset(_ sender: Any?) { setBodySize(styler.theme.bodySize) }

    func setBodySize(_ s: CGFloat) {
        styler.bodySize = max(11, min(32, s))
        styler.invalidate()
        Self.defaults.set(Double(styler.bodySize), forKey: "bodySize")
        layoutColumn()
        reparseAndStyle()
    }
}
