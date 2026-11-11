import ClaudeCodeAgent
import Testing

/// The choices of the menus of a thread with Claude Code.
@Suite struct ClaudeCodeChoicesTests {
    @Test func theModesGoFromTheStrictestToTheWidest() {
        let order = ClaudeCodePermissionMode.fromStrictestToWidest
        #expect(order.map(\.rawValue) == ["plan", "dontAsk", "default", "acceptEdits", "auto"])
        #expect(Set(order) == Set(ClaudeCodePermissionMode.allCases) && order.count == ClaudeCodePermissionMode.allCases.count)
    }

    @Test func aThreadCanTakeEachModeUpToTheLimit() {
        #expect(ClaudeCodePermissionMode.modes(upTo: .plan) == [.plan])
        #expect(ClaudeCodePermissionMode.modes(upTo: .standard) == [.plan, .doNotAsk, .standard])
        #expect(ClaudeCodePermissionMode.modes(upTo: .automatic) == ClaudeCodePermissionMode.fromStrictestToWidest)
    }

    @Test func theMenuOfTheModelsHoldsEachOtherModelOnce() {
        #expect(ClaudeCodeModelChoices.choices(with: []) == ["fable", "opus", "sonnet", "haiku"])
        #expect(ClaudeCodeModelChoices.choices(with: ["opus", "claude-opus-5-5", "claude-opus-5-5"]) == ["fable", "opus", "sonnet", "haiku", "claude-opus-5-5"])
    }
}
