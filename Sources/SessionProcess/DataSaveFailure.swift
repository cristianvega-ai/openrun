/// A change of the projects or the settings could not be saved, so it did
/// not happen: the state in memory stays the state before the change.
///
/// A change that a client was told of must survive a crash right after the
/// answer, so the answer waits for the save, and a failed save is a failed
/// change.
struct DataSaveFailure: Error, CustomStringConvertible {
    /// What the change was of, such as "the projects".
    let subject: String
    /// The error of the save. A path in it is quoted (`QuotedText`).
    let reason: String

    var description: String {
        "The change of \(subject) could not be saved, so nothing changed: \(reason)"
    }
}
