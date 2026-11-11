import AgentConversation
import AgentProgram
import ClaudeCodeAgent
import Foundation
import PseudoTerminal

/// The process of the agent of a thread: its start, its output and its end.
extension ThreadRunner {
    /// Starts the agent. The first start of a thread gives the agent the
    /// identifier of the conversation, and each later start resumes it
    /// (decision of 2026-11-10).
    func startProcess() async throws -> AgentProgram {
        let settings = try await launchSettings()
        guard let conversation = UUID(uuidString: record.conversationIdentifier),
              let mode = ClaudeCodePermissionMode(rawValue: record.permissionMode) else {
            throw ClaudeCodeLaunchError.invalidModel
        }
        let launch = try ClaudeCodeLaunch(
            model: record.model, permissionMode: mode, conversation: record.hasConversation ? .resume(conversation) : .new(conversation),
            hookCommand: settings.hookCommand, hookArguments: settings.hookArguments)
        var additions = ["OPENRUN_THREAD": record.identifier.uuidString.lowercased()]
        if let account = record.account { additions["CLAUDE_CONFIG_DIR"] = account.settingsFolder }
        let started = try AgentProgram(launching: AgentProgramLaunch(
            executablePath: settings.program, arguments: launch.arguments, folder: record.folder,
            environment: ClaudeCodeEnvironment.make(base: settings.environment, additions: additions)))
        (program, decoder, endWasRequested) = (started, ClaudeCodeOutputDecoder(), false)
        Task { await self.read(started) }
        return started
    }

    /// Reads the output of the process until its end. The process waits
    /// in its own write while this actor has not dealt with a chunk.
    private func read(_ program: AgentProgram) async {
        for await chunk in program.output {
            await received(decoder.decode(chunk))
            program.markOutputConsumed(chunk.count)
        }
        await received(decoder.finish())
        await ended(program, exit: await program.waitForExit())
    }

    private func received(_ events: [ConversationEvent]) async {
        let stateBefore = transcript.state
        var turnEnded = false
        for event in events {
            emit(event.kind, sourceLine: event.sourceLine)
            if case .turnEnded = event.kind { turnEnded = true }
        }
        if turnEnded {
            // The agent has the conversation now, so each later start resumes it.
            (activeMessage, record.hasConversation, record.lastActivityAt) = (nil, true, Date())
        }
        if turnEnded || transcript.state != stateBefore { await changed(self) }
    }

    /// The process ended: by a stop, at the quiet time, by itself, or
    /// with a failure. A turn that ran ends with it.
    private func ended(_ ended: AgentProgram, exit: ProgramExit) async {
        guard program === ended else { return }
        program = nil
        let (status, signal): (Int32?, Int32?) = switch exit {
        case .exited(let status): (status, nil)
        case .signaled(let signal): (nil, signal)
        }
        let errorText = ended.standardErrorText
        emit(.processEnded(ProcessEnd(exitStatus: status, signal: signal, wasRequested: endWasRequested, standardErrorText: errorText.isEmpty ? nil : errorText)))
        activeMessage = nil
        await changed(self)
    }

    /// Ends a process that the thread does not need now. The agent ends
    /// by itself when its input closes. One that does not gets a signal.
    func endProcess() async {
        guard let program else { return }
        endWasRequested = true
        program.closeInput()
        await endAfterGrace(program)
    }

    /// Gives the process the grace period to end, and then ends it.
    func endAfterGrace(_ ending: AgentProgram) async {
        let deadline = ContinuousClock.now + Self.endGracePeriod
        while program === ending, ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(20)) }
        if program === ending { await ending.terminate(gracePeriod: .seconds(1)) }
    }
}
