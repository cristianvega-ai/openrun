/// How long one turn of parsing may last. The budget starts when it is made.
struct ParseBudget {
    let limit: Duration
    private let start = ContinuousClock.now

    init(limit: Duration) {
        self.limit = limit
    }

    var isUsed: Bool {
        start.duration(to: .now) >= limit
    }
}
