import Foundation
import Synchronization

/// The color scheme a terminal reports when a program asks for it.
public enum TerminalColorScheme: Equatable, Sendable {
    case light
    case dark

    /// The scheme of the macOS appearance of the current user.
    ///
    /// The session process has no window, so it reads the system setting
    /// itself. macOS stores a value only in dark mode: no value means light.
    ///
    /// The read is fresh, at most once each second. The session process runs
    /// no main run loop, and CFPreferences keeps a cache per process that such
    /// a process never refreshes by itself, so the reader asks for a refresh
    /// before it reads. A program that asks at every redraw would otherwise
    /// make a system call each time. An appearance change reaches a running
    /// program within about a second.
    public static func current() -> TerminalColorScheme {
        AppearanceReader.system.scheme()
    }

    /// Reads the appearance and keeps the answer for a short time.
    final class AppearanceReader: Sendable {
        static let system = AppearanceReader(
            readStyle: { readStyle(key: "AppleInterfaceStyle", applicationIdentifier: kCFPreferencesAnyApplication) }
        )

        static let refreshInterval = Duration.seconds(1)

        private struct Reading {
            let scheme: TerminalColorScheme
            let readAt: ContinuousClock.Instant
        }

        private let readStyle: @Sendable () -> String?
        private let now: @Sendable () -> ContinuousClock.Instant
        private let latest = Mutex<Reading?>(nil)

        /// - Parameters:
        ///   - readStyle: Returns the stored style, such as "Dark". Tests give
        ///     their own, so they never depend on or change the real appearance.
        ///   - now: The time. Tests move it by hand.
        init(
            readStyle: @escaping @Sendable () -> String?,
            now: @escaping @Sendable () -> ContinuousClock.Instant = { ContinuousClock.now }
        ) {
            self.readStyle = readStyle
            self.now = now
        }

        func scheme() -> TerminalColorScheme {
            latest.withLock { latest in
                let moment = now()
                if let latest, latest.readAt.duration(to: moment) < Self.refreshInterval, moment >= latest.readAt {
                    return latest.scheme
                }
                let scheme: TerminalColorScheme = readStyle() == "Dark" ? .dark : .light
                latest = Reading(scheme: scheme, readAt: moment)
                return scheme
            }
        }

        /// Reads one style value after a refresh of the cache of this process.
        static func readStyle(key: String, applicationIdentifier: CFString) -> String? {
            CFPreferencesAppSynchronize(applicationIdentifier)
            return CFPreferencesCopyValue(
                key as CFString,
                applicationIdentifier,
                kCFPreferencesCurrentUser,
                kCFPreferencesAnyHost
            ) as? String
        }
    }
}
