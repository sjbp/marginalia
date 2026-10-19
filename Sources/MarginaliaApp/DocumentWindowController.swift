import AppKit
import MarginaliaCore

struct ChangeMark {
    enum Kind { case added, removed, conflict }
    var line: Int
    var kind: Kind
    var at: Date
}

final class DocumentWindowController: NSWindowController, NSWindowDelegate, NSTextStorageDelegate, NSTextViewDelegate {
    let doc: Document
    let textView: EditorTextView
    let scrollView: NSScrollView
    let statusLine = StatusLine(frame: .zero)
    private(set) var margin: CommentMargin!
    private var overlays: ReadingOverlays!
    private(set) lazy var palette = CommandPalette(controller: self)
    private(set) lazy var formatBar = FormatBar(textView: textView)
    let modeToggle = ModeToggle(frame: .zero)
    var authorTag: String { Self.defaults.string(forKey: "authorTag") ?? "sebo" }
    var onClose: (() -> Void)?
    var sourceMode: Bool
    let styler: Styler
    private(set) var model: DocumentModel?
    private var flags: [UInt32] = []
    private var restylePending = false
    private var activeLine: Int? = nil
    private var restoreOffset = 0
    private var saveTimer: Timer?
    private var memoryTimer: Timer?
    private var statsTimer: Timer?
    private var watcher: FileWatcher?
    private(set) var changeMarks: [ChangeMark] = []
    private var marksTimer: Timer?
    private let openedAt = Date()
    private(set) var loadMs: Double = 0
    private(set) var parseMs: Double = 0
    private(set) var styleMs: Double = 0
    private(set) var reloadMs: Double = 0

    static var defaults: UserDefaults { .standard }
    static var markLifetime: TimeInterval { let v = UserDefaults.standard.double(forKey: "changeFade"); return v > 0 ? v : 8 }

    init(document: Document, sourceMode: Bool, themeOverride: String? = nil) {
        self.doc = document
        self.sourceMode = sourceMode
        let t0 = CFAbsoluteTimeGetCurrent()
        let themeId = themeOverride ?? Self.defaults.string(forKey: "theme") ?? "flex"
        let size = CGFloat(Self.defaults.double(forKey: "bodySize"))
        styler = Styler(theme: ThemeSpec.named(themeId), bodySize: size > 0 ? size : ThemeSpec.named(themeId).bodySize)

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 860, height: 980))
        scrollView = NSScrollView(frame: container.bounds)
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = Palette.bg
        scrollView.borderType = .noBorder
        scrollView.autoresizingMask = [.width, .height]
        scrollView.scrollerStyle = .overlay
        container.addSubview(scrollView)
        statusLine.frame = container.bounds
        statusLine.autoresizingMask = [.width, .height]
        container.addSubview(statusLine)

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
        textView.selectedTextAttributes = [.backgroundColor: NSColor.clear]   // drawn by EditorTextView on the text extents
        textView.textContainerInset = NSSize(width: 40, height: 64)
        scrollView.documentView = textView

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 860, height: 980),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .visible
        window.title = document.url.lastPathComponent
        window.representedURL = document.url
        window.contentView = container
        window.isReleasedWhenClosed = false
        window.backgroundColor = Palette.bg
        window.minSize = NSSize(width: 480, height: 320)
        if let screen = NSScreen.main, screen.visibleFrame.width >= 1300 {
            window.setContentSize(NSSize(width: 1180, height: min(980, screen.visibleFrame.height - 40)))
        }
        window.center()
        let memory = WindowMemory.entry(for: document.url.path)
        if let f = memory?.frame, NSScreen.screens.contains(where: { $0.visibleFrame.intersects(f) }) { window.setFrame(f, display: false) }
        super.init(window: window)
        restoreOffset = memory?.offset ?? 0
        window.delegate = self
        textView.delegate = self
        textView.controller = self
        textView.textStorage?.delegate = self
        assert(textView.textLayoutManager != nil, "TextKit 2 fell back to TextKit 1")

        margin = CommentMargin(textView: textView)
        textView.margin = margin
        overlays = ReadingOverlays(textView: textView)
        textView.overlays = overlays
        textView.flagsProvider = { [weak self] in self?.flags ?? [] }
        textView.hiddenProvider = { [weak self] i in self?.isHiddenChar(at: i) ?? false }
        textView.formatBar = formatBar
        modeToggle.sourceMode = sourceMode
        modeToggle.onToggle = { [weak self] on in self?.setSourceMode(on) }
        container.addSubview(modeToggle)
        modeToggle.frame.origin = NSPoint(x: container.bounds.width - modeToggle.frame.width - 16, y: 14)
        modeToggle.autoresizingMask = [.minXMargin, .maxYMargin]
        statusLine.trailingInset = modeToggle.frame.width + 32
        window.subtitle = document.url.deletingLastPathComponent().path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
        overlays.onActivate = { [weak self] line in
            guard let self, let m = self.model, line < m.lines.count else { return }
            self.setSourceMode(true)
            self.textView.setSelectedRange(NSRange(location: m.lines[line].range.location, length: 0))
            self.window?.makeFirstResponder(self.textView)
        }
        styler.baseURL = document.url.deletingLastPathComponent()
        wireMargin()
        var tp = CFAbsoluteTimeGetCurrent()
        ProcessClock.phase("setup.views", t0)
        textView.string = document.text
        ProcessClock.phase("setup.setString", tp); tp = CFAbsoluteTimeGetCurrent()
        styler.isDark = window.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        layoutColumn(restyle: false)
        reparseAndStyle()
        ProcessClock.phase("setup.parseStyle", tp)
        tp = CFAbsoluteTimeGetCurrent()
        watcher = FileWatcher(url: document.url) { [weak self] in self?.externalChanged() }
        ProcessClock.phase("setup.watcher", tp)
        if sourceMode { styler.mode = .source; textView.isRendered = false; reparseAndStyle() }
        loadMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000
    }

    required init?(coder: NSCoder) { fatalError() }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        if restoreOffset > 0 {
            let off = restoreOffset
            restoreOffset = 0
            DispatchQueue.main.async { [weak self] in self?.scroll(toOffset: off, topInset: 0) }
        }
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(scrolled(_:)), name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
    }

    @objc func scrolled(_ n: Notification) {
        margin.layout()
        if styler.mode == .rendered { overlays.layout(model: model, metrics: styler.metrics, activeLines: styler.activeLines) }
        // Only a user gesture cancels settling; TextKit's own viewport adjustments must not.
        if !programmaticScroll, let e = NSApp.currentEvent,
           [.scrollWheel, .leftMouseDown, .leftMouseDragged, .keyDown, .magnify, .swipe].contains(e.type) { settleToken += 1 }
        scheduleMemory()
        guard Date().timeIntervalSince(openedAt) > 1.5 else { return }
        statsTimer?.invalidate()
        statsTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: false) { [weak self] _ in
            guard let self, self.statusLine.alphaValue < 0.5 else { return }
            self.statusLine.show(ReadingStats.describe(self.textView.string) + " · saved", for: 1.6)
        }
    }

    func windowDidMove(_ notification: Notification) { scheduleMemory() }

    private func scheduleMemory() {
        memoryTimer?.invalidate()
        memoryTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            guard let self else { return }
            if !self.resizing { self.lastAnchor = self.firstVisible() }
            self.storeMemory()
        }
    }

    func storeMemory() {
        guard let w = window else { return }
        WindowMemory.store(.init(frame: w.frame, offset: firstVisibleOffset()), for: doc.url.path)
    }

    /// Character offset of the first visible line and how far its top sits above the viewport top.
    func firstVisible() -> (offset: Int, delta: CGFloat) {
        let top = scrollView.contentView.bounds.minY
        let inset = textView.textContainerInset
        if top <= inset.height { return (0, top - inset.height) }
        let m = styler.metrics
        let probe = NSPoint(x: inset.width + m.columnLeft + m.textEdge + 2, y: top + 2)
        let idx = textView.characterIndexForInsertion(at: probe)
        guard idx < textView.string.utf16.count else { return (0, 0) }
        let lineStart = (textView.string as NSString).lineRange(for: NSRange(location: idx, length: 0)).location
        let lt = lineTop(ofOffset: lineStart) ?? top
        return (lineStart, top - lt)
    }

    func firstVisibleOffset() -> Int { firstVisible().offset }

    // MARK: Layout

    private var lastColumnLeft: CGFloat = -1
    static let cardGutter: CGFloat = 24
    static let maxLeftWithComments: CGFloat = 112
    private var cardsFit = false
    func layoutColumn(restyle: Bool = true) {
        let w = scrollView.contentSize.width
        let side: CGFloat = 40
        textView.textContainerInset = NSSize(width: side, height: 64)
        let available = w - 2 * side
        let cw = styler.metrics.columnWidth
        let centered = max(0, ((available - cw) / 2).rounded())
        let hasComments = !(model?.comments.isEmpty ?? true)
        let needRight = ThreadCard.minWidth + Self.cardGutter * 2
        var left = centered
        var cards = false
        cardsFit = available >= cw + needRight
        if hasComments, cardsFit {
            cards = true
            // A commented document reads left-biased, like a page with its margin notes: cap the left margin
            // and let the cards use the room that frees up.
            left = min(centered, available - cw - needRight, Self.maxLeftWithComments)
            let room = available - cw - left - Self.cardGutter * 2
            ThreadCard.width = max(ThreadCard.minWidth, min(ThreadCard.maxWidth, room))
        }
        styler.columnLeft = left
        textView.metrics = styler.metrics
        margin.enabled = cards
        margin.x = side + left + cw + Self.cardGutter
        if restyle, left != lastColumnLeft, lastColumnLeft >= 0, let m = model, let storage = textView.textStorage {
            styler.apply(model: m, flags: flags, to: storage, lines: nil, activeLine: activeLine)
        }
        lastColumnLeft = left
        if restyle, let m = model { margin.update(comments: m.comments) }
    }

    private var resizeTimer: Timer?
    /// Last settled reading position, refreshed after every scroll; used to re-anchor after resizes.
    private var lastAnchor: (offset: Int, delta: CGFloat)?
    private var resizing = false
    func windowDidResize(_ notification: Notification) {
        resizing = true
        resizeTimer?.invalidate()
        resizeTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.layoutColumn()
            if let a = self.lastAnchor { self.scroll(toOffset: a.offset, topInset: -a.delta) }
            self.resizing = false
            self.scheduleMemory()
        }
    }

    func windowWillClose(_ notification: Notification) {
        watcher?.stop()
        onClose?()
        DistributedNotificationCenter.default().postNotificationName(Notification.Name("com.sjbp.marginalia.windowClosed"), object: nil,
                                                                     userInfo: ["path": doc.url.standardizedFileURL.path], deliverImmediately: true)
    }

    // MARK: Parse + style

    private var parseGeneration = 0
    static let backgroundParseThreshold = 200_000
    static let chunkedStyleThreshold = 800   // lines

    func reparseAndStyle() {
        guard let storage = textView.textStorage else { return }
        parseGeneration += 1
        let gen = parseGeneration
        var text = storage.string
        text.makeContiguousUTF8()   // bridged NSString → native UTF-8 once, everything downstream gets fast
        if text.utf16.count > Self.backgroundParseThreshold, model != nil {
            DispatchQueue.global(qos: .userInitiated).async {
                let t0 = CFAbsoluteTimeGetCurrent()
                let m = MarkdownParser.parse(text)
                let ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000
                DispatchQueue.main.async { [weak self] in
                    guard let self, gen == self.parseGeneration, let st = self.textView.textStorage, st.length == m.map.utf16Count else { return }
                    self.parseMs = ms
                    self.finishStyle(m, storage: st, generation: gen)
                }
            }
            return
        }
        let t0 = CFAbsoluteTimeGetCurrent()
        let m = MarkdownParser.parse(text)
        parseMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000
        finishStyle(m, storage: storage, generation: gen)
    }

    private func finishStyle(_ m: DocumentModel, storage: NSTextStorage, generation gen: Int) {
        let t1 = CFAbsoluteTimeGetCurrent()
        model = m
        textView.model = m
        flags = styler.paintFlags(model: m, length: storage.length)
        layoutColumn(restyle: false)   // column may shift to make room for cards; decide before the single style pass
        styler.activeLines = revealsCaretBlock ? activeBlock(for: textView.selectedRange(), in: m) : 0..<0
        if styler.mode == .rendered { rebuildOverlays(m) }
        if m.lines.count <= Self.chunkedStyleThreshold || window == nil {
            styler.apply(model: m, flags: flags, to: storage, lines: nil, activeLine: activeLine)
        } else {
            // Visible region now, the rest in slices so the first paint and typing stay fast.
            let (t, b) = window?.isVisible == true ? visibleOffsets() : (0, 0)
            let lo = max(0, m.map.lineIndex(forUTF16: min(t, storage.length)) - 100)
            let hi = min(m.lines.count, m.map.lineIndex(forUTF16: min(b, storage.length)) + 300)
            let first = lo < hi ? lo..<hi : 0..<min(400, m.lines.count)
            styler.apply(model: m, flags: flags, to: storage, lines: first, activeLine: activeLine)
            styleRemaining(model: m, storage: storage, done: first, generation: gen)
        }
        styleMs = (CFAbsoluteTimeGetCurrent() - t1) * 1000
        if styler.mode == .rendered { overlays.layout(model: m, metrics: styler.metrics, activeLines: styler.activeLines) }
        textView.typingAttributes = styler.baseAttributes
        if margin.cards.isEmpty, !m.comments.isEmpty, window?.isVisible != true {
            // First load: let the text paint first, cards a frame later.
            DispatchQueue.main.async { [weak self] in if let self, self.model?.map.utf16Count == m.map.utf16Count { self.margin.update(comments: m.comments) } }
        } else {
            margin.update(comments: m.comments)
        }
        textView.needsDisplay = true
    }

    private func styleRemaining(model m: DocumentModel, storage: NSTextStorage, done: Range<Int>, generation gen: Int) {
        let total = m.lines.count
        var slices: [Range<Int>] = []
        var i = done.upperBound
        while i < total { slices.append(i..<min(total, i + 600)); i += 600 }
        i = done.lowerBound
        while i > 0 { let lo = max(0, i - 600); slices.append(lo..<i); i = lo }
        func next(_ k: Int) {
            guard k < slices.count, gen == self.parseGeneration, storage.length == m.map.utf16Count else { return }
            self.styler.apply(model: m, flags: self.flags, to: storage, lines: slices[k], activeLine: self.activeLine)
            DispatchQueue.main.async { next(k + 1) }
        }
        DispatchQueue.main.async { next(0) }
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

    private var normalizingCaret = false
    func textViewDidChangeSelection(_ notification: Notification) {
        guard let m = model, let storage = textView.textStorage, m.map.utf16Count == storage.length else { return }
        var sel = textView.selectedRange()
        // The caret never rests inside or at the very start of a hidden run (zero-size syntax).
        if styler.mode == .rendered, sel.length == 0, !normalizingCaret, isHiddenChar(at: sel.location) {
            let ns = storage.string as NSString
            let lineStart = ns.lineRange(for: NSRange(location: sel.location, length: 0)).location
            if sel.location == lineStart || isHiddenChar(at: sel.location - 1) {
                var c = sel.location
                while c < storage.length, isHiddenChar(at: c) { c += 1 }
                normalizingCaret = true
                textView.setSelectedRange(NSRange(location: c, length: 0))
                normalizingCaret = false
                sel = textView.selectedRange()
            }
        }
        let act = m.comments.firstIndex { NSLocationInRange(sel.location, $0.range) || ($0.anchorMarkupRange.map { NSLocationInRange(sel.location, $0) } ?? false) }
        if act != margin.activeIndex { margin.activeIndex = act; margin.layout(); textView.needsDisplay = true }
        textView.needsDisplay = true   // selection is drawn in drawBackground
        if sel.length == 0 { formatBar.hide() }
        else if let ev = NSApp.currentEvent, ev.type == .keyDown || ev.type == .flagsChanged { formatBar.update(selection: sel) }
        else if NSApp.currentEvent == nil { formatBar.update(selection: sel) }   // scripted / programmatic selection
        guard revealsCaretBlock else { return }
        let newBlock = activeBlock(for: sel, in: m)
        let oldBlock = styler.activeLines
        guard newBlock != oldBlock else { return }
        styler.activeLines = newBlock
        styler.apply(model: m, flags: flags, to: storage, lines: oldBlock, activeLine: nil)
        styler.apply(model: m, flags: flags, to: storage, lines: newBlock, activeLine: nil)
        overlays.layout(model: m, metrics: styler.metrics, activeLines: newBlock)
        margin.layout()
        textView.needsDisplay = true
    }

    // MARK: Scrolling

    func scroll(toLine line: Int) {
        guard let m = model, line > 0, line <= m.lines.count else { return }
        scroll(toOffset: m.lines[line - 1].range.location, topInset: 0, moveCaret: true)
    }

    /// Scrolls so the line containing `offset` sits `topInset` points below the top edge.
    /// TextKit 2 estimates the height of text it has not laid out, so positions computed from
    /// fragment frames drift. Bring the range on screen first, then correct against its real
    /// on-screen rect until it stops moving.
    func scroll(toOffset offset: Int, topInset: CGFloat, moveCaret: Bool = false) {
        let length = textView.string.utf16.count
        let off = min(offset, length)
        if moveCaret { textView.setSelectedRange(NSRange(location: off, length: 0)) }
        let clip = scrollView.contentView
        if off == 0 {
            clip.scroll(to: NSPoint(x: 0, y: max(0, -topInset)))
            scrollView.reflectScrolledClipView(clip)
            return
        }
        programmaticScroll = true
        correctScroll(offset: off, topInset: topInset)
        correctScroll(offset: off, topInset: topInset)
        programmaticScroll = false
        // TextKit 2 re-estimates heights after the viewport moves; verify on later turns until stable.
        settleToken += 1
        settle(offset: off, topInset: topInset, token: settleToken, attempts: 5)
    }

    private var settleToken = 0
    private var programmaticScroll = false

    /// Re-checks the anchor after display passes, when TextKit 2 has replaced estimates with layout.
    private func settle(offset: Int, topInset: CGFloat, token: Int, attempts: Int) {
        let delays: [TimeInterval] = [0.02, 0.08, 0.2, 0.45, 0.8]
        guard attempts > 0, attempts <= delays.count else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + delays[delays.count - attempts]) { [weak self] in
            guard let self, token == self.settleToken else { return }
            self.programmaticScroll = true
            self.correctScroll(offset: offset, topInset: topInset)
            self.programmaticScroll = false
            self.settle(offset: offset, topInset: topInset, token: token, attempts: attempts - 1)
        }
    }

    /// Character offsets at the top and bottom of the viewport, by hit test (the only geometry TextKit 2 guarantees).
    func visibleOffsets() -> (top: Int, bottom: Int) {
        let b = scrollView.contentView.bounds
        let m = styler.metrics
        let x = textView.textContainerInset.width + m.columnLeft + m.textEdge + 2
        let top = textView.characterIndexForInsertion(at: NSPoint(x: x, y: b.minY + 2))
        let bottom = textView.characterIndexForInsertion(at: NSPoint(x: x, y: b.maxY - 2))
        return (top, bottom)
    }

    /// Moves the clip view so the line is where it should be. Returns true when it had to move.
    /// Estimated geometry is untrustworthy, so first make the target genuinely visible (verified by
    /// hit test), then align it using its real on-screen rect.
    @discardableResult
    private func correctScroll(offset: Int, topInset: CGFloat) -> Bool {
        let clip = scrollView.contentView
        let ns = textView.string as NSString
        let targetLine = ns.lineRange(for: NSRange(location: offset, length: 0))
        var moved = false
        for _ in 0..<8 {
            let (t, b) = visibleOffsets()
            let visible = t <= targetLine.location + targetLine.length && b >= targetLine.location
            if visible { break }
            textView.scrollRangeToVisible(NSRange(location: offset, length: 0))
            textView.textLayoutManager?.textViewportLayoutController.layoutViewport()
            textView.layoutSubtreeIfNeeded()
            moved = true
        }
        guard let top = lineTop(ofOffset: offset) else { return moved }
        let want = max(0, top - topInset)
        if ProcessInfo.processInfo.environment["MARGINALIA_DEBUG"] != nil {
            let (t, _) = visibleOffsets()
            fputs("correct off=\(offset) hitTop=\(t) lineTop=\(Int(top)) bounds=\(Int(clip.bounds.minY)) want=\(Int(want))\n", stderr)
        }
        if abs(clip.bounds.minY - want) < 0.5 { return moved }
        clip.scroll(to: NSPoint(x: 0, y: want))
        scrollView.reflectScrolledClipView(clip)
        textView.textLayoutManager?.textViewportLayoutController.layoutViewport()
        return true
    }

    /// Top of the line containing `offset`, in clip-view (document) coordinates, from its real on-screen rect.
    func lineTop(ofOffset offset: Int) -> CGFloat? {
        guard let w = window else { return nil }
        // Measure the whole line, not one character: in rendered mode the first characters may be hidden (0.1 pt) runs.
        let ns = textView.string as NSString
        let lr = ns.lineRange(for: NSRange(location: min(offset, max(0, ns.length - 1)), length: 0))
        let r = textView.firstRect(forCharacterRange: NSRange(location: lr.location, length: max(1, lr.length)), actualRange: nil)
        guard r.width.isFinite, r.height > 0 else { return nil }
        let inWindow = w.convertFromScreen(r)
        let inClip = scrollView.contentView.convert(inWindow, from: nil)
        return inClip.minY
    }

    // MARK: External changes

    func externalChanged() {
        let t0 = CFAbsoluteTimeGetCurrent()
        var tp = t0
        var ph: [(String, Double)] = []
        func lap(_ n: String) { ph.append((n, (CFAbsoluteTimeGetCurrent() - tp) * 1000)); tp = CFAbsoluteTimeGetCurrent() }
        guard let disk = try? Document.read(doc.url) else { return }
        guard disk != doc.lastSavedText else { return }
        lap("read")
        guard let storage = textView.textStorage, let oldModel = model else { return }
        var buffer = storage.string
        buffer.makeContiguousUTF8()
        let base = doc.lastSavedText
        var newText = disk
        var conflicts: [Int] = []
        if buffer != base {
            let m = ThreeWayMerge.merge(base: base, ours: buffer, theirs: disk)
            newText = m.text; conflicts = m.conflictLines
        }
        guard newText != buffer else {
            if newText != disk { try? doc.write(newText) } else { doc.adoptExternal(newText) }
            return
        }
        lap("merge")
        let diff = LineDiff.diff(old: buffer, new: newText)
        let oldCount = oldModel.lines.count
        lap("diff")

        // Remember where the reader is.
        let caret = textView.selectedRange().location
        let caretLine = oldModel.map.lineIndex(forUTF16: min(caret, storage.length))
        let caretCol = caret - oldModel.lines[caretLine].range.location
        let (topOff, delta) = firstVisible()
        let topLine = oldModel.map.lineIndex(forUTF16: topOff)

        // Replace only the span that differs, so TextKit invalidates little and content above stays put.
        let oldNS = buffer as NSString, newNS = newText as NSString
        var pfx = 0
        let minLen = min(oldNS.length, newNS.length)
        while pfx < minLen, oldNS.character(at: pfx) == newNS.character(at: pfx) { pfx += 1 }
        if pfx > 0, UTF16.isLeadSurrogate(oldNS.character(at: pfx - 1)) { pfx -= 1 }
        var oEnd = oldNS.length, nEnd = newNS.length
        while oEnd > pfx, nEnd > pfx, oldNS.character(at: oEnd - 1) == newNS.character(at: nEnd - 1) { oEnd -= 1; nEnd -= 1 }
        if oEnd < oldNS.length, UTF16.isTrailSurrogate(oldNS.character(at: oEnd)) { oEnd += 1; nEnd += 1 }
        let changeBelowViewport = pfx > topOff
        lap("anchor+prefix")
        saveTimer?.invalidate()
        storage.beginEditing()
        storage.replaceCharacters(in: NSRange(location: pfx, length: oEnd - pfx), with: newNS.substring(with: NSRange(location: pfx, length: nEnd - pfx)))
        storage.endEditing()
        lap("replace")
        textView.undoManager?.removeAllActions()
        restylePending = false
        reparseAndStyle()
        lap("parseStyle")
        if newText != disk { try? doc.write(newText) } else { doc.adoptExternal(newText) }
        guard let newModel = model else { return }

        // Restore caret and scroll by anchoring to surviving lines.
        if caret >= pfx {
            let newCaretLine = min(LineDiff.mapLine(caretLine, diff, oldCount: oldCount), newModel.lines.count - 1)
            let cl = newModel.lines[newCaretLine]
            textView.setSelectedRange(NSRange(location: cl.range.location + min(caretCol, cl.range.length), length: 0))
        }
        if !changeBelowViewport {
            let newTopLine = min(LineDiff.mapLine(topLine, diff, oldCount: oldCount), newModel.lines.count - 1)
            scroll(toOffset: newModel.lines[newTopLine].range.location, topInset: -delta)
        }
        lap("caretScroll")

        // Marks.
        let now = Date()
        var marks: [ChangeMark] = diff.changedNewLines.map { ChangeMark(line: $0, kind: .added, at: now) }
        // A removal right before a changed line is a modification; the green bar already says so.
        marks += diff.removedBefore.filter { !diff.changedNewLines.contains($0) }.map { ChangeMark(line: $0, kind: .removed, at: now) }
        for c in conflicts { marks.append(ChangeMark(line: c, kind: .conflict, at: now)) }
        changeMarks = marks.sorted { $0.line < $1.line }
        textView.needsDisplay = true
        scheduleMarkFade()

        reloadMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000
        let n = diff.changedNewLines.count + diff.removedBefore.count
        if !conflicts.isEmpty {
            statusLine.show("conflict on \(conflicts.count) line\(conflicts.count == 1 ? "" : "s"), yours kept", for: 5, accent: true)
        } else if let first = changeMarks.first, !isLineVisible(first.line) {
            statusLine.show("updated · \(n) line\(n == 1 ? "" : "s") ↓", for: 4, accent: true) { [weak self] in self?.jumpToChange(forward: true) }
        } else {
            statusLine.show("updated · \(n) line\(n == 1 ? "" : "s")", for: 3)
        }
        lap("marks+status")
        NSLog("reload %.1f ms, %d lines changed  [%@]", reloadMs, n, ph.map { String(format: "%@ %.1f", $0.0, $0.1) }.joined(separator: ", "))
    }

    func isLineVisible(_ line: Int) -> Bool {
        guard let m = model, line < m.lines.count, let tlm = textView.textLayoutManager, let tcs = textView.textContentStorage,
              let loc = tcs.location(tcs.documentRange.location, offsetBy: m.lines[line].range.location) else { return true }
        var y: CGFloat = -1
        tlm.enumerateTextLayoutFragments(from: loc, options: [.ensuresLayout]) { f in y = f.layoutFragmentFrame.minY; return false }
        let v = scrollView.contentView.bounds
        let yy = y + textView.textContainerInset.height
        return yy >= v.minY && yy <= v.maxY - 20
    }

    private func scheduleMarkFade() {
        marksTimer?.invalidate()
        marksTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            guard let self else { return }
            let now = Date()
            self.changeMarks.removeAll { now.timeIntervalSince($0.at) > Self.markLifetime }
            self.textView.needsDisplay = true
            if self.changeMarks.isEmpty { self.marksTimer?.invalidate(); self.marksTimer = nil }
        }
    }

    func clearChangeMarks() {
        changeMarks.removeAll()
        marksTimer?.invalidate(); marksTimer = nil
        textView.needsDisplay = true
    }

    @objc func nextChange(_ sender: Any?) { jumpToChange(forward: true) }
    @objc func previousChange(_ sender: Any?) { jumpToChange(forward: false) }

    func jumpToChange(forward: Bool) {
        guard let m = model, !changeMarks.isEmpty else { return }
        let cur = m.map.lineIndex(forUTF16: textView.selectedRange().location)
        let target = forward ? changeMarks.first { $0.line > cur } ?? changeMarks.first : changeMarks.last { $0.line < cur } ?? changeMarks.last
        guard let t = target, t.line < m.lines.count else { return }
        scroll(toOffset: m.lines[t.line].range.location, topInset: scrollView.contentSize.height * 0.3, moveCaret: true)
    }

    // MARK: Perf

    func printPerf() {
        print(String(format: "launch_to_first_paint_ms=%.1f", ProcessClock.firstPaintMs))
        print(String(format: "window_setup_ms=%.1f", loadMs))
        print(String(format: "parse_ms=%.1f", parseMs))
        print(String(format: "style_ms=%.1f", styleMs))
        print(String(format: "fonts_ms=%.1f", FontLoader.registerMs))
        print("marks: " + ProcessClock.marks.map { String(format: "%@=%.0f", $0.0, $0.1) }.joined(separator: " "))
        print("phases: " + ProcessClock.phases.map { String(format: "%@=%.1f", $0.0, $0.1) }.joined(separator: " "))
        print("chars=\(doc.text.utf16.count) theme=\(styler.theme.id)")
    }

    // MARK: Saving

    func textDidChange(_ notification: Notification) {
        formatBar.hide()
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: false) { [weak self] _ in self?.saveNow(nil) }
    }

    @objc func saveNow(_ sender: Any?) {
        saveTimer?.invalidate(); saveTimer = nil
        do { try doc.write(textView.string) } catch { NSLog("save failed: \(error)") }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool { saveNow(nil); storeMemory(); return true }

    // MARK: Actions

    @objc func revealInFinder(_ sender: Any?) { NSWorkspace.shared.activateFileViewerSelecting([doc.url]) }
    @objc func copyPath(_ sender: Any?) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(doc.url.path, forType: .string) }
    @objc func printDocument(_ sender: Any?) { textView.printView(sender) }
    func wireMargin() {
        margin.onSelect = { [weak self] c in
            guard let self else { return }
            let r = c.anchorRange ?? c.range
            self.withScrollPreserved(editAt: Int.max) {
                self.textView.setSelectedRange(c.anchorRange != nil ? r : NSRange(location: r.location, length: 0))
                self.window?.makeFirstResponder(self.textView)
            }
        }
        margin.onResolve = { [weak self] c in self?.resolve(c) }
        margin.onReply = { [weak self] c in self?.reply(to: c) }
        margin.onCommit = { [weak self] c, text in
            guard let self else { return }
            if text.isEmpty { self.resolve(c); return }
            let who = c.author ?? self.authorTag
            let rep = "{>>@\(who): \(text)<<}"
            let keep = self.textView.selectedRange()
            self.withScrollPreserved(editAt: c.range.location) {
                self.textView.perform(SmartEdit.Edit(range: c.range, replacement: rep, caret: c.range.location + (rep as NSString).length), select: keep)
                self.window?.makeFirstResponder(self.textView)
            }
        }
        margin.onReplyText = { [weak self] thread, text in
            guard let self, let last = thread.last else { return }
            let at = last.range.location + last.range.length
            let rep = "{>>@\(self.authorTag): \(text)<<}"
            let keep = self.textView.selectedRange()
            self.withScrollPreserved(editAt: at) {
                self.textView.perform(SmartEdit.Edit(range: NSRange(location: at, length: 0), replacement: rep, caret: at), select: keep)
                self.window?.makeFirstResponder(self.textView)
            }
        }
        margin.onResolveThread = { [weak self] thread in self?.resolveThread(thread) }
        formatBar.onComment = { [weak self] in self?.addComment(nil) }
    }

    func resolveThread(_ thread: [Comment]) {
        guard let first = thread.first else { return }
        let ns = textView.string as NSString
        var edits: [(NSRange, String)] = thread.map { ($0.range, "") }
        if let hl = first.anchorMarkupRange, let anchor = first.anchorRange { edits.append((hl, ns.substring(with: anchor))) }
        edits.sort { $0.0.location > $1.0.location }
        let keep = textView.selectedRange()
        let lowest = edits.map { $0.0.location }.min() ?? 0
        withScrollPreserved(editAt: lowest) {
            for (r, rep) in edits { textView.perform(SmartEdit.Edit(range: r, replacement: rep, caret: r.location), select: NSRange(location: min(keep.location, r.location), length: 0)) }
            window?.makeFirstResponder(textView)
        }
    }

    @objc func addComment(_ sender: Any?) {
        let sel = textView.selectedRange()
        let ns = textView.string as NSString
        let tag = "{>>@\(authorTag): <<}"
        formatBar.hide()
        if sel.length > 0 {
            let inner = ns.substring(with: sel)
            let rep = "{==\(inner)==}" + tag
            withScrollPreserved(editAt: sel.location) { textView.perform(SmartEdit.Edit(range: sel, replacement: rep, caret: sel.location + 3), select: NSRange(location: sel.location + 3, length: sel.length)) }
            margin.editSoon(threadStart: sel.location, initial: "")
        } else {
            // Standalone: at the end of the current paragraph.
            let para = ns.paragraphRange(for: sel)
            var end = para.location + para.length
            if end > para.location, ns.character(at: end - 1) == 0x0A { end -= 1 }
            let needsSpace = end > para.location && ns.character(at: end - 1) != 0x20
            let rep = (needsSpace ? " " : "") + tag
            withScrollPreserved(editAt: end) { textView.perform(SmartEdit.Edit(range: NSRange(location: end, length: 0), replacement: rep, caret: end), select: sel) }
            margin.editSoon(threadStart: end + (needsSpace ? 1 : 0), initial: "")
        }
        if !cardsFit { statusLine.show("comment added in the text, widen the window for cards", for: 2.5) }
    }

    func resolve(_ c: Comment) {
        guard let m = model else { return }
        let ns = textView.string as NSString
        // Remove the comment; unwrap the highlight only if no other comment still hangs off it.
        var edits: [(NSRange, String)] = [(c.range, "")]
        if let hl = c.anchorMarkupRange, let anchor = c.anchorRange {
            let siblings = m.comments.filter { $0.anchorMarkupRange == hl && $0.range != c.range }
            if siblings.isEmpty { edits.append((hl, ns.substring(with: anchor))) }
        }
        edits.sort { $0.0.location > $1.0.location }
        let lowest = edits.map { $0.0.location }.min() ?? 0
        let keep = textView.selectedRange()
        withScrollPreserved(editAt: lowest) {
            for (r, rep) in edits { textView.perform(SmartEdit.Edit(range: r, replacement: rep, caret: r.location), select: NSRange(location: min(keep.location, r.location), length: 0)) }
            window?.makeFirstResponder(textView)
        }
    }

    func reply(to c: Comment) { margin.beginReply(threadStart: c.threadStart) }

    @objc func nextComment(_ sender: Any?) { jumpToComment(forward: true) }
    @objc func previousComment(_ sender: Any?) { jumpToComment(forward: false) }
    func jumpToComment(forward: Bool) {
        guard let m = model, !m.comments.isEmpty else { return }
        let cur = textView.selectedRange().location
        let target = forward ? (m.comments.first { $0.range.location > cur } ?? m.comments.first) : (m.comments.last { $0.range.location < cur } ?? m.comments.last)
        guard let t = target else { return }
        let r = t.anchorRange ?? NSRange(location: t.range.location, length: 0)
        textView.setSelectedRange(r)
        scroll(toOffset: r.location, topInset: scrollView.contentSize.height * 0.3)
    }

    @objc func showPalette(_ sender: Any?) { if let w = window { palette.show(mode: ">", in: w) } }
    @objc func showOutline(_ sender: Any?) { if let w = window { palette.show(mode: "#", in: w) } }
    @objc func quickOpen(_ sender: Any?) { if let w = window { palette.show(mode: "file", in: w) } }

    @objc func resolveClaudeComments(_ sender: Any?) {
        guard let m = model else { return }
        let targets = m.comments.filter { $0.author == "claude" }
        guard !targets.isEmpty else { statusLine.show("no comments by @claude", for: 1.5); return }
        // Resolve from the end so earlier ranges stay valid; re-parse between steps for anchors.
        for c in targets.sorted(by: { $0.range.location > $1.range.location }) {
            if let fresh = model?.comments.first(where: { $0.range.location == c.range.location }) { resolve(fresh) }
            reparseAndStyle()
        }
        statusLine.show("resolved \(targets.count) by @claude", for: 2)
    }

    @objc func copyComments(_ sender: Any?) {
        guard let m = model else { return }
        let ns = textView.string as NSString
        let lines = m.comments.map { c -> String in
            let who = c.author.map { "@\($0)" } ?? "note"
            let anchor = c.anchorRange.map { " (on: “\(ns.substring(with: $0))”)" } ?? ""
            return "- \(who): \(c.text)\(anchor)"
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
        statusLine.show("\(m.comments.count) comments copied", for: 1.5)
    }
    func rebuildOverlays(_ m: DocumentModel) {
        let inset = textView.textContainerInset.width
        let maxWidth = max(200, scrollView.contentSize.width - 2 * inset - styler.metrics.columnLeft - styler.metrics.textEdge)
        styler.reservedHeights = overlays.rebuild(model: m, text: textView.string as NSString, styler: styler, baseURL: doc.url.deletingLastPathComponent(), maxWidth: maxWidth)
    }

    @objc func toggleReading(_ sender: Any?) { setSourceMode(!sourceMode) }

    /// Source mode shows every character of Markdown. Rendered mode (default) shows styled text and reveals the caret's block.
    func setSourceMode(_ on: Bool) {
        sourceMode = on
        let anchor = firstVisible()
        saveNow(nil)
        styler.mode = on ? .source : .rendered
        textView.isRendered = !on
        if on { overlays.clear(); styler.reservedHeights = [:] }
        reparseAndStyle()
        scroll(toOffset: anchor.offset, topInset: -anchor.delta)
        modeToggle.sourceMode = on
        formatBar.hide()
    }

    /// Rendered mode: whether the character at `i` is drawn as a zero-size run.
    func isHiddenChar(at i: Int) -> Bool {
        guard styler.mode == .rendered, let m = model, i >= 0, i < flags.count - 1 else { return false }
        let line = m.lines[m.map.lineIndex(forUTF16: i)]
        if styler.reservedHeights[m.map.lineIndex(forUTF16: i)] != nil, line.kind != .table { return true }
        return styler.isHiddenInReading(line: line, flags: flags[i])
    }

    /// Runs a mutation and puts the viewport back where it was. `editAt` is the lowest offset the
    /// mutation touches: when it lies above the anchor, the anchor shifts by the length delta.
    func withScrollPreserved(editAt: Int, _ body: () -> Void) {
        let anchor = firstVisible()
        let before = textView.string.utf16.count
        body()
        let delta = textView.string.utf16.count - before
        let offset = editAt < anchor.offset ? max(0, anchor.offset + delta) : anchor.offset
        scroll(toOffset: offset, topInset: -anchor.delta)
    }

    /// Lines whose Markdown should be visible for the caret / selection: the whole code block or table, else the lines spanned.
    func activeBlock(for sel: NSRange, in m: DocumentModel) -> Range<Int> {
        guard !m.lines.isEmpty else { return 0..<0 }
        let length = m.map.utf16Count
        let a = m.map.lineIndex(forUTF16: min(sel.location, length))
        let b = m.map.lineIndex(forUTF16: min(sel.location + sel.length, length))
        var lo = min(a, b), hi = max(a, b) + 1
        for cb in m.codeBlocks where cb.lineRange.overlaps(lo..<hi) { lo = min(lo, cb.lineRange.lowerBound); hi = max(hi, cb.lineRange.upperBound) }
        for t in m.tables where t.lineRange.overlaps(lo..<hi) { lo = min(lo, t.lineRange.lowerBound); hi = max(hi, t.lineRange.upperBound) }
        if m.frontmatterLines?.overlaps(lo..<hi) == true, let f = m.frontmatterLines { lo = min(lo, f.lowerBound); hi = max(hi, f.upperBound) }
        return lo..<min(hi, max(lo + 1, min(m.lines.count, lo + 400)))
    }
    // Rendered text never reveals Markdown under the caret (feedback round 2). Kept for a possible opt-in later.
    var revealsCaretBlock: Bool { false }

    @objc func cycleTheme(_ sender: Any?) {
        let all = ThemeSpec.all
        let i = all.firstIndex(of: styler.theme) ?? 0
        setTheme(all[(i + 1) % all.count])
        statusLine.show(styler.theme.name, for: 1.2)
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
