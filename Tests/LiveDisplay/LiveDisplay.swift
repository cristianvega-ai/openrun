import AppKit
import CoreGraphics
import Testing

/// Whether this Mac can show a frame now. While the screen is locked or the
/// display sleeps, display links do not fire and a window capture gives
/// nothing, so a test that waits for a drawn frame fails every time.
public enum LiveDisplay {
    /// Why no frame can be drawn now, or `nil` when one can.
    @MainActor public static var reasonItIsMissing: String? {
        if NSScreen.main == nil { return "there is no screen" }
        if CGDisplayIsAsleep(CGMainDisplayID()) != 0 { return "the display sleeps" }
        let session = CGSessionCopyCurrentDictionary() as? [String: Any]
        if session?["CGSSessionScreenIsLocked"] as? Bool == true { return "the screen is locked" }
        return nil
    }
}

extension Trait where Self == ConditionTrait {
    /// Skips a test that needs a drawn frame or a picture of a window when the
    /// screen is locked, the display sleeps, or there is no screen.
    public static var needsLiveDisplay: Self {
        .enabled("This test needs an unlocked screen and a display that is awake.") {
            await MainActor.run { LiveDisplay.reasonItIsMissing == nil }
        }
    }
}
