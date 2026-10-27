import Carbon.HIToolbox
import TerminalEmulation

/// Gives the physical key for the key code of a macOS key event. A key code
/// follows the place of the key on the keyboard, so it does not change with
/// the keyboard layout. libghostty-vt wants this place and not the character.
enum KeyCodeTable {
    static func physicalKey(forKeyCode keyCode: UInt16) -> PhysicalKey {
        keys[Int(keyCode)] ?? .unidentified
    }

    // The `kVK_` constants are from HIToolbox.
    static let keys: [Int: PhysicalKey] = [
        kVK_ANSI_A: .a, kVK_ANSI_B: .b, kVK_ANSI_C: .c, kVK_ANSI_D: .d, kVK_ANSI_E: .e, kVK_ANSI_F: .f,
        kVK_ANSI_G: .g, kVK_ANSI_H: .h, kVK_ANSI_I: .i, kVK_ANSI_J: .j, kVK_ANSI_K: .k, kVK_ANSI_L: .l,
        kVK_ANSI_M: .m, kVK_ANSI_N: .n, kVK_ANSI_O: .o, kVK_ANSI_P: .p, kVK_ANSI_Q: .q, kVK_ANSI_R: .r,
        kVK_ANSI_S: .s, kVK_ANSI_T: .t, kVK_ANSI_U: .u, kVK_ANSI_V: .v, kVK_ANSI_W: .w, kVK_ANSI_X: .x,
        kVK_ANSI_Y: .y, kVK_ANSI_Z: .z,
        kVK_ANSI_0: .digit0, kVK_ANSI_1: .digit1, kVK_ANSI_2: .digit2, kVK_ANSI_3: .digit3, kVK_ANSI_4: .digit4,
        kVK_ANSI_5: .digit5, kVK_ANSI_6: .digit6, kVK_ANSI_7: .digit7, kVK_ANSI_8: .digit8, kVK_ANSI_9: .digit9,
        kVK_ANSI_Grave: .backquote, kVK_ANSI_Backslash: .backslash, kVK_ANSI_LeftBracket: .bracketLeft,
        kVK_ANSI_RightBracket: .bracketRight, kVK_ANSI_Comma: .comma, kVK_ANSI_Equal: .equal,
        kVK_ANSI_Minus: .minus, kVK_ANSI_Period: .period, kVK_ANSI_Quote: .quote,
        kVK_ANSI_Semicolon: .semicolon, kVK_ANSI_Slash: .slash, kVK_ISO_Section: .internationalBackslash,
        kVK_JIS_Yen: .internationalYen, kVK_JIS_Underscore: .internationalRo,
        kVK_Return: .enter, kVK_Tab: .tab, kVK_Space: .space, kVK_Delete: .backspace, kVK_Escape: .escape,
        kVK_ForwardDelete: .delete,
        // PC keyboards have an Insert key where a Mac keyboard has the Help key.
        kVK_Help: .insert,
        kVK_Home: .home, kVK_End: .end, kVK_PageUp: .pageUp, kVK_PageDown: .pageDown,
        kVK_LeftArrow: .arrowLeft, kVK_RightArrow: .arrowRight, kVK_UpArrow: .arrowUp, kVK_DownArrow: .arrowDown,
        kVK_Command: .metaLeft, kVK_RightCommand: .metaRight, kVK_Shift: .shiftLeft, kVK_RightShift: .shiftRight,
        kVK_Option: .altLeft, kVK_RightOption: .altRight, kVK_Control: .controlLeft, kVK_RightControl: .controlRight,
        kVK_CapsLock: .capsLock, kVK_Function: .function,
        kVK_F1: .f1, kVK_F2: .f2, kVK_F3: .f3, kVK_F4: .f4, kVK_F5: .f5, kVK_F6: .f6, kVK_F7: .f7, kVK_F8: .f8,
        kVK_F9: .f9, kVK_F10: .f10, kVK_F11: .f11, kVK_F12: .f12, kVK_F13: .f13, kVK_F14: .f14, kVK_F15: .f15,
        kVK_F16: .f16, kVK_F17: .f17, kVK_F18: .f18, kVK_F19: .f19, kVK_F20: .f20,
        kVK_ANSI_Keypad0: .numberPad0, kVK_ANSI_Keypad1: .numberPad1, kVK_ANSI_Keypad2: .numberPad2,
        kVK_ANSI_Keypad3: .numberPad3, kVK_ANSI_Keypad4: .numberPad4, kVK_ANSI_Keypad5: .numberPad5,
        kVK_ANSI_Keypad6: .numberPad6, kVK_ANSI_Keypad7: .numberPad7, kVK_ANSI_Keypad8: .numberPad8,
        kVK_ANSI_Keypad9: .numberPad9, kVK_ANSI_KeypadDecimal: .numberPadDecimal,
        kVK_ANSI_KeypadMultiply: .numberPadMultiply, kVK_ANSI_KeypadPlus: .numberPadAdd,
        // The Clear key of a Mac keypad is the Num Lock key of other keyboards.
        kVK_ANSI_KeypadClear: .numberLock, kVK_ANSI_KeypadDivide: .numberPadDivide,
        kVK_ANSI_KeypadEnter: .numberPadEnter, kVK_ANSI_KeypadMinus: .numberPadSubtract,
        kVK_ANSI_KeypadEquals: .numberPadEqual, kVK_JIS_KeypadComma: .numberPadComma,
    ]
}
