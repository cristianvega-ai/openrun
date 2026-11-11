import Darwin

/// The standard output of an agent program.
extension AgentProgram {
    /// Tells the object that the reader dealt with this many bytes of
    /// output. It reads on when the backlog is small enough.
    public func markOutputConsumed(_ byteCount: Int) {
        queue.async {
            self.unconsumedBytes -= byteCount
            if self.outputSourceIsSuspended, self.unconsumedBytes <= Self.unconsumedLowMark {
                self.outputSource?.resume()
                self.outputSourceIsSuspended = false
            }
        }
    }

    /// Reads what waits on standard output. Past the high mark it stops,
    /// unless the program has ended and the rest must be read now.
    func readOutput(honoringBackpressure: Bool = true) {
        guard outputDescriptor >= 0 else { return }
        var buffer = [UInt8](repeating: 0, count: Self.readChunkSize)
        while true {
            let count = read(outputDescriptor, &buffer, buffer.count)
            if count > 0 {
                outputContinuation.yield(Array(buffer[0..<count]))
                unconsumedBytes += count
                if honoringBackpressure, unconsumedBytes >= Self.unconsumedHighMark, !outputSourceIsSuspended {
                    outputSource?.suspend()
                    outputSourceIsSuspended = true
                    return
                }
                continue
            }
            if count < 0 && errno == EINTR { continue }
            // At the end, the source would fire again and again.
            if count == 0 || errno != EAGAIN { outputSource?.cancel() }
            return
        }
    }
}
