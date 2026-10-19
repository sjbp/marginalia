import AppKit

/// A hairline of text at the bottom right that fades in with a message and fades out on its own.
final class StatusLine: NSView {
    private let label = NSTextField(labelWithString: "")
    private var hideTimer: Timer?
    var onClick: (() -> Void)?
    private var trailing: NSLayoutConstraint!
    var trailingInset: CGFloat = 20 { didSet { trailing.constant = -trailingInset } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        alphaValue = 0
        label.font = ChromeFont.regular(12)
        label.textColor = Palette.fgMuted
        label.alignment = .right
        label.lineBreakMode = .byTruncatingHead
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        trailing = label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20)
        NSLayoutConstraint.activate([
            trailing,
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 20),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard alphaValue > 0.5, onClick != nil else { return nil }
        return label.frame.insetBy(dx: -8, dy: -6).contains(point) ? self : nil
    }
    override func mouseDown(with event: NSEvent) { onClick?() }

    /// Shows a message. Duration in seconds, or nil to stay until replaced.
    func show(_ text: String, for duration: TimeInterval? = 2.0, accent: Bool = false, action: (() -> Void)? = nil) {
        label.stringValue = text
        label.textColor = accent ? Palette.accent : Palette.fgMuted
        onClick = action
        hideTimer?.invalidate()
        NSAnimationContext.runAnimationGroup { ctx in ctx.duration = 0.15; animator().alphaValue = 1 }
        if let duration {
            hideTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in self?.hide() }
        }
    }

    func hide() {
        hideTimer?.invalidate()
        NSAnimationContext.runAnimationGroup { ctx in ctx.duration = 0.4; animator().alphaValue = 0 }
    }
}

enum ReadingStats {
    static func describe(_ text: String) -> String {
        var words = 0
        var inWord = false
        for u in text.utf8 {
            let ws = u == 0x20 || u == 0x0A || u == 0x09 || u == 0x0D
            if ws { inWord = false } else if !inWord { inWord = true; words += 1 }
        }
        let minutes = max(1, Int((Double(words) / 230).rounded()))
        let f = NumberFormatter(); f.numberStyle = .decimal
        return "\(f.string(from: NSNumber(value: words)) ?? "\(words)") words · \(minutes) min"
    }
}
