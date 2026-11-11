/// The lines of a box drawing character that go from the middle of the cell to
/// the middle of its edges. Most characters of U+2500 to U+257F are such a set
/// of four arms, each one absent, light, heavy or double.
struct BoxLineArms: Equatable {
    enum Weight: Character {
        case none = ".", light = "l", heavy = "h", double = "d"
    }

    let up, right, down, left: Weight

    init(up: Weight, right: Weight, down: Weight, left: Weight) {
        (self.up, self.right, self.down, self.left) = (up, right, down, left)
    }

    /// The arms of a character, or `nil` for one that is not only straight arms,
    /// such as a dashed line, a rounded corner or a diagonal.
    init?(_ scalar: Unicode.Scalar) {
        guard (0x2500...0x257F).contains(scalar.value) else { return nil }
        let weights = Self.table[Int(scalar.value - 0x2500)].compactMap(Weight.init(rawValue:))
        guard weights.count == 4 else { return nil }
        self.init(up: weights[0], right: weights[1], down: weights[2], left: weights[3])
    }

    /// The arms of U+2500 to U+257F, 16 characters in each line, in the order up,
    /// right, down and left. A dash marks a character that is drawn another way.
    private static let table: [Substring] = """
        .l.l .h.h l.l. h.h. ---- ---- ---- ---- ---- ---- ---- ---- .ll. .hl. .lh. .hh.
        ..ll ..lh ..hl ..hh ll.. lh.. hl.. hh.. l..l l..h h..l h..h lll. lhl. hll. llh.
        hlh. hhl. lhh. hhh. l.ll l.lh h.ll l.hl h.hl h.lh l.hh h.hh .lll .llh .hll .hlh
        .lhl .lhh .hhl .hhh ll.l ll.h lh.l lh.h hl.l hl.h hh.l hh.h llll lllh lhll lhlh
        hlll llhl hlhl hllh hhll llhh lhhl hhlh lhhh hlhh hhhl hhhh ---- ---- ---- ----
        .d.d d.d. .dl. .ld. .dd. ..ld ..dl ..dd ld.. dl.. dd.. l..d d..l d..d ldl. dld.
        ddd. l.ld d.dl d.dd .dld .ldl .ddd ld.d dl.l dd.d ldld dldl dddd ---- ---- ----
        ---- ---- ---- ---- ...l l... .l.. ..l. ...h h... .h.. ..h. .h.l l.h. .l.h h.l.
        """.split(whereSeparator: \.isWhitespace)
}
