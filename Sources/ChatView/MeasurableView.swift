import CoreGraphics

/// A view whose height follows from its width, such as a box of text.
@MainActor protocol MeasurableView {
    func height(forWidth width: CGFloat) -> CGFloat
}
