import Foundation
import Testing
@testable import OpenRunApplication

@MainActor @Suite struct KeyRepeatDefaultsTests {
    @Test func theDefaultAllowsRepeatAndAnExplicitPreferenceStillWins() {
        let defaults = UserDefaults.standard
        let key = "ApplePressAndHoldEnabled"
        let savedArguments = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        let savedRegistration = defaults.volatileDomain(forName: UserDefaults.registrationDomain)
        defer {
            defaults.setVolatileDomain(savedArguments, forName: UserDefaults.argumentDomain)
            defaults.setVolatileDomain(savedRegistration, forName: UserDefaults.registrationDomain)
        }

        var arguments = savedArguments
        arguments.removeValue(forKey: key)
        defaults.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
        OpenRunApplication.registerKeyboardDefaults()
        #expect(defaults.volatileDomain(forName: UserDefaults.registrationDomain)[key] as? Bool == false)

        arguments[key] = true
        defaults.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
        OpenRunApplication.registerKeyboardDefaults()
        #expect(defaults.bool(forKey: key))
    }
}
