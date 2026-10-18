import AppKit

@MainActor
private final class TrackingSlider: NSSlider {
    private(set) var isUserTracking = false
    var onTrackingEnded: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        isUserTracking = true
        super.mouseDown(with: event)
        isUserTracking = false
        onTrackingEnded?()
    }
}

@MainActor
final class BrightnessSliderView: NSView {
    private let slider = TrackingSlider(value: 0.75, minValue: 0, maxValue: 1, target: nil, action: nil)
    private let symbolView = NSImageView()
    private let label = NSTextField(labelWithString: "All displays")
    private let subtitleLabel = NSTextField(labelWithString: "Global brightness")
    private let valueLabel = NSTextField(labelWithString: "75%")

    var onChange: ((Double) -> Void)?
    var onTrackingEnded: (() -> Void)?
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.lineBreakMode = .byTruncatingTail
        subtitleLabel.font = .systemFont(ofSize: 10)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.lineBreakMode = .byTruncatingTail
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        valueLabel.alignment = .right
        valueLabel.setContentHuggingPriority(.required, for: .horizontal)
        symbolView.image = NSImage(systemSymbolName: "display.2", accessibilityDescription: nil)
        symbolView.contentTintColor = .secondaryLabelColor
        symbolView.setContentHuggingPriority(.required, for: .horizontal)
        slider.target = self
        slider.action = #selector(changed)
        slider.isContinuous = true
        slider.onTrackingEnded = { [weak self] in self?.onTrackingEnded?() }

        let text = NSStackView(views: [label, subtitleLabel])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 0
        let labels = NSStackView(views: [symbolView, text, valueLabel])
        labels.orientation = .horizontal
        labels.alignment = .centerY
        labels.spacing = 8
        let stack = NSStackView(views: [labels, slider])
        stack.orientation = .vertical
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            symbolView.widthAnchor.constraint(equalToConstant: 18),
            symbolView.heightAnchor.constraint(equalToConstant: 18),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
        ])
    }

    required init?(coder: NSCoder) { nil }

    func configure(title: String, subtitle: String, symbolName: String) {
        label.stringValue = title
        subtitleLabel.stringValue = subtitle
        symbolView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: title)
    }

    func setRange(minimum: Double, maximum: Double = 1) {
        slider.minValue = minimum
        slider.maxValue = maximum
    }

    func setValue(_ value: Double, unlessTracking: Bool = false) {
        guard !unlessTracking || !slider.isUserTracking else { return }
        slider.doubleValue = value
        valueLabel.stringValue = "\(Int((value * 100).rounded()))%"
    }

    @objc private func changed() {
        setValue(slider.doubleValue)
        onChange?(slider.doubleValue)
    }
}
