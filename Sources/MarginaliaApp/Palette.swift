import AppKit
import MarginaliaCore

struct PaletteItem {
    enum Kind { case command(Selector), heading(Int, Int), file(URL), theme(String), mode(String) }
    let title: String
    let subtitle: String?
    let shortcut: String?
    let kind: Kind
}

enum Recents {
    static let key = "recentFiles"
    static func all() -> [URL] { (UserDefaults.standard.stringArray(forKey: key) ?? []).map { URL(fileURLWithPath: $0) } }
    static func touch(_ url: URL) {
        var list = (UserDefaults.standard.stringArray(forKey: key) ?? []).filter { $0 != url.path }
        list.insert(url.path, at: 0)
        UserDefaults.standard.set(Array(list.prefix(30)), forKey: key)
    }
}

/// Fuzzy subsequence score: higher is better, nil when the query does not match.
enum Fuzzy {
    static func score(_ query: String, _ candidate: String) -> Int? {
        if query.isEmpty { return 0 }
        let q = Array(query.lowercased()), c = Array(candidate.lowercased())
        var qi = 0, score = 0, lastMatch = -2
        for (i, ch) in c.enumerated() where qi < q.count {
            if ch == q[qi] {
                score += 10
                if i == lastMatch + 1 { score += 15 }
                if i == 0 || c[i - 1] == " " || c[i - 1] == "-" || c[i - 1] == "_" || c[i - 1] == "/" { score += 12 }
                lastMatch = i; qi += 1
            }
        }
        guard qi == q.count else { return nil }
        return score - c.count / 4
    }
}

/// ⌘K. One floating panel for commands, headings (`#`), and files (⌘O).
final class CommandPalette: NSPanel, NSTextFieldDelegate, NSTableViewDataSource, NSTableViewDelegate {
    private let field = NSTextField()
    private let table = NSTableView()
    private let scroll = NSScrollView()
    private let hint = NSTextField(labelWithString: "")
    private var items: [PaletteItem] = []
    private var filtered: [PaletteItem] = []
    private var mode: String = ">"
    private weak var controller: DocumentWindowController?
    static let rowHeight: CGFloat = 40
    static let width: CGFloat = 560

    init(controller: DocumentWindowController) {
        self.controller = controller
        super.init(contentRect: NSRect(x: 0, y: 0, width: CommandPalette.width, height: 60), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = false
        becomesKeyOnlyIfNeeded = false
        hidesOnDeactivate = true

        let content = PaletteBackground(frame: NSRect(x: 0, y: 0, width: CommandPalette.width, height: 60))
        contentView = content

        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = ChromeFont.regular(18)
        field.textColor = Palette.fg
        field.placeholderAttributedString = NSAttributedString(string: "Type a command, # for headings", attributes: [.font: ChromeFont.regular(18), .foregroundColor: Palette.fgMuted])
        field.delegate = self
        field.frame = NSRect(x: 20, y: 0, width: CommentCard.width + 200, height: 30)
        content.addSubview(field)

        hint.font = ChromeFont.regular(11)
        hint.textColor = Palette.fgMuted
        hint.alignment = .right
        content.addSubview(hint)

        table.headerView = nil
        table.backgroundColor = .clear
        table.selectionHighlightStyle = .regular
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.rowHeight = CommandPalette.rowHeight
        table.intercellSpacing = .zero
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.action = #selector(rowClicked)
        let col = NSTableColumn(identifier: .init("c")); col.width = CommandPalette.width; col.resizingMask = .autoresizingMask
        table.addTableColumn(col)
        scroll.documentView = table
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        content.addSubview(scroll)
    }

    override var canBecomeKey: Bool { true }

    // MARK: Show

    func show(mode: String, in parent: NSWindow) {
        self.mode = mode
        items = buildItems(mode: mode)
        field.stringValue = ""
        field.placeholderAttributedString = NSAttributedString(string: mode == "#" ? "Jump to heading" : (mode == "file" ? "Open a recent or sibling file" : "Type a command, # for headings"),
                                                               attributes: [.font: ChromeFont.regular(18), .foregroundColor: Palette.fgMuted])
        refilter()
        if mode == "#", let c = controller, let m = c.model {
            let caret = c.textView.selectedRange().location
            if let idx = filtered.lastIndex(where: { if case .heading(let off, _) = $0.kind { return off <= caret } else { return false } }) {
                table.selectRowIndexes([idx], byExtendingSelection: false); table.scrollRowToVisible(idx)
            }
            _ = m
        }
        let pf = parent.frame
        let x = pf.midX - CommandPalette.width / 2
        let y = pf.maxY - 120 - frame.height
        setFrameOrigin(NSPoint(x: x, y: y))
        parent.addChildWindow(self, ordered: .above)
        makeKeyAndOrderFront(nil)
        makeFirstResponder(field)
    }

    func dismiss() {
        parent?.removeChildWindow(self)
        orderOut(nil)
    }

    override func resignKey() {
        super.resignKey()
        dismiss()
    }

    // MARK: Items

    private func buildItems(mode: String) -> [PaletteItem] {
        guard let c = controller else { return [] }
        switch mode {
        case "#":
            guard let m = c.model else { return [] }
            return m.headings.map { h in
                PaletteItem(title: String(repeating: "    ", count: max(0, h.level - 1)) + h.title, subtitle: nil, shortcut: "H\(h.level)", kind: .heading(h.range.location, h.level))
            }
        case "file":
            var seen = Set<String>()
            var out: [PaletteItem] = []
            let current = c.doc.url.standardizedFileURL.path
            for u in Recents.all() where u.path != current && FileManager.default.fileExists(atPath: u.path) {
                guard seen.insert(u.path).inserted else { continue }
                out.append(PaletteItem(title: u.lastPathComponent, subtitle: u.deletingLastPathComponent().path.replacingOccurrences(of: NSHomeDirectory(), with: "~"), shortcut: "recent", kind: .file(u)))
            }
            let dir = c.doc.url.deletingLastPathComponent()
            if let sib = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) {
                let mds = sib.filter { ["md", "markdown", "txt"].contains($0.pathExtension.lowercased()) && $0.standardizedFileURL.path != current }
                    .sorted { (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantPast) ?? .distantPast > (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantPast) ?? .distantPast }
                for u in mds.prefix(60) where seen.insert(u.standardizedFileURL.path).inserted {
                    out.append(PaletteItem(title: u.lastPathComponent, subtitle: "same folder", shortcut: nil, kind: .file(u)))
                }
            }
            return out
        default:
            var out: [PaletteItem] = [
                PaletteItem(title: c.reading ? "Edit Mode" : "Reading Mode", subtitle: nil, shortcut: "⌘⇧R", kind: .command(#selector(DocumentWindowController.toggleReading(_:)))),
                PaletteItem(title: "Go to Heading…", subtitle: nil, shortcut: "⌘⇧O", kind: .mode("#")),
                PaletteItem(title: "Open Recent or Sibling…", subtitle: nil, shortcut: "⌘O", kind: .mode("file")),
                PaletteItem(title: "Add Comment", subtitle: "on the selection, or at the end of the paragraph", shortcut: "⌘⇧M", kind: .command(#selector(DocumentWindowController.addComment(_:)))),
                PaletteItem(title: "Next Comment", subtitle: nil, shortcut: "⌥⌘↓", kind: .command(#selector(DocumentWindowController.nextComment(_:)))),
                PaletteItem(title: "Previous Comment", subtitle: nil, shortcut: "⌥⌘↑", kind: .command(#selector(DocumentWindowController.previousComment(_:)))),
                PaletteItem(title: "Copy All Comments as Markdown List", subtitle: nil, shortcut: nil, kind: .command(#selector(DocumentWindowController.copyComments(_:)))),
                PaletteItem(title: "Resolve All Comments by @claude", subtitle: nil, shortcut: nil, kind: .command(#selector(DocumentWindowController.resolveClaudeComments(_:)))),
                PaletteItem(title: "Next Change", subtitle: "from the last external update", shortcut: "⌃↓", kind: .command(#selector(DocumentWindowController.nextChange(_:)))),
                PaletteItem(title: "Previous Change", subtitle: nil, shortcut: "⌃↑", kind: .command(#selector(DocumentWindowController.previousChange(_:)))),
                PaletteItem(title: "Next Theme", subtitle: nil, shortcut: "⌘⇧T", kind: .command(#selector(DocumentWindowController.cycleTheme(_:)))),
            ]
            for t in ThemeSpec.all { out.append(PaletteItem(title: "Theme: \(t.name)", subtitle: "\(t.bodyFamily) + \(t.monoFamily)", shortcut: nil, kind: .theme(t.id))) }
            out += [
                PaletteItem(title: "Bigger Text", subtitle: nil, shortcut: "⌘+", kind: .command(#selector(DocumentWindowController.zoomIn(_:)))),
                PaletteItem(title: "Smaller Text", subtitle: nil, shortcut: "⌘−", kind: .command(#selector(DocumentWindowController.zoomOut(_:)))),
                PaletteItem(title: "Actual Size", subtitle: nil, shortcut: "⌘0", kind: .command(#selector(DocumentWindowController.zoomReset(_:)))),
                PaletteItem(title: "Bold", subtitle: nil, shortcut: "⌘B", kind: .command(#selector(EditorTextView.toggleBold(_:)))),
                PaletteItem(title: "Italic", subtitle: nil, shortcut: "⌘I", kind: .command(#selector(EditorTextView.toggleItalic(_:)))),
                PaletteItem(title: "Inline Code", subtitle: nil, shortcut: "⌘E", kind: .command(#selector(EditorTextView.toggleCodeSpan(_:)))),
                PaletteItem(title: "Strikethrough", subtitle: nil, shortcut: nil, kind: .command(#selector(EditorTextView.toggleStrike(_:)))),
                PaletteItem(title: "Link", subtitle: "uses a URL from the clipboard when there is one", shortcut: "⌘⇧K", kind: .command(#selector(EditorTextView.insertLink(_:)))),
                PaletteItem(title: "Raise Heading", subtitle: nil, shortcut: "⌘⇧]", kind: .command(#selector(EditorTextView.headingUp(_:)))),
                PaletteItem(title: "Lower Heading", subtitle: nil, shortcut: "⌘⇧[", kind: .command(#selector(EditorTextView.headingDown(_:)))),
                PaletteItem(title: "Toggle Task", subtitle: nil, shortcut: "⌘⏎", kind: .command(#selector(EditorTextView.toggleTask(_:)))),
                PaletteItem(title: "Move Line Up", subtitle: nil, shortcut: "⌥↑", kind: .command(#selector(EditorTextView.moveLineUp(_:)))),
                PaletteItem(title: "Move Line Down", subtitle: nil, shortcut: "⌥↓", kind: .command(#selector(EditorTextView.moveLineDown(_:)))),
                PaletteItem(title: "Save Now", subtitle: "autosave is always on", shortcut: "⌘S", kind: .command(#selector(DocumentWindowController.saveNow(_:)))),
                PaletteItem(title: "Reveal in Finder", subtitle: nil, shortcut: nil, kind: .command(#selector(DocumentWindowController.revealInFinder(_:)))),
                PaletteItem(title: "Copy Path", subtitle: nil, shortcut: nil, kind: .command(#selector(DocumentWindowController.copyPath(_:)))),
                PaletteItem(title: "Print…", subtitle: "uses the reading style", shortcut: "⌘P", kind: .command(#selector(DocumentWindowController.printDocument(_:)))),
                PaletteItem(title: "Settings…", subtitle: nil, shortcut: "⌘,", kind: .command(#selector(AppDelegate.showSettings(_:)))),
            ]
            return out
        }
    }

    // MARK: Filter

    private func refilter() {
        var q = field.stringValue
        if mode == ">" || mode == "#", q.hasPrefix("#") {
            if mode != "#" { mode = "#"; items = buildItems(mode: "#") }
            q = String(q.dropFirst())
        } else if mode == "#", !field.stringValue.hasPrefix("#"), field.stringValue.isEmpty == false, items.isEmpty {
            // nothing
        }
        if q.hasPrefix(">") { q = String(q.dropFirst()) }
        q = q.trimmingCharacters(in: .whitespaces)
        if q.isEmpty {
            filtered = items
        } else {
            filtered = items.compactMap { it -> (PaletteItem, Int)? in
                guard let s = Fuzzy.score(q, it.title + " " + (it.subtitle ?? "")) else { return nil }
                return (it, s)
            }.sorted { $0.1 > $1.1 }.map { $0.0 }
        }
        table.reloadData()
        if !filtered.isEmpty { table.selectRowIndexes([0], byExtendingSelection: false); table.scrollRowToVisible(0) }
        scroll.contentView.scroll(to: .zero)
        hint.stringValue = mode == "#" ? "\(filtered.count) headings" : (mode == "file" ? "\(filtered.count) files" : "\(filtered.count) commands")
        relayout()
    }

    private func relayout() {
        let rows = min(8, max(0, filtered.count))
        let listH = CGFloat(rows) * CommandPalette.rowHeight
        let fieldH: CGFloat = 54
        let h = fieldH + listH + (rows > 0 ? 8 : 0)
        let old = frame
        setFrame(NSRect(x: old.minX, y: old.maxY - h, width: CommandPalette.width, height: h), display: true)
        guard let cv = contentView else { return }
        field.frame = NSRect(x: 20, y: h - 40, width: CommandPalette.width - 140, height: 28)
        hint.frame = NSRect(x: CommandPalette.width - 120, y: h - 34, width: 100, height: 16)
        scroll.frame = NSRect(x: 0, y: 0, width: CommandPalette.width, height: listH + (rows > 0 ? 4 : 0))
        cv.needsDisplay = true
    }

    /// Script hook: types into the field and filters.
    func scriptType(_ text: String) { field.stringValue = text; refilter() }

    // MARK: Field delegate

    func controlTextDidChange(_ obj: Notification) { refilter() }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        switch sel {
        case #selector(NSResponder.moveDown(_:)): move(1); return true
        case #selector(NSResponder.moveUp(_:)): move(-1); return true
        case #selector(NSResponder.insertNewline(_:)): activateSelected(); return true
        case #selector(NSResponder.cancelOperation(_:)): dismiss(); return true
        case #selector(NSResponder.deleteBackward(_:)):
            if field.stringValue.isEmpty, mode != ">" { mode = ">"; items = buildItems(mode: ">"); refilter(); return true }
            return false
        default: return false
        }
    }

    private func move(_ d: Int) {
        guard !filtered.isEmpty else { return }
        let r = max(0, min(filtered.count - 1, table.selectedRow + d))
        table.selectRowIndexes([r], byExtendingSelection: false)
        table.scrollRowToVisible(r)
    }

    @objc private func rowClicked() { activateSelected() }

    private func activateSelected() {
        guard table.selectedRow >= 0, table.selectedRow < filtered.count else { return }
        let item = filtered[table.selectedRow]
        switch item.kind {
        case .mode(let m):
            mode = m; items = buildItems(mode: m); field.stringValue = ""; refilter(); return
        case .command(let sel):
            dismiss()
            controller?.window?.makeKeyAndOrderFront(nil)
            DispatchQueue.main.async { NSApp.sendAction(sel, to: nil, from: nil) }
        case .heading(let off, _):
            dismiss()
            controller?.window?.makeKeyAndOrderFront(nil)
            controller?.scroll(toOffset: off, topInset: 96, moveCaret: true)
        case .file(let url):
            dismiss()
            (NSApp.delegate as? AppDelegate)?.open(url)
        case .theme(let id):
            dismiss()
            controller?.setTheme(ThemeSpec.named(id))
        }
    }

    // MARK: Table

    func numberOfRows(in tableView: NSTableView) -> Int { filtered.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let item = filtered[row]
        let v = PaletteRow(frame: NSRect(x: 0, y: 0, width: CommandPalette.width, height: CommandPalette.rowHeight))
        v.configure(item)
        return v
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? { PaletteRowView() }
}

final class PaletteBackground: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let p = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 10, yRadius: 10)
        Palette.bgElevated.setFill(); p.fill()
        Palette.fgFaint.setStroke(); p.lineWidth = 1; p.stroke()
        if bounds.height > 60 {
            let y = bounds.height - 54
            Palette.fgFaint.setFill()
            NSRect(x: 12, y: y, width: bounds.width - 24, height: 1).fill()
        }
    }
}

final class PaletteRowView: NSTableRowView {
    override var isEmphasized: Bool { get { true } set {} }
    override func drawBackground(in dirtyRect: NSRect) {}
    override func drawSelection(in dirtyRect: NSRect) {
        let r = bounds.insetBy(dx: 8, dy: 2)
        Palette.accent.withAlphaComponent(0.12).setFill()
        NSBezierPath(roundedRect: r, xRadius: 6, yRadius: 6).fill()
    }
}

final class PaletteRow: NSView {
    let title = NSTextField(labelWithString: "")
    let subtitle = NSTextField(labelWithString: "")
    let shortcut = NSTextField(labelWithString: "")
    override init(frame: NSRect) {
        super.init(frame: frame)
        title.font = ChromeFont.regular(14); title.textColor = Palette.fg
        subtitle.font = ChromeFont.regular(11); subtitle.textColor = Palette.fgMuted
        shortcut.font = ChromeFont.regular(11); shortcut.textColor = Palette.fgMuted; shortcut.alignment = .right
        addSubview(title); addSubview(subtitle); addSubview(shortcut)
    }
    required init?(coder: NSCoder) { fatalError() }
    func configure(_ item: PaletteItem) {
        title.stringValue = item.title
        subtitle.stringValue = item.subtitle ?? ""
        shortcut.stringValue = item.shortcut ?? ""
        let hasSub = !(item.subtitle ?? "").isEmpty
        title.frame = NSRect(x: 20, y: hasSub ? 18 : 11, width: bounds.width - 170, height: 18)
        subtitle.frame = NSRect(x: 20, y: 5, width: bounds.width - 170, height: 14)
        subtitle.isHidden = !hasSub
        shortcut.frame = NSRect(x: bounds.width - 140, y: 12, width: 108, height: 16)
    }
}
