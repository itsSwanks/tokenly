import Testing
import PulseCore
@testable import Pulse

@MainActor
@Suite struct PreferencesTests {
    @Test func defaultsMatchTheSpec() {
        let prefs = Preferences(defaults: makeTestDefaults())
        #expect(prefs.providerOrder == [.claude, .codex, .gemini])
        #expect(prefs.enabledProviders == [.claude, .codex, .gemini])
        #expect(prefs.edge == .right)
        #expect(prefs.dockStyle == .notch)
        #expect(prefs.dockYFraction == 0.5)
        #expect(prefs.dockScreenName == nil)
        #expect(prefs.alertThreshold == 90)
        #expect(prefs.autoHide == false)
        #expect(prefs.launchAtLogin == false)
        #expect(prefs.autoUpdate == true)
        #expect(prefs.firedAlerts.isEmpty)
    }

    @Test func valuesPersistAcrossInstances() {
        let defaults = makeTestDefaults()
        let a = Preferences(defaults: defaults)
        a.providerOrder = [.gemini, .claude, .codex]
        a.enabledProviders = [.claude]
        a.edge = .left
        a.dockStyle = .glass
        a.dockYFraction = 0.25
        a.dockScreenName = "Built-in Retina Display"
        a.alertThreshold = 95
        a.autoHide = true
        a.launchAtLogin = true
        a.autoUpdate = false
        a.firedAlerts = ["claude.Current session": 91]

        let b = Preferences(defaults: defaults)
        #expect(b.providerOrder == [.gemini, .claude, .codex])
        #expect(b.enabledProviders == [.claude])
        #expect(b.edge == .left)
        #expect(b.dockStyle == .glass)
        #expect(b.dockYFraction == 0.25)
        #expect(b.dockScreenName == "Built-in Retina Display")
        #expect(b.alertThreshold == 95)
        #expect(b.autoHide == true)
        #expect(b.launchAtLogin == true)
        #expect(b.autoUpdate == false)
        #expect(b.firedAlerts == ["claude.Current session": 91])
    }

    @Test func corruptOrUnknownValuesFallBackToDefaults() {
        let defaults = makeTestDefaults()
        defaults.set(["claude", "bogus"], forKey: "providerOrder")
        defaults.set("diagonal", forKey: "edge")
        defaults.set("frosted", forKey: "dockStyle")
        defaults.set(42, forKey: "alertThreshold")
        defaults.set(7.5, forKey: "dockYFraction")
        let prefs = Preferences(defaults: defaults)
        #expect(prefs.providerOrder == [.claude, .codex, .gemini])   // unknown id → full default order
        #expect(prefs.edge == .right)
        #expect(prefs.dockStyle == .notch)                            // unknown style → Notch
        #expect(prefs.alertThreshold == 90)                           // only 80/90/95 are valid
        #expect(prefs.dockYFraction == 0.5)                           // out of 0…1
    }

    @Test func orderAlwaysContainsEveryProviderExactlyOnce() {
        let prefs = Preferences(defaults: makeTestDefaults())
        prefs.providerOrder = [.codex, .codex]
        #expect(prefs.providerOrder == [.codex, .claude, .gemini])
    }
}
