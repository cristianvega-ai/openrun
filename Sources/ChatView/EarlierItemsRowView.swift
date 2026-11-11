import AppKit

/// The first row when the chat does not show the start of the thread. When
/// the agent's history holds more, a click or a scroll to the top asks the
/// host for it.
final class EarlierItemsRowView: StackRowView {
    let line = DisclosureLineView()

    override func configure(_ row: TranscriptRow, context: TranscriptRowContext) {
        super.configure(row, context: context)
        let canLoad = context.hasEarlierHistory && !context.isLoadingEarlierHistory
        let status = context.isLoadingEarlierHistory ? "Loading" : canLoad ? "Click to load" : nil
        line.show(symbolName: "clock.arrow.circlepath", title: "Earlier messages are not shown", status: status, palette: context.palette)
        line.action = canLoad ? { [weak context] in context?.actions?.loadEarlierHistory() } : nil
        setParts([Part(view: line)])
        setAccessibilityRole(.group)
        setAccessibilityLabel("Earlier messages")
    }
}
