import PseudoTerminal
@testable import SessionProcess
import Testing

@Suite struct SessionActivityTests {
    private static let start = ContinuousClock.now

    private static func foreground(_ name: String, leadsSession: Bool, lineMode: Bool) -> ForegroundState {
        ForegroundState(program: ForegroundProgram(name: name, arguments: [name]), leadsSession: leadsSession, currentFolder: "/", isInLineMode: lineMode)
    }

    @Test func outputIsWorkUntilTheQuietTimePasses() {
        var activity = SessionActivity()
        activity.noteForeground(Self.foreground("claude", leadsSession: false, lineMode: false))
        #expect(!activity.isInProgress(at: Self.start))
        activity.noteOutput(at: Self.start)
        #expect(activity.isInProgress(at: Self.start + .seconds(1)))
        #expect(!activity.isQuiet(at: Self.start + .seconds(1)))
        #expect(!activity.isInProgress(at: Self.start + SessionActivity.quietTime))
        #expect(activity.isQuiet(at: Self.start + SessionActivity.quietTime))
    }

    /// zsh draws its prompt and echoes keys in raw mode, and sh without a
    /// line editor reads its line in line mode. Neither is work.
    @Test(arguments: [(true, false), (true, true), (false, false)])
    func aShellAtItsPromptIsNotInProgress(leadsSession: Bool, lineMode: Bool) {
        var activity = SessionActivity()
        activity.noteForeground(Self.foreground("zsh", leadsSession: leadsSession, lineMode: lineMode))
        activity.noteOutput(at: Self.start)
        #expect(!activity.isInProgress(at: Self.start))
        #expect(!activity.isQuiet(at: Self.start))
    }

    /// A build, a script or a test can work for minutes without output.
    @Test(arguments: [("make", true), ("sleep", false), ("bash", false)])
    func aCommandInLineModeIsInProgressWithoutOutput(name: String, leadsSession: Bool) {
        var activity = SessionActivity()
        activity.noteForeground(Self.foreground(name, leadsSession: leadsSession, lineMode: true))
        #expect(activity.isInProgress(at: Self.start + .seconds(3600)))
    }

    @Test func aBellRightAfterATypedKeyRaisesNoAlert() {
        var activity = SessionActivity()
        #expect(activity.bellRaisesAlert(at: Self.start))
        activity.noteInput(at: Self.start, isTyped: false)
        #expect(activity.bellRaisesAlert(at: Self.start))
        activity.noteInput(at: Self.start, isTyped: true)
        #expect(!activity.bellRaisesAlert(at: Self.start + .milliseconds(500)))
        #expect(activity.bellRaisesAlert(at: Self.start + SessionActivity.bellAnswerTime))
    }

    /// `sh -c` and `bash build.sh` run commands and have no prompt.
    @Test(arguments: [["sh", "-c", "make"], ["bash", "build.sh"]])
    func aShellWithACommandOrAScriptWorks(arguments: [String]) {
        var activity = SessionActivity()
        let program = ForegroundProgram(name: arguments[0], arguments: arguments)
        activity.noteForeground(ForegroundState(program: program, leadsSession: true, currentFolder: "/", isInLineMode: false))
        activity.noteOutput(at: Self.start)
        #expect(activity.isInProgress(at: Self.start))
    }
}
