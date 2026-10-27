/// The values of the table "Graphite theme" in `documentation/product.md`.
enum GraphitePalette {
    static let light = TerminalTheme(
        background: 0xfafbfc, foreground: 0x1e2022, cursor: 0x1e2022, selection: 0xdfe6ee,
        firstSixteenColors: [
            0x1e2022, 0xb8364b, 0x327339, 0x81600e, 0x2b67b1, 0x8748bc, 0x137073, 0xd6dade,
            0x6e7277, 0xce3b53, 0x3d8044, 0x8f6c15, 0x3073c5, 0x9553cb, 0x197e80, 0xf3f4f6,
        ])

    static let dark = TerminalTheme(
        background: 0x1e2022, foreground: 0xe6eef4, cursor: 0xe6eef4, selection: 0x3a4147,
        firstSixteenColors: [
            0x2e3134, 0xe87382, 0x9fcb8b, 0xe2c27f, 0x79aee6, 0xc59de6, 0x67c9cb, 0xc8cfd5,
            0x8a8f94, 0xf08f9b, 0xb4d8a3, 0xebd29b, 0x97c1ee, 0xd5b5ee, 0x88d8d9, 0xe6eef4,
        ])
}
