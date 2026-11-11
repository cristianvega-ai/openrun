import Settings
import Testing

@Suite struct SettingChangeTests {
    /// A value other than the default for each setting, in its text form.
    static let changedTexts: [SettingName: String] = [
        .theme: "Solarized Light", .fontName: "Menlo", .fontSize: "72", .optionAsAlt: "neither",
        .scrollbackLimit: "0", .newSessionCommands: #"[{"command":"htop","name":"Monitor"}]"#,
        .linkDestination: "browser-split", .showsNotifications: "off", .sessionLimit: "1", .asksBeforeUnsafePaste: "off",
        .claudeCodeModel: "claude-sonnet-5-5", .claudeCodePermissionMode: "acceptEdits",
        .claudeCodeProgram: "/opt/homebrew/bin/claude", .agentProcessLimit: "32",
    ]

    @Test func everySettingRoundTripsThroughText() throws {
        var values = SettingValues()
        for name in SettingName.allCases {
            let text = try #require(Self.changedTexts[name])
            #expect(text != values.text(of: name))
            try values.change(name, to: text, requestedBy: .application)
            #expect(values.text(of: name) == text)
        }
        #expect(values.theme == "Solarized Light")
        #expect(values.fontName == "Menlo")
        #expect(values.fontSize == 72)
        #expect(values.optionAsAlt == .neither)
        #expect(values.scrollbackLimit == 0)
        #expect(values.newSessionCommands == [NewSessionCommand(name: "Monitor", commandLine: "htop")])
        #expect(values.linkDestination == .browserSplit)
        #expect(!values.showsNotifications)
        #expect(values.sessionLimit == 1)
        #expect(!values.asksBeforeUnsafePaste)
        #expect(values.claudeCodeModel == "claude-sonnet-5-5" && values.claudeCodePermissionMode == "acceptEdits")
        #expect(values.claudeCodeProgram == "/opt/homebrew/bin/claude" && values.agentProcessLimit == 32)
        // The case of a choice does not count, and the value keeps its own spelling.
        try values.change(.claudeCodePermissionMode, to: " DONTASK ", requestedBy: .application)
        #expect(values.claudeCodePermissionMode == "dontAsk")
    }

    @Test func theDefaultsAreTheOnesOfTheDecisionLog() {
        let values = SettingValues()
        #expect(values.theme == "graphite")
        #expect(values.fontName == "SF Mono")
        #expect(values.fontSize == 13)
        #expect(values.optionAsAlt == .left)
        #expect(values.scrollbackLimit == 10_000)
        #expect(values.newSessionCommands == NewSessionCommand.defaults)
        #expect(values.linkDestination == .defaultBrowser)
        #expect(values.showsNotifications)
        #expect(values.sessionLimit == 100)
        #expect(values.asksBeforeUnsafePaste)
        #expect(values.claudeCodeModel == "opus" && values.claudeCodePermissionMode == "default")
        #expect(values.claudeCodeProgram == "claude" && values.agentProcessLimit == 8)
    }

    /// The rule of 2026-10-27, in its one place: only the app changes a
    /// protected setting, and any client reads it.
    @Test(arguments: SettingName.allCases.filter { $0.isProtected })
    func onlyTheAppChangesAProtectedSetting(name: SettingName) throws {
        var values = SettingValues()
        let before = values.text(of: name)
        let text = try #require(Self.changedTexts[name])
        #expect(throws: SettingError.protectedSetting(name)) {
            try values.change(name, to: text, requestedBy: .otherClient)
        }
        #expect(values.text(of: name) == before)
        try values.change(name, to: text, requestedBy: .application)
        #expect(values.text(of: name) == text)
    }

    @Test(arguments: SettingName.allCases.filter { !$0.isProtected })
    func anyClientChangesAnOtherSetting(name: SettingName) throws {
        var values = SettingValues()
        try values.change(name, to: values.text(of: name), requestedBy: .otherClient)
        #expect(values == SettingValues())
    }

    @Test func aBadValueChangesNothing() {
        var values = SettingValues()
        #expect(throws: SettingError.invalidValue(.fontSize)) {
            try values.change(.fontSize, to: "500", requestedBy: .application)
        }
        #expect(values == SettingValues())
    }
}
