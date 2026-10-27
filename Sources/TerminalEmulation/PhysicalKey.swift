import GhosttyVt

/// A physical key, independent of the keyboard layout. The names follow
/// the W3C UI Events KeyboardEvent code values that libghostty-vt uses.
public enum PhysicalKey: Sendable, CaseIterable {
    case unidentified
    case a, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p, q, r, s, t, u
    case v, w, x, y, z
    case digit0, digit1, digit2, digit3, digit4, digit5, digit6, digit7
    case digit8, digit9
    case backquote, backslash, bracketLeft, bracketRight, comma, equal
    case minus, period, quote, semicolon, slash, internationalBackslash
    case internationalRo, internationalYen
    case space, tab, enter, escape, backspace, delete, help, insert, home, end
    case pageUp, pageDown, arrowUp, arrowDown, arrowLeft, arrowRight
    case shiftLeft, shiftRight, controlLeft, controlRight, altLeft
    case altRight, metaLeft, metaRight, capsLock, contextMenu
    case numberLock, numberPad0, numberPad1, numberPad2, numberPad3
    case numberPad4, numberPad5, numberPad6, numberPad7, numberPad8
    case numberPad9, numberPadAdd, numberPadSubtract, numberPadMultiply
    case numberPadDivide, numberPadDecimal, numberPadEnter
    case numberPadEqual, numberPadClear, numberPadComma
    case f1, f2, f3, f4, f5, f6, f7, f8, f9, f10, f11, f12, f13, f14
    case f15, f16, f17, f18, f19, f20, function

    var raw: GhosttyKey {
        switch self {
        case .unidentified: GHOSTTY_KEY_UNIDENTIFIED
        case .a: GHOSTTY_KEY_A
        case .b: GHOSTTY_KEY_B
        case .c: GHOSTTY_KEY_C
        case .d: GHOSTTY_KEY_D
        case .e: GHOSTTY_KEY_E
        case .f: GHOSTTY_KEY_F
        case .g: GHOSTTY_KEY_G
        case .h: GHOSTTY_KEY_H
        case .i: GHOSTTY_KEY_I
        case .j: GHOSTTY_KEY_J
        case .k: GHOSTTY_KEY_K
        case .l: GHOSTTY_KEY_L
        case .m: GHOSTTY_KEY_M
        case .n: GHOSTTY_KEY_N
        case .o: GHOSTTY_KEY_O
        case .p: GHOSTTY_KEY_P
        case .q: GHOSTTY_KEY_Q
        case .r: GHOSTTY_KEY_R
        case .s: GHOSTTY_KEY_S
        case .t: GHOSTTY_KEY_T
        case .u: GHOSTTY_KEY_U
        case .v: GHOSTTY_KEY_V
        case .w: GHOSTTY_KEY_W
        case .x: GHOSTTY_KEY_X
        case .y: GHOSTTY_KEY_Y
        case .z: GHOSTTY_KEY_Z
        case .digit0: GHOSTTY_KEY_DIGIT_0
        case .digit1: GHOSTTY_KEY_DIGIT_1
        case .digit2: GHOSTTY_KEY_DIGIT_2
        case .digit3: GHOSTTY_KEY_DIGIT_3
        case .digit4: GHOSTTY_KEY_DIGIT_4
        case .digit5: GHOSTTY_KEY_DIGIT_5
        case .digit6: GHOSTTY_KEY_DIGIT_6
        case .digit7: GHOSTTY_KEY_DIGIT_7
        case .digit8: GHOSTTY_KEY_DIGIT_8
        case .digit9: GHOSTTY_KEY_DIGIT_9
        case .backquote: GHOSTTY_KEY_BACKQUOTE
        case .backslash: GHOSTTY_KEY_BACKSLASH
        case .bracketLeft: GHOSTTY_KEY_BRACKET_LEFT
        case .bracketRight: GHOSTTY_KEY_BRACKET_RIGHT
        case .comma: GHOSTTY_KEY_COMMA
        case .equal: GHOSTTY_KEY_EQUAL
        case .minus: GHOSTTY_KEY_MINUS
        case .period: GHOSTTY_KEY_PERIOD
        case .quote: GHOSTTY_KEY_QUOTE
        case .semicolon: GHOSTTY_KEY_SEMICOLON
        case .slash: GHOSTTY_KEY_SLASH
        case .internationalBackslash: GHOSTTY_KEY_INTL_BACKSLASH
        case .internationalRo: GHOSTTY_KEY_INTL_RO
        case .internationalYen: GHOSTTY_KEY_INTL_YEN
        case .space: GHOSTTY_KEY_SPACE
        case .tab: GHOSTTY_KEY_TAB
        case .enter: GHOSTTY_KEY_ENTER
        case .escape: GHOSTTY_KEY_ESCAPE
        case .backspace: GHOSTTY_KEY_BACKSPACE
        case .delete: GHOSTTY_KEY_DELETE
        case .help: GHOSTTY_KEY_HELP
        case .insert: GHOSTTY_KEY_INSERT
        case .home: GHOSTTY_KEY_HOME
        case .end: GHOSTTY_KEY_END
        case .pageUp: GHOSTTY_KEY_PAGE_UP
        case .pageDown: GHOSTTY_KEY_PAGE_DOWN
        case .arrowUp: GHOSTTY_KEY_ARROW_UP
        case .arrowDown: GHOSTTY_KEY_ARROW_DOWN
        case .arrowLeft: GHOSTTY_KEY_ARROW_LEFT
        case .arrowRight: GHOSTTY_KEY_ARROW_RIGHT
        case .shiftLeft: GHOSTTY_KEY_SHIFT_LEFT
        case .shiftRight: GHOSTTY_KEY_SHIFT_RIGHT
        case .controlLeft: GHOSTTY_KEY_CONTROL_LEFT
        case .controlRight: GHOSTTY_KEY_CONTROL_RIGHT
        case .altLeft: GHOSTTY_KEY_ALT_LEFT
        case .altRight: GHOSTTY_KEY_ALT_RIGHT
        case .metaLeft: GHOSTTY_KEY_META_LEFT
        case .metaRight: GHOSTTY_KEY_META_RIGHT
        case .capsLock: GHOSTTY_KEY_CAPS_LOCK
        case .contextMenu: GHOSTTY_KEY_CONTEXT_MENU
        case .numberLock: GHOSTTY_KEY_NUM_LOCK
        case .numberPad0: GHOSTTY_KEY_NUMPAD_0
        case .numberPad1: GHOSTTY_KEY_NUMPAD_1
        case .numberPad2: GHOSTTY_KEY_NUMPAD_2
        case .numberPad3: GHOSTTY_KEY_NUMPAD_3
        case .numberPad4: GHOSTTY_KEY_NUMPAD_4
        case .numberPad5: GHOSTTY_KEY_NUMPAD_5
        case .numberPad6: GHOSTTY_KEY_NUMPAD_6
        case .numberPad7: GHOSTTY_KEY_NUMPAD_7
        case .numberPad8: GHOSTTY_KEY_NUMPAD_8
        case .numberPad9: GHOSTTY_KEY_NUMPAD_9
        case .numberPadAdd: GHOSTTY_KEY_NUMPAD_ADD
        case .numberPadSubtract: GHOSTTY_KEY_NUMPAD_SUBTRACT
        case .numberPadMultiply: GHOSTTY_KEY_NUMPAD_MULTIPLY
        case .numberPadDivide: GHOSTTY_KEY_NUMPAD_DIVIDE
        case .numberPadDecimal: GHOSTTY_KEY_NUMPAD_DECIMAL
        case .numberPadEnter: GHOSTTY_KEY_NUMPAD_ENTER
        case .numberPadEqual: GHOSTTY_KEY_NUMPAD_EQUAL
        case .numberPadClear: GHOSTTY_KEY_NUMPAD_CLEAR
        case .numberPadComma: GHOSTTY_KEY_NUMPAD_COMMA
        case .f1: GHOSTTY_KEY_F1
        case .f2: GHOSTTY_KEY_F2
        case .f3: GHOSTTY_KEY_F3
        case .f4: GHOSTTY_KEY_F4
        case .f5: GHOSTTY_KEY_F5
        case .f6: GHOSTTY_KEY_F6
        case .f7: GHOSTTY_KEY_F7
        case .f8: GHOSTTY_KEY_F8
        case .f9: GHOSTTY_KEY_F9
        case .f10: GHOSTTY_KEY_F10
        case .f11: GHOSTTY_KEY_F11
        case .f12: GHOSTTY_KEY_F12
        case .f13: GHOSTTY_KEY_F13
        case .f14: GHOSTTY_KEY_F14
        case .f15: GHOSTTY_KEY_F15
        case .f16: GHOSTTY_KEY_F16
        case .f17: GHOSTTY_KEY_F17
        case .f18: GHOSTTY_KEY_F18
        case .f19: GHOSTTY_KEY_F19
        case .f20: GHOSTTY_KEY_F20
        case .function: GHOSTTY_KEY_FN
        }
    }
}
