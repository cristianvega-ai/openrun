import AppKit

/// The order of Tab: from the composer to the newest request that waits,
/// then up through the lines that open, newest first, then to the menus
/// under the composer, and back to the composer.
extension ChatViewController {
    func connectKeyViews() {
        let rows = transcriptView.rowViews.views.values.sorted { $0.frame.minY > $1.frame.minY }
        let request = rows.lazy.compactMap { ($0 as? PermissionRequestRowView)?.box }.first { $0.superview != nil && $0.denyButton.isEnabled }
        var chain: [NSView] = [composer.textView]
        if let request { chain += [request.messageField, request.denyButton] + (request.allowButton.isHidden ? [] : [request.allowButton]) }
        for row in rows {
            let lines = (row as? StackRowView)?.parts.compactMap { $0.view as? DisclosureLineView } ?? []
            chain += lines.filter { $0.action != nil }.reversed()
        }
        chain += [composer.footer.modelButton, composer.footer.modeButton]
        for (view, next) in zip(chain, chain.dropFirst() + [composer.textView]) { view.nextKeyView = next }
    }
}
