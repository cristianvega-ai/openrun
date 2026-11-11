import Settings
import Testing

@Suite struct SettingChangeTests {
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
    }
}
