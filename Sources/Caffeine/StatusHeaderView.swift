import AppKit

/// Custom header row for the right-click menu: a status dot plus a title/detail
/// pair, standing in for the plain-text "☕ Caffeine: Active" item.
final class StatusHeaderView: NSView {
    private let dot = NSView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        dot.wantsLayer = true
        dot.layer?.cornerRadius = 4
        dot.frame = NSRect(x: 14, y: frameRect.height / 2 - 4, width: 8, height: 8)
        addSubview(dot)

        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.frame = NSRect(x: 30, y: frameRect.height / 2 - 1, width: frameRect.width - 40, height: 16)
        addSubview(titleLabel)

        detailLabel.font = .systemFont(ofSize: 11, weight: .regular)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.frame = NSRect(x: 30, y: frameRect.height / 2 - 18, width: frameRect.width - 40, height: 14)
        addSubview(detailLabel)
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    func configure(title: String, detail: String, dotColor: NSColor) {
        titleLabel.stringValue = title
        detailLabel.stringValue = detail
        dot.layer?.backgroundColor = dotColor.cgColor
    }
}
