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

    /// Draws the arms with whole pixels. Every arm reaches its edge of the cell at
    /// the same place for a size of cell, so neighbors join. In the middle, each
    /// arm stops where it meets the others, so a corner or a joint has no notch,
    /// and the gap of a double line stays open where another double line joins it.
    func draw(on canvas: inout CellCanvas) {
        let light = canvas.lightThickness, heavy = 2 * canvas.lightThickness
        let (width, height) = (canvas.width, canvas.height)
        let lightTop = (height - light) / 2, lightBottom = (height - light) / 2 + light
        let heavyTop = (height - heavy) / 2, heavyBottom = (height - heavy) / 2 + heavy
        let doubleTop = lightTop - light, doubleBottom = lightBottom + light
        let lightLeft = (width - light) / 2, lightRight = (width - light) / 2 + light
        let heavyLeft = (width - heavy) / 2, heavyRight = (width - heavy) / 2 + heavy
        let doubleLeft = lightLeft - light, doubleRight = lightRight + light
        let horizontal = [left, right], vertical = [up, down]
        // Where an arm stops in the middle depends on the arms across it.
        func stop(across: [Weight], along: (Weight, Weight), heavy: Int, double: Int, light: Int, inner: Int) -> Int {
            if across.contains(.heavy) { return heavy }
            if across[0] != across[1] || along.0 == along.1 { return across.contains(.double) ? double : light }
            return across.allSatisfy { $0 == .none } ? light : inner
        }
        let upBottom = stop(across: horizontal, along: (down, up), heavy: heavyBottom, double: doubleBottom, light: lightBottom, inner: lightTop)
        let downTop = stop(across: horizontal, along: (up, down), heavy: heavyTop, double: doubleTop, light: lightTop, inner: lightBottom)
        let leftRight = stop(across: vertical, along: (left, right), heavy: heavyRight, double: doubleRight, light: lightRight, inner: lightLeft)
        let rightLeft = stop(across: vertical, along: (right, left), heavy: heavyLeft, double: doubleLeft, light: lightLeft, inner: lightRight)
        switch up {
        case .none: break
        case .light: canvas.fill(left: lightLeft, top: 0, right: lightRight, bottom: upBottom)
        case .heavy: canvas.fill(left: heavyLeft, top: 0, right: heavyRight, bottom: upBottom)
        case .double:
            canvas.fill(left: doubleLeft, top: 0, right: lightLeft, bottom: left == .double ? lightTop : upBottom)
            canvas.fill(left: lightRight, top: 0, right: doubleRight, bottom: right == .double ? lightTop : upBottom)
        }
        switch right {
        case .none: break
        case .light: canvas.fill(left: rightLeft, top: lightTop, right: width, bottom: lightBottom)
        case .heavy: canvas.fill(left: rightLeft, top: heavyTop, right: width, bottom: heavyBottom)
        case .double:
            canvas.fill(left: up == .double ? lightRight : rightLeft, top: doubleTop, right: width, bottom: lightTop)
            canvas.fill(left: down == .double ? lightRight : rightLeft, top: lightBottom, right: width, bottom: doubleBottom)
        }
        switch down {
        case .none: break
        case .light: canvas.fill(left: lightLeft, top: downTop, right: lightRight, bottom: height)
        case .heavy: canvas.fill(left: heavyLeft, top: downTop, right: heavyRight, bottom: height)
        case .double:
            canvas.fill(left: doubleLeft, top: left == .double ? lightBottom : downTop, right: lightLeft, bottom: height)
            canvas.fill(left: lightRight, top: right == .double ? lightBottom : downTop, right: doubleRight, bottom: height)
        }
        switch left {
        case .none: break
        case .light: canvas.fill(left: 0, top: lightTop, right: leftRight, bottom: lightBottom)
        case .heavy: canvas.fill(left: 0, top: heavyTop, right: leftRight, bottom: heavyBottom)
        case .double:
            canvas.fill(left: 0, top: doubleTop, right: up == .double ? lightLeft : leftRight, bottom: lightTop)
            canvas.fill(left: 0, top: lightBottom, right: down == .double ? lightLeft : leftRight, bottom: doubleBottom)
        }
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
