import AppKit

/// What a row shows on its trailing edge.
enum MenuRowAccessory {
    case none
    case chevron(expanded: Bool)
    case checkmark(selected: Bool)
}

/// A small rounded color chip behind a row's SF Symbol — reads as a colored
/// "icon tile" rather than a flat monochrome glyph.
private final class IconChipView: NSView {
    init(symbol: String, tint: NSColor, pointSize: CGFloat = 11) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 7
        layer?.backgroundColor = tint.withAlphaComponent(0.22).cgColor
        widthAnchor.constraint(equalToConstant: 22).isActive = true
        heightAnchor.constraint(equalToConstant: 22).isActive = true

        let imageView = NSImageView()
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
        imageView.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
        imageView.contentTintColor = tint
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("not supported") }
}

/// A single row in the custom right-click menu. Rows aren't real NSMenuItems,
/// so hover highlighting, the icon chip, and the accessory glyph are all
/// hand-rolled here.
final class MenuRowView: NSView {
    private let titleLabel = NSTextField(labelWithString: "")
    private var trackingArea: NSTrackingArea?
    private let isEnabled: Bool
    private let onSelect: (() -> Void)?
    private let tint: NSColor

    private var isHighlighted = false {
        didSet { needsDisplay = true }
    }

    init(
        title: String,
        symbolName: String? = nil,
        tint: NSColor = .white,
        indent: CGFloat = 14,
        accessory: MenuRowAccessory = .none,
        titleColor: NSColor? = nil,
        emphasized: Bool = false,
        isEnabled: Bool = true,
        onSelect: (() -> Void)? = nil
    ) {
        self.isEnabled = isEnabled && onSelect != nil
        self.onSelect = onSelect
        self.tint = tint
        super.init(frame: .zero)

        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 30).isActive = true
        wantsLayer = true

        titleLabel.font = .systemFont(ofSize: 13, weight: emphasized ? .semibold : .regular)
        titleLabel.textColor = isEnabled ? (titleColor ?? .white.withAlphaComponent(0.92)) : .white.withAlphaComponent(0.3)
        titleLabel.stringValue = title
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        var titleLeadingConstraint: NSLayoutConstraint

        if let symbolName {
            let chip = IconChipView(symbol: symbolName, tint: isEnabled ? tint : .white.withAlphaComponent(0.25))
            addSubview(chip)
            NSLayoutConstraint.activate([
                chip.leadingAnchor.constraint(equalTo: leadingAnchor, constant: indent),
                chip.centerYAnchor.constraint(equalTo: centerYAnchor),
            ])
            titleLeadingConstraint = titleLabel.leadingAnchor.constraint(equalTo: chip.trailingAnchor, constant: 8)
        } else {
            titleLeadingConstraint = titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: indent)
        }

        let accessoryView = NSImageView()
        accessoryView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(accessoryView)

        switch accessory {
        case .none:
            break
        case .chevron(let expanded):
            let config = NSImage.SymbolConfiguration(pointSize: 10, weight: .semibold)
            accessoryView.image = NSImage(systemSymbolName: expanded ? "chevron.down" : "chevron.right", accessibilityDescription: nil)?
                .withSymbolConfiguration(config)
            accessoryView.contentTintColor = .white.withAlphaComponent(0.35)
        case .checkmark(let selected):
            if selected {
                let badge = NSView()
                badge.wantsLayer = true
                badge.layer?.backgroundColor = tint.cgColor
                badge.layer?.cornerRadius = 7
                badge.translatesAutoresizingMaskIntoConstraints = false
                addSubview(badge)
                let check = NSImageView()
                let config = NSImage.SymbolConfiguration(pointSize: 8, weight: .heavy)
                check.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)?
                    .withSymbolConfiguration(config)
                check.contentTintColor = .black
                check.translatesAutoresizingMaskIntoConstraints = false
                badge.addSubview(check)
                NSLayoutConstraint.activate([
                    badge.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -11),
                    badge.centerYAnchor.constraint(equalTo: centerYAnchor),
                    badge.widthAnchor.constraint(equalToConstant: 14),
                    badge.heightAnchor.constraint(equalToConstant: 14),
                    check.centerXAnchor.constraint(equalTo: badge.centerXAnchor),
                    check.centerYAnchor.constraint(equalTo: badge.centerYAnchor),
                ])
            }
        }

        NSLayoutConstraint.activate([
            titleLeadingConstraint,
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -30),

            accessoryView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -13),
            accessoryView.centerYAnchor.constraint(equalTo: centerYAnchor),
            accessoryView.widthAnchor.constraint(equalToConstant: 10),
        ])
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        if isEnabled { isHighlighted = true }
    }

    override func mouseExited(with event: NSEvent) {
        isHighlighted = false
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        onSelect?()
    }

    override func draw(_ dirtyRect: NSRect) {
        guard isHighlighted else { return }
        let bar = NSBezierPath(roundedRect: NSRect(x: 6, y: 5, width: 3, height: bounds.height - 10), xRadius: 1.5, yRadius: 1.5)
        tint.setFill()
        bar.fill()

        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 6, dy: 1), xRadius: 8, yRadius: 8)
        tint.withAlphaComponent(0.12).setFill()
        path.fill()
    }
}

/// A thin inset divider, standing in for NSMenuItem.separator().
final class MenuSeparatorView: NSView {
    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 9).isActive = true
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.withAlphaComponent(0.08).setFill()
        NSRect(x: 14, y: bounds.midY, width: bounds.width - 28, height: 1).fill()
    }
}
