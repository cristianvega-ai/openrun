import Darwin

/// The standard input of an agent program.
extension AgentProgram {
    /// Bytes that wait to go to the program, with the caller that waits.
    struct PendingInput {
        var bytes: [UInt8]
        var offset = 0
        var continuation: CheckedContinuation<Void, any Error>
    }

    /// Sends bytes to the standard input of the program, after every earlier
    /// write. Returns when the pipe took all of them. The wait blocks no
    /// thread, so a program that reads nothing holds only its caller.
    ///
    /// - Throws: `AgentProgramError.programEnded` when the program ends or
    ///   closes its input first, or when `closeInput` was called.
    public func write(_ bytes: [UInt8]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            queue.async {
                guard !self.inputIsClosing, self.inputDescriptor >= 0 else {
                    continuation.resume(throwing: AgentProgramError.programEnded)
                    return
                }
                self.pendingInput.append(PendingInput(bytes: bytes, continuation: continuation))
                self.pumpInput()
            }
        }
    }

    /// Closes the standard input of the program after the writes that wait.
    /// Claude Code ends after its turn when its input ends.
    public func closeInput() {
        queue.async {
            self.inputIsClosing = true
            self.pumpInput()
        }
    }

    /// Writes from the front of the waiting input until the pipe takes no
    /// more. The write source fires while the pipe has room, so it runs
    /// only while input waits.
    func pumpInput() {
        while let front = pendingInput.first, inputDescriptor >= 0 {
            let rest = front.bytes.count - front.offset
            let count = rest == 0 ? 0 : front.bytes.withUnsafeBytes { Darwin.write(inputDescriptor, $0.baseAddress! + front.offset, rest) }
            if count >= 0 {
                pendingInput[0].offset += count
                if pendingInput[0].offset == front.bytes.count {
                    pendingInput.removeFirst().continuation.resume()
                    continue
                }
            }
            if count < 0 && errno == EINTR { continue }
            if count < 0 && errno != EAGAIN {
                // The program closed its input, so nothing can reach it.
                endInput()
                return
            }
            break
        }
        if pendingInput.isEmpty, inputIsClosing {
            endInput()
        }
        if pendingInput.isEmpty != inputSourceIsSuspended {
            if inputSourceIsSuspended { inputSource?.resume() } else { inputSource?.suspend() }
            inputSourceIsSuspended.toggle()
        }
    }

    /// Ends all input: the pipe closes, and each write that waits fails.
    func endInput() {
        inputIsClosing = true
        let waiting = pendingInput
        pendingInput = []
        for input in waiting { input.continuation.resume(throwing: AgentProgramError.programEnded) }
        // A suspended source runs its cancel handler only after a resume.
        if inputSourceIsSuspended {
            inputSource?.resume()
            inputSourceIsSuspended = false
        }
        inputSource?.cancel()
        inputSource = nil
    }
}
