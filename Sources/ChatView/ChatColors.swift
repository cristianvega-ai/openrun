import TerminalTheme

/// The colors of the chat for one appearance, light or dark.
public struct ChatColors: Equatable, Hashable, Sendable {
    public var background: ChatColor
    public var text: ChatColor
    /// Quiet text, such as the state of a tool call or a notice.
    public var secondaryText: ChatColor
    /// Lines between parts, the bar of a quote, and the lines of a table.
    public var divider: ChatColor
    /// The fill behind a message of the user.
    public var userMessageBackground: ChatColor
    /// The fill behind code, output and diffs.
    public var codeBackground: ChatColor
    /// The one accent: what needs the user, such as a permission request.
    public var attention: ChatColor
    public var link: ChatColor
    /// The color of the lines that a diff adds and removes. A view shows
    /// them as a faint fill.
    public var addedLine: ChatColor
    public var removedLine: ChatColor
    public var selection: ChatColor

    public init(
        background: ChatColor, text: ChatColor, secondaryText: ChatColor, divider: ChatColor, userMessageBackground: ChatColor,
        codeBackground: ChatColor, attention: ChatColor, link: ChatColor, addedLine: ChatColor, removedLine: ChatColor,
        selection: ChatColor
    ) {
        self.background = background
        self.text = text
        self.secondaryText = secondaryText
        self.divider = divider
        self.userMessageBackground = userMessageBackground
        self.codeBackground = codeBackground
        self.attention = attention
        self.link = link
        self.addedLine = addedLine
        self.removedLine = removedLine
        self.selection = selection
    }

    /// The colors that fit a terminal theme, so the chat and a terminal
    /// beside it look like one window. Quiet fills mix the text color into
    /// the background, and the accents come from the theme's palette.
    public init(theme: TerminalTheme) {
        let background = ChatColor(theme.background)
        let text = ChatColor(theme.foreground)
        let palette = theme.firstSixteenColors.map(ChatColor.init)
        self.init(
            background: background, text: text, secondaryText: palette[8],
            divider: background.mixed(with: text, fraction: 0.13),
            userMessageBackground: background.mixed(with: text, fraction: 0.055),
            codeBackground: background.mixed(with: text, fraction: 0.035),
            attention: palette[1], link: palette[4], addedLine: palette[2], removedLine: palette[1],
            selection: ChatColor(theme.selection))
    }
}
