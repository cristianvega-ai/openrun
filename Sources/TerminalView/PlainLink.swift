import TerminalRendering

/// A web address in the plain text of the screen, and the cells that it covers.
struct PlainLink: Equatable {
    let address: String
    let runs: [ViewportCellRun]
}
