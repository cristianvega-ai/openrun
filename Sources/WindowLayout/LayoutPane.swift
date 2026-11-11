import Foundation

/// What a row of the sessions list shows in the third pane: one session,
/// or two panes side by side or one over the other (decision of
/// 2026-11-10). In the session process each split is a session of its own.
public indirect enum LayoutPane: Equatable, Sendable {
    case session(UUID)
    case split(LayoutSplit)

    /// The sessions of the pane in reading order: the first half of each
    /// split before the second.
    public var sessions: [UUID] {
        switch self {
        case .session(let identifier): [identifier]
        case .split(let split): split.first.sessions + split.second.sessions
        }
    }

    /// The pane without the sessions that `keeps` refuses. The other half
    /// of a split takes the place of a half that goes away. `nil` means
    /// that no session stays.
    public func keeping(_ keeps: (UUID) -> Bool) -> LayoutPane? {
        switch self {
        case .session(let identifier):
            return keeps(identifier) ? self : nil
        case .split(var split):
            switch (split.first.keeping(keeps), split.second.keeping(keeps)) {
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
    private enum CodingKeys: String, CodingKey { case session, split }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        if let identifier = try values.decodeIfPresent(UUID.self, forKey: .session) {
            self = .session(identifier)
        } else {
            self = .split(try values.decode(LayoutSplit.self, forKey: .split))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .session(let identifier): try values.encode(identifier, forKey: .session)
        case .split(let split): try values.encode(split, forKey: .split)
        }
    }
}
