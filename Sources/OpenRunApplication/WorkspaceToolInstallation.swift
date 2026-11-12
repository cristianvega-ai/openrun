import AppKit
import ToolInstallation

/// OpenRun > Install Command-Line Tool: the command `openrun` for the
/// terminals outside OpenRun.
extension Workspace {
    @objc func installCommandLineTool(_ sender: Any?) {
        guard let installation = toolInstallation else { return }
        confirmToolInstallation(installation) { [weak self] agreed in
            guard agreed, let self else { return }
            do {
                // The folder belongs to the administrator on most Macs, and macOS then asks for the password.
                if installation.needsAdministrator { try runAsAdministrator(installation.shellCommand) } else { try installation.install() }
                tellToolInstallation("The command openrun is installed", "A new terminal window finds it at \(installation.linkPath).")
            } catch let error as AdministratorCommandFailure where error.wasCancelled {
                // The user closed the password question, which needs no message.
            } catch {
                tellToolInstallation("The command openrun was not installed", "\(error.localizedDescription)")
            }
        }
    }

    /// Asks before the install. The first button installs.
    func askBeforeToolInstallation(_ installation: ToolInstallation, then answer: @escaping (Bool) -> Void) {
        let alert = NSAlert()
        alert.messageText = installation.isInstalled ? "The command openrun is installed. Install it again?" : "Install the command openrun?"
        alert.informativeText = "OpenRun puts a link to its command-line tool in \(installation.folder), so the command works in every terminal. "
            + (installation.needsAdministrator ? "macOS asks for the password of an administrator." : "")
        alert.addButton(withTitle: "Install")
        alert.addButton(withTitle: "Cancel")
        answer(ModalAlert.runStandardModal(alert) == .alertFirstButtonReturn)
    }

    func showToolInstallationResult(_ title: String, _ message: String) {
        let alert = NSAlert()
        (alert.messageText, alert.informativeText) = (title, message)
        _ = ModalAlert.runStandardModal(alert)
    }
}

/// A command for the shell that did not run with the rights of the administrator.
struct AdministratorCommandFailure: Error, LocalizedError {
    let message: String
    /// The user closed the password question of macOS.
    let wasCancelled: Bool
    var errorDescription: String? { message }

    /// Runs the command with the rights of the administrator. macOS asks
    /// the user for the password, and OpenRun never sees it.
    static func run(_ command: String) throws {
        let source = "do shell script \"" + command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            + "\" with administrator privileges"
        var failure: NSDictionary?
        guard NSAppleScript(source: source)?.executeAndReturnError(&failure) == nil, let failure else { return }
        let number = failure[NSAppleScript.errorNumber] as? Int
        throw AdministratorCommandFailure(message: failure[NSAppleScript.errorMessage] as? String ?? "macOS did not run the command.", wasCancelled: number == -128)
    }
}
