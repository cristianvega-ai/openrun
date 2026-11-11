/// The models that the menu of a thread offers: the names that
/// `claude --model` takes for the newest model of each family.
public enum ClaudeCodeModelChoices {
    public static let offered = ["fable", "opus", "sonnet", "haiku"]

    /// The offered models, and after them each of `others` that is not
    /// one of them, such as a full model name from the settings.
    public static func choices(with others: [String]) -> [String] {
        others.reduce(into: offered) { choices, model in
            if !choices.contains(model) { choices.append(model) }
        }
    }
}
