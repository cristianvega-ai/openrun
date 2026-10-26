import GhosttyVt

/// A physical key, independent of the keyboard layout. The names follow
/// the W3C UI Events KeyboardEvent code values that libghostty-vt uses.
public enum PhysicalKey: Sendable, CaseIterable {
    case unidentified
    case a, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p, q, r, s, t, u
    case v, w, x, y, z
    case digit0, digit1, digit2, digit3, digit4, digit5, digit6, digit7
    case digit8, digit9

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
        }
    }
}
