import AgentProgram
import Darwin

// Starts a program on pipes after it closed the descriptor in its first
// argument. A test cannot close 0, 1 or 2 in its own process, because
// other tests run there at the same time. The exit status tells the
// result, because standard output or error can be closed: 0 when the
// three pipes worked, and 1 when they did not.
guard let argument = CommandLine.arguments.dropFirst().first, let closed = Int32(argument) else { exit(2) }
close(closed)
let launch = AgentProgramLaunch(
    executablePath: "/bin/sh", arguments: ["-c", "read line && echo \"got $line\" && echo problem >&2"], folder: "/",
    environment: ["PATH": "/usr/bin:/bin"])
guard let program = try? AgentProgram(launching: launch) else { exit(1) }
guard (try? await program.write(Array("hello\n".utf8))) != nil else { exit(1) }
program.closeInput()
var output: [UInt8] = []
for await chunk in program.output {
    output += chunk
    program.markOutputConsumed(chunk.count)
}
let worked = await program.waitForExit() == .exited(status: 0) && output == Array("got hello\n".utf8)
exit(worked && program.standardErrorText == "problem\n" ? 0 : 1)
