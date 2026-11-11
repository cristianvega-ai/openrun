/// The newest identifiers up to a count, oldest out first.
///
/// The transcript keeps the identifiers of the items that it dropped, so
/// that a late event of such an item does not bring a part of it back. An
/// agent can send events without end, so only the newest stay.
struct RecentIdentifiers: Sendable, Hashable {
    let capacity: Int
    private var members: Set<String> = []
    private var order: [String] = []
    /// The place in `order` of the oldest identifier, once `order` is full.
    private var oldest = 0

    init(capacity: Int) {
        self.capacity = max(1, capacity)
    }

    func contains(_ identifier: String) -> Bool {
        members.contains(identifier)
    }

    var count: Int { members.count }

    mutating func insert(_ identifier: String) {
        guard members.insert(identifier).inserted else { return }
        if order.count < capacity {
            order.append(identifier)
            return
        }
        members.remove(order[oldest])
        order[oldest] = identifier
        oldest = (oldest + 1) % capacity
    }
}
