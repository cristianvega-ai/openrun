import Foundation
import MachO

/// The identifier of this build of the session process: the UUID that
/// the linker gave the program. Each copy of one build has the same
/// identifier, and a new build has another one. The app compares it with
/// the identifier of the program in its own bundle, to know whether an
/// older session process still runs after an update.
public enum BuildIdentifier {
    /// The identifier of the program that runs, or `nil` when the program
    /// holds none.
    public static let current: String? = {
        // The program is the one image of the process that is an executable.
        let images = (0..<_dyld_image_count()).lazy.compactMap { _dyld_get_image_header($0) }
        guard let header = images.first(where: { $0.pointee.filetype == MH_EXECUTE }) else { return nil }
        var command = UnsafeRawPointer(header) + MemoryLayout<mach_header_64>.size
        for _ in 0..<header.pointee.ncmds {
            let load = command.load(as: load_command.self)
            if load.cmd == LC_UUID { return UUID(uuid: command.load(as: uuid_command.self).uuid).uuidString.lowercased() }
            command += Int(load.cmdsize)
        }
        return nil
    }()
}
