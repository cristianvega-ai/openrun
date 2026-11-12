import Foundation

/// What a row of the sessions list shows in the third pane: one terminal
/// session, one agent thread, a web page, or two panes side by side or
/// one over the other (decisions of 2026-11-10). In the session process
/// each split is a session or a thread of its own. A web page belongs to
/// the app only.
public indirect enum LayoutPane: Equatable, Sendable {
    case session(UUID)
    /// The chat of an agent thread (proposal 1 of 2026-11-10).
    case thread(UUID)
    case browser(LayoutBrowser)
    case split(LayoutSplit)

    /// The sessions of the pane in reading order: the first half of each
    /// split before the second.
    public var sessions: [UUID] {
        switch self {
        case .session(let identifier): [identifier]
        case .thread, .browser: []
        case .split(let split): split.first.sessions + split.second.sessions
        }
    }

    /// The thread that the pane shows first, when its first leaf is a
    /// thread. The row then looks like that thread.
    public var leadingThread: UUID? {
        switch self {
        case .session, .browser: nil
        case .thread(let identifier): identifier
        case .split(let split): split.first.leadingThread
        }
    }

    /// The threads of the pane in reading order.
    public var threads: [UUID] {
        switch self {
        case .session, .browser: []
        case .thread(let identifier): [identifier]
        case .split(let split): split.first.threads + split.second.threads
        }
    }

    /// The web pages of the pane in reading order.
    public var browsers: [LayoutBrowser] {
        switch self {
        case .session, .thread: []
        case .browser(let browser): [browser]
        case .split(let split): split.first.browsers + split.second.browsers
        }
    }

    /// The pane without the sessions and the threads that `keeps` refuses.
    /// The other half of a split takes the place of a half that goes away.
    /// A web page stays while a session or a thread of the pane stays.
    /// `nil` means that nothing stays.
    public func keeping(_ keeps: (UUID) -> Bool) -> LayoutPane? {
        guard let kept = filtered(keeps), !(kept.sessions.isEmpty && kept.threads.isEmpty) else { return nil }
        return kept
    }

    private func filtered(_ keeps: (UUID) -> Bool) -> LayoutPane? {
        switch self {
        case .session(let identifier), .thread(let identifier):
            return keeps(identifier) ? self : nil
        case .browser:
            return self
        case .split(var split):
            switch (split.first.filtered(keeps), split.second.filtered(keeps)) {
            case (let first?, let second?):
                (split.first, split.second) = (first, second)
                return .split(split)
            case (let one?, nil), (nil, let one?):
                return one
            case (nil, nil):
                return nil
            }
        }
    }
}

extension LayoutPane: Codable {
    private enum CodingKeys: String, CodingKey { case session, thread, browser, split }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        if let identifier = try values.decodeIfPresent(UUID.self, forKey: .session) {
            self = .session(identifier)
        } else if let identifier = try values.decodeIfPresent(UUID.self, forKey: .thread) {
            self = .thread(identifier)
        } else if let browser = try values.decodeIfPresent(LayoutBrowser.self, forKey: .browser) {
            self = .browser(browser)
        } else {
            self = .split(try values.decode(LayoutSplit.self, forKey: .split))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .session(let identifier): try values.encode(identifier, forKey: .session)
        case .thread(let identifier): try values.encode(identifier, forKey: .thread)
        case .browser(let browser): try values.encode(browser, forKey: .browser)
        case .split(let split): try values.encode(split, forKey: .split)
        }
    }
}
