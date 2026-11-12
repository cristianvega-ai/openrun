import AppKit

/// A field with a stepper for a whole number in a range.
@MainActor final class NumberSettingControl: NSObject, SettingControl {
    let field = NSTextField(string: "")
    let stepper = NSStepper()
    private let range: ClosedRange<Int>
    private let stack: NSStackView
    private var shown = 0
    var changed: ((String) -> Void)?
    var view: NSView { stack }

    /// - Parameter unit: A word after the field, such as "lines".
    init(_ range: ClosedRange<Int>, unit: String? = nil) {
        self.range = range
        stack = NSStackView(views: [field, stepper] + (unit.map { [NSTextField(labelWithString: $0)] } ?? []))
        super.init()
        stack.spacing = 6
        field.alignment = .right
        field.widthAnchor.constraint(equalToConstant: 84).isActive = true
        (stepper.minValue, stepper.maxValue, stepper.valueWraps) = (Double(range.lowerBound), Double(range.upperBound), false)
        (field.target, field.action) = (self, #selector(typed))
        (stepper.target, stepper.action) = (self, #selector(stepped))
    }

    func show(_ text: String) {
        shown = Int(text) ?? shown
        field.stringValue = String(shown)
        stepper.integerValue = shown
    }

    /// Text that is no number in the range goes back to the value before it.
    @objc func typed() {
        take(Int(field.stringValue.trimmingCharacters(in: .whitespaces)).map { min(max($0, range.lowerBound), range.upperBound) } ?? shown)
    }

    @objc func stepped() {
        take(stepper.integerValue)
    }

    private func take(_ number: Int) {
        let isNew = number != shown
        show(String(number))
        if isNew { changed?(String(number)) }
    }
}
