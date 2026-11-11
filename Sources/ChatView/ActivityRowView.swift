import AppKit

/// The quiet sign that the agent works: three dots that brighten in turn,
/// and "Thinking" while the agent thinks. With Reduce Motion, the dots
/// stand still.
final class ActivityRowView: TranscriptRowView {
    static let height: CGFloat = 24
    let label = NSTextField(labelWithString: "")
    private let dots = (0..<3).map { _ in CALayer() }
    private var color = NSColor.secondaryLabelColor

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        for dot in dots {
            dot.cornerRadius = 2.5
            layer?.addSublayer(dot)
        }
        addSubview(label)
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func configure(_ row: TranscriptRow, context: TranscriptRowContext) {
        super.configure(row, context: context)
        label.stringValue = context.transcript.thinking == nil ? "Working" : "Thinking"
        label.font = context.palette.smallFont
        label.textColor = context.palette.secondaryText
        color = context.palette.secondaryText
        setAccessibilityLabel("\(context.agentName) is \(label.stringValue.lowercased())")
        updateDots()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateDots()
    }

    private func updateDots() {
        effectiveAppearance.performAsCurrentDrawingAppearance { [dots, color] in
            for dot in dots { dot.backgroundColor = color.cgColor }
        }
        let isStill = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        for (index, dot) in dots.enumerated() {
            dot.removeAllAnimations()
            dot.opacity = isStill ? 0.6 : 0.25
            guard !isStill else { continue }
            let animation = CABasicAnimation(keyPath: "opacity")
            animation.fromValue = 0.25
            animation.toValue = 0.9
            animation.duration = 0.6
            animation.autoreverses = true
            animation.repeatCount = .infinity
            animation.beginTime = CACurrentMediaTime() + Double(index) * 0.2
            dot.add(animation, forKey: "brighten")
        }
    }

    override func height(forWidth width: CGFloat) -> CGFloat {
        Self.height
    }

    override func layout() {
        super.layout()
        let column = ChatColumn.frame(inWidth: bounds.width)
        for (index, dot) in dots.enumerated() {
            dot.frame = CGRect(x: column.x + 2 + CGFloat(index) * 9, y: (bounds.height - 5) / 2, width: 5, height: 5)
        }
        label.frame = NSRect(x: column.x + 34, y: (bounds.height - 17) / 2, width: column.width - 34, height: 17)
    }
}
