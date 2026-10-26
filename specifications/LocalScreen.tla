----------------------------- MODULE LocalScreen ----------------------------
\* A small client model of `openrun attach`: the window size, the local copy
\* of the screen (AttachCommand.LocalScreen), a suspension, and the picture
\* that the resume draws from the local copy.
\*
\* The constant LocalScreenFollowsWindow switches one protection.
\*   TRUE   The code has this protection.  When the window changes,
\*          AttachCommand.relay resizes the local Terminal too.  TLC must
\*          find no violation.
\*   FALSE  A control that removes the protection.  The window signal sends
\*          `resize` to the session but never resizes the local Terminal.
\*          TLC must find that LocalCopyMatchesWindow is false: the local
\*          copy has the old size, and the resume then draws that stale copy.
EXTENDS Naturals

CONSTANTS LocalScreenFollowsWindow

Sizes == 1..2

\* windowSize      the size of the user's terminal window
\* localSize       the size of the local Terminal that draws the picture
\* sessionSize     the size that the session was last told
\* suspended       the tool is stopped (SIGTSTP) and the shell has the terminal
\* lastPictureSize the size at which the last picture was drawn
VARIABLES windowSize, localSize, sessionSize, suspended, lastPictureSize

variables == <<windowSize, localSize, sessionSize, suspended, lastPictureSize>>

InitialState ==
  /\ windowSize = 1
  /\ localSize = 1
  /\ sessionSize = 1
  /\ suspended = FALSE
  /\ lastPictureSize = 1

\* The user changes the window.  A correct client resizes its local Terminal
\* too, because it parses the output that follows at the window's width.
\* AttachCommand.relay does this through LocalScreen.resize.
ResizeWindow(size) ==
  /\ size # windowSize
  /\ windowSize' = size
  /\ localSize' = IF LocalScreenFollowsWindow THEN size ELSE localSize
  /\ UNCHANGED <<sessionSize, suspended, lastPictureSize>>

\* AttachCommand.relay (the resize case) and AttachCommand.send.  The window
\* signal makes the tool send `resize`.  The session resizes its Terminal and
\* the program's pseudo terminal.
SendResize ==
  /\ ~suspended
  /\ windowSize # sessionSize
  /\ sessionSize' = windowSize
  /\ UNCHANGED <<windowSize, localSize, suspended, lastPictureSize>>

\* AttachCommand.relay (the suspend case).  SIGTSTP restores the terminal and
\* stops the tool.
Suspend ==
  /\ ~suspended
  /\ suspended' = TRUE
  /\ UNCHANGED <<windowSize, localSize, sessionSize, lastPictureSize>>

\* AttachCommand.relay (the resume case) and LocalScreen.picture.  SIGCONT
\* draws the picture again from the local copy.  The picture has the size of
\* that local copy.
Resume ==
  /\ suspended
  /\ suspended' = FALSE
  /\ lastPictureSize' = localSize
  /\ UNCHANGED <<windowSize, localSize, sessionSize>>

Next ==
  \/ (\E size \in Sizes : ResizeWindow(size))
  \/ SendResize
  \/ Suspend
  \/ Resume

Specification == InitialState /\ [][Next]_variables

\* The local copy always has the size of the window.  While the tool is
\* suspended the shell owns the terminal, so the rule does not apply.
LocalCopyMatchesWindow == suspended \/ localSize = windowSize

=============================================================================
