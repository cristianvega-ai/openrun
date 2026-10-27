/// The message that a client sends to the Mach service of the launch agent.
/// It holds nothing: its arrival is what makes launchd start the program.
struct WakeRequest: Codable, Sendable {}
