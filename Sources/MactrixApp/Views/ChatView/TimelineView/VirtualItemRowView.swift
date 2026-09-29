import AppKit
import MatrixRustSDK

final class VirtualItemRowView: NSView {
    static let rowHeight: CGFloat = 40

    private let leadingLine = NSView()
    private let trailingLine = NSView()
    private let label = NSTextField(labelWithString: "")
    private var isReadMarker = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        for line in [leadingLine, trailingLine] {
            line.wantsLayer = true
            line.translatesAutoresizingMaskIntoConstraints = false
            addSubview(line)
        }

        label.translatesAutoresizingMaskIntoConstraints = false
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addSubview(label)

        NSLayoutConstraint.activate([
            leadingLine.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            leadingLine.trailingAnchor.constraint(equalTo: label.leadingAnchor, constant: -10),
            leadingLine.centerYAnchor.constraint(equalTo: centerYAnchor),
            leadingLine.heightAnchor.constraint(equalToConstant: 1),

            label.centerYAnchor.constraint(equalTo: centerYAnchor),

            trailingLine.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 10),
            trailingLine.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            trailingLine.centerYAnchor.constraint(equalTo: centerYAnchor),
            trailingLine.heightAnchor.constraint(equalToConstant: 1),
            trailingLine.widthAnchor.constraint(equalTo: leadingLine.widthAnchor),
        ])

        updateLineColor()
    }

    func configure(item: VirtualTimelineItem) {
        switch item {
        case let .dateDivider(ts):
            let date = Date(timeIntervalSince1970: Double(ts) / 1000)
            let dayInSeconds: TimeInterval = 24 * 60 * 60
            let elapsed = Date.now.timeIntervalSince(date)
            if elapsed < dayInSeconds {
                label.stringValue = String(localized: "Today")
            } else if elapsed < dayInSeconds * 2 {
                label.stringValue = String(localized: "Yesterday")
            } else {
                label.stringValue = date.formatted(date: .long, time: .omitted)
            }
            label.font = .systemFont(ofSize: NSFont.systemFontSize)
            isReadMarker = false
        case .readMarker:
            label.stringValue = String(localized: "Read Marker")
            label.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
            isReadMarker = true
        case .timelineStart:
            label.stringValue = String(localized: "Start of conversation")
            label.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
            isReadMarker = false
        }

        updateLineColor()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateLineColor()
    }

    private func updateLineColor() {
        let color: NSColor
        if isReadMarker {
            let isDark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            color = NSColor.red.blended(withFraction: 0.1, of: isDark ? .white : .black) ?? .red
        } else {
            color = .separatorColor
        }
        label.textColor = isReadMarker ? color : .labelColor
        leadingLine.layer?.backgroundColor = color.cgColor
        trailingLine.layer?.backgroundColor = color.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
