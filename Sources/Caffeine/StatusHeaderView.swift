import AppKit

/// Header row for the custom right-click menu: a bold brand title plus a
/// colored status pill (e.g. "● ACTIVE · 12m"), replacing the plain-text
/// "☕ Caffeine: Active" item and the old plain status dot.
final class StatusHeaderView: NSView {
    private let titleLabel = NSTextField(labelWithString: "")
    private let pill = NSView()
    private let pillLabel = NSTextField(labelWithString: "")

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 44).isActive = true

        titleLabel.font = NSFont.systemFont(ofSize: 15, weight: .bold)
        titleLabel.textColor = .white
        titleLabel.stringValue = "Caffeine"
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        pill.wantsLayer = true
        pill.layer?.cornerRadius = 8
        pill.translatesAutoresizingMaskIntoConstraints = false
        addSubview(pill)

        pillLabel.font = .systemFont(ofSize: 10, weight: .bold)
        pillLabel.translatesAutoresizingMaskIntoConstraints = false
        pill.addSubview(pillLabel)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 9),

            pill.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            pill.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 5),
            pill.heightAnchor.constraint(equalToConstant: 16),

            pillLabel.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 7),
            pillLabel.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -7),
            pillLabel.centerYAnchor.constraint(equalTo: pill.centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    /// `duration` (e.g. "12m") is shown as-is, lowercase unit and all —
    /// only the ACTIVE/INACTIVE word itself is a badge-style caps word.
    func configure(active: Bool, duration: String) {
        let color: NSColor = active ? NSColor(calibratedRed: 0.30, green: 0.85, blue: 0.45, alpha: 1) : .white
        pill.layer?.backgroundColor = color.withAlphaComponent(active ? 0.18 : 0.1).cgColor
        pillLabel.stringValue = active ? "ACTIVE · \(duration)" : "INACTIVE"
        pillLabel.textColor = active ? color : .white.withAlphaComponent(0.5)
    }
}
