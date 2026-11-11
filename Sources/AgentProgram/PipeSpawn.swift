import Darwin

/// Starts a program with three new pipes as its standard input, output and
/// error, as the leader of a new process group.
///
/// `posix_spawn` does the work in the kernel, so no Swift code runs in a
/// child that shares the memory of a process with other threads. With
/// `POSIX_SPAWN_CLOEXEC_DEFAULT` the program gets no descriptor but the
/// three pipes. The signals that the session process ignores or blocks
/// go back to their defaults.
enum PipeSpawn {
    struct Started {
        var processIdentifier: pid_t
        var inputDescriptor: Int32
        var outputDescriptor: Int32
        var errorDescriptor: Int32
    }

    static func start(_ launch: AgentProgramLaunch) throws -> Started {
        try launch.checkValues()
        try launch.checkFolder()
        let program = try launch.resolvedExecutablePath()
        var pipes: [(read: Int32, write: Int32)] = []
        defer { for pipe in pipes { close(pipe.read); close(pipe.write) } }
        for _ in 0..<3 {
            var descriptors: [Int32] = [-1, -1]
            guard pipe(&descriptors) == 0 else { throw AgentProgramError.systemCallFailed(function: "pipe", code: errno) }
            let ends = descriptors.map(raised)
            pipes.append((ends[0], ends[1]))
            guard !ends.contains(-1) else { throw AgentProgramError.systemCallFailed(function: "fcntl", code: errno) }
        }
        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_adddup2(&actions, pipes[0].read, 0)
        posix_spawn_file_actions_adddup2(&actions, pipes[1].write, 1)
        posix_spawn_file_actions_adddup2(&actions, pipes[2].write, 2)
        posix_spawn_file_actions_addchdir(&actions, launch.folder)
        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        let flags = POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK
        posix_spawnattr_setflags(&attributes, Int16(flags))
        posix_spawnattr_setpgroup(&attributes, 0)
        var noSignals = sigset_t()
        sigemptyset(&noSignals)
        posix_spawnattr_setsigmask(&attributes, &noSignals)
        var allSignals = sigset_t()
        sigfillset(&allSignals)
        posix_spawnattr_setsigdefault(&attributes, &allSignals)

        let arguments = [program] + launch.arguments
        let environment = launch.environment.map { "\($0.key)=\($0.value)" }
        var processIdentifier: pid_t = 0
        var result = spawn(&processIdentifier, program, arguments, environment, &actions, &attributes)
        // A file that the kernel cannot run and that has no `#!` line fails
        // with ENOEXEC. Shells then run it as a script, and so does this.
        if result == ENOEXEC {
            result = spawn(&processIdentifier, "/bin/sh", ["sh", "--", program] + launch.arguments, environment, &actions, &attributes)
            if result != 0 { result = ENOEXEC }
        }
        guard result == 0 else { throw AgentProgramError.systemCallFailed(function: "posix_spawn", code: result) }
        let started = Started(
            processIdentifier: processIdentifier, inputDescriptor: pipes[0].write,
            outputDescriptor: pipes[1].read, errorDescriptor: pipes[2].read)
        // The parent keeps only its own ends. The defer closes the others.
        pipes[0].write = -1
        pipes[1].read = -1
        pipes[2].read = -1
        _ = fcntl(started.inputDescriptor, F_SETFL, O_NONBLOCK)
        _ = fcntl(started.inputDescriptor, F_SETNOSIGPIPE, 1)
        _ = fcntl(started.outputDescriptor, F_SETFL, O_NONBLOCK)
        _ = fcntl(started.errorDescriptor, F_SETFL, O_NONBLOCK)
        return started
    }

    /// Moves a new pipe end above 2, with close-on-exec, so that programs
    /// that other threads start do not get it. When the parent has 0, 1 or
    /// 2 closed, `pipe` can return that number. An end at a target of the
    /// `dup2` actions would then stay close-on-exec, because `dup2` onto
    /// itself keeps the flag, or a later action would overwrite it.
    /// Returns -1, with `errno` set, when the move fails.
    private static func raised(_ descriptor: Int32) -> Int32 {
        let moved = fcntl(descriptor, F_DUPFD_CLOEXEC, 3)
        let code = errno
        close(descriptor)
        errno = code
        return moved
    }

    private static func spawn(
        _ processIdentifier: inout pid_t, _ path: String, _ arguments: [String], _ environment: [String],
        _ actions: inout posix_spawn_file_actions_t?, _ attributes: inout posix_spawnattr_t?
    ) -> Int32 {
        let argumentStrings = arguments.map { strdup($0) } + [nil]
        let environmentStrings = environment.map { strdup($0) } + [nil]
        defer {
            argumentStrings.forEach { free($0) }
            environmentStrings.forEach { free($0) }
        }
        return posix_spawn(&processIdentifier, path, &actions, &attributes, argumentStrings, environmentStrings)
    }
}
