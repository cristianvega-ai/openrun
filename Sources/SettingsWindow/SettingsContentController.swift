import AppKit
import PaneAppearance

/// The right part of the settings window: the title of the pane in the
/// top row, and the sections of that pane under it.
@MainActor final class SettingsContentController: NSViewController {
    let panes: [SettingsPaneController]
    let titleLabel = NSTextField(labelWithString: "")
    private let scroll = OverlayScrollView()
    private(set) var shownPane = 0

    init(panes: [SettingsPaneController]) {
        self.panes = panes
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func loadView() {
        let root = PaneBackgroundView(color: PaneColor.terminalBackground), topRow = PaneTopRow(background: PaneColor.terminalBackground)
        (titleLabel.font, titleLabel.textColor) = (.systemFont(ofSize: 15, weight: .semibold), PaneColor.text)
        topRow.leadingSpace = 32
        topRow.leadingItems.addArrangedSubview(titleLabel)
        let stack = NSStackView(views: panes.map(\.view)), document = SettingsDocumentView()
        (stack.orientation, stack.alignment, stack.spacing) = (.vertical, .leading, 26)
        document.addSubview(stack)
        (scroll.documentView, scroll.drawsBackground, scroll.hasVerticalScroller) = (document, false, true)
        for view in [topRow, scroll, stack, document] as [NSView] { view.translatesAutoresizingMaskIntoConstraints = false }
        root.addSubview(scroll)
        root.addSubview(topRow)
        NSLayoutConstraint.activate([
            topRow.topAnchor.constraint(equalTo: root.topAnchor), topRow.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            topRow.trailingAnchor.constraint(equalTo: root.trailingAnchor), scroll.topAnchor.constraint(equalTo: topRow.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor), document.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            document.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor), document.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: document.topAnchor), stack.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -32),
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 32), stack.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -32),
        ])
        view = root
        show(pane: shownPane)
    }

    /// Shows one pane, from its top.
    func show(pane index: Int) {
        loadViewIfNeeded()
        shownPane = index
        for (index, pane) in panes.enumerated() { pane.view.isHidden = index != shownPane }
        titleLabel.stringValue = panes[shownPane].pane.title
        scroll.contentView.scroll(to: .zero)
        scroll.reflectScrolledClipView(scroll.contentView)
    }
}
