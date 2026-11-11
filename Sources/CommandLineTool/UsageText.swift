/// The help text of the command-line tool.
enum UsageText {
    static let full = """
        Usage: openrun COMMAND [OPTIONS]

        Commands:
          new [--folder PATH] [-- PROGRAM ARGUMENTS...]
                          Start a session and print its identifier. Without a program
                          it runs your login shell. The folder defaults to the current one.
          list [--json]   Show every session: identifier, folder and command.
                          With --json, print every fact of each session as JSON.
          attach IDENTIFIER
                          Show a session and type into it. Control-] detaches.
          read IDENTIFIER [--scrollback]
                          Print the screen of a session as plain text. With --scrollback,
                          print the lines above the screen too.
          send IDENTIFIER [--enter] TEXT
                          Type TEXT into a session. --enter adds a carriage return.
                          After --, everything is text.
          kill IDENTIFIER End a session and its program.
          rename IDENTIFIER [NAME]
                          Give a session a name. Without NAME, remove the name.
          notify [--session IDENTIFIER] TEXT
                          Raise the alert of your own session, or of the session
                          after --session. Without a session process, tell the
                          terminal with OSC 777. Exits with 0 when the alert went
                          out, and with 1 otherwise, also for wrong arguments.
          help            Show this text.

        Options for every command:
          --socket PATH   The socket of the session process. The default is
                          OPENRUN_SOCKET, or
                          ~/Library/Application Support/OpenRun/session.socket.

        An IDENTIFIER can be any unique start of a session identifier.
        A program in a session may rename or alert only its own session.
        """

    static let hint = "Run 'openrun help' for the list of commands."
}
