import AppKit
import PaneAppearance

/// The right part of the settings window: the title of the pane in the
/// top row, and the sections of that pane under it. A search shows the
/// rows of every pane that hold the words of the search.
@MainActor final class SettingsContentController: NSViewController {
    let panes: [SettingsPaneController]
    let titleLabel = NSTextField(labelWithString: "")
    let emptyLabel = NSTextField(labelWithString: "No Setting Has These Words")
    private let scroll = OverlayScrollView()
    private(set) var shownPane = 0
    private var words: [String] = []
    var isSearching: Bool { !words.isEmpty }

    init(panes: [SettingsPaneController]) {
        self.panes = panes
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func loadView() {
        let root = PaneBackgroundView(color: PaneColor.terminalBackground), topRow = PaneTopRow(background: PaneColor.terminalBackground)
        (titleLabel.font, titleLabel.textColor) = (.systemFont(ofSize: 15, weight: .semibold), PaneColor.text)
        (emptyLabel.textColor, emptyLabel.isHidden, topRow.leadingSpace) = (PaneColor.quietText, true, 32)
        topRow.leadingItems.addArrangedSubview(titleLabel)
        let stack = NSStackView(views: panes.map(\.view) + [emptyLabel]), document = SettingsDocumentView()
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
        refresh()
    }

    /// Shows one pane, and ends a search.
    func show(pane index: Int) {
        (shownPane, words) = (index, [])
        refresh()
    }

    /// Shows the rows of each pane that hold every word of `text`. An
    /// empty text shows the pane from before the search.
    func search(_ text: String) {
        words = text.lowercased().split(separator: " ").map(String.init)
        refresh()
    }

    private func refresh() {
        loadViewIfNeeded()
        var showsRow = false
        for (index, pane) in panes.enumerated() {
            let holdsWords = pane.filter(words)
            pane.view.isHidden = words.isEmpty ? index != shownPane : !holdsWords
            pane.heading.isHidden = words.isEmpty
            showsRow = showsRow || !pane.view.isHidden
        }
        (titleLabel.stringValue, emptyLabel.isHidden) = (words.isEmpty ? panes[shownPane].pane.title : "Search", showsRow)
        // Each pane and each search starts at its top.
        scroll.contentView.scroll(to: .zero)
        scroll.reflectScrolledClipView(scroll.contentView)
    }
}
