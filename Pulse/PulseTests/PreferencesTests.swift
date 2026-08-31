import Testing
import PulseCore
@testable import Pulse

@MainActor
@Suite struct PreferencesTests {
    @Test func defaultsMatchTheSpec() {
        let prefs = Preferences(defaults: makeTestDefaults(), legacy: nil)
        #expect(prefs.providerOrder == [.claude, .codex, .gemini])
        #expect(prefs.enabledProviders == [.claude, .codex, .gemini])
        #expect(prefs.edge == .right)
        #expect(prefs.dockStyle == .notch)
        #expect(prefs.dockYFraction == 0.5)
        #expect(prefs.dockScreenName == nil)
        #expect(prefs.alertThreshold == 90)
        #expect(prefs.autoHide == true)      // on by default; a stored false still wins (tested below)
        #expect(prefs.launchAtLogin == false)
        #expect(prefs.autoUpdate == true)
        #expect(prefs.firedAlerts.isEmpty)
        #expect(prefs.appearance == .auto)
    }

    @Test func appearancePersistsAndValidates() {
        let defaults = makeTestDefaults()
        let prefs = Preferences(defaults: defaults, legacy: nil)
        prefs.appearance = .dark
        #expect(defaults.string(forKey: "appearance") == "dark")
        #expect(Preferences(defaults: defaults, legacy: nil).appearance == .dark)
        defaults.set("sepia", forKey: "appearance")
        #expect(Preferences(defaults: defaults, legacy: nil).appearance == .auto)
    }

    @Test func valuesPersistAcrossInstances() {
        let defaults = makeTestDefaults()
        let a = Preferences(defaults: defaults, legacy: nil)
        a.providerOrder = [.gemini, .claude, .codex]
        a.enabledProviders = [.claude]
        a.edge = .left
        a.dockStyle = .pill
        a.dockYFraction = 0.25
        a.dockScreenName = "Built-in Retina Display"
        a.alertThreshold = 95
        a.autoHide = true
        a.launchAtLogin = true
        a.autoUpdate = false
        a.firedAlerts = ["claude.Current session": 91]

        let b = Preferences(defaults: defaults, legacy: nil)
        #expect(b.providerOrder == [.gemini, .claude, .codex])
        #expect(b.enabledProviders == [.claude])
        #expect(b.edge == .left)
        #expect(b.dockStyle == .pill)
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
        let prefs = Preferences(defaults: defaults, legacy: nil)
        #expect(prefs.providerOrder == [.claude, .codex, .gemini])   // unknown id → full default order
        #expect(prefs.edge == .right)
        #expect(prefs.dockStyle == .notch)                            // unknown style → Notch
        #expect(prefs.alertThreshold == 90)                           // only 80/90/95 are valid
        #expect(prefs.dockYFraction == 0.5)                           // out of 0…1
    }

    @Test func orderAlwaysContainsEveryProviderExactlyOnce() {
        let prefs = Preferences(defaults: makeTestDefaults(), legacy: nil)
        prefs.providerOrder = [.codex, .codex]
        #expect(prefs.providerOrder == [.codex, .claude, .gemini])
    }

    @Test func dockSizeDefaultsToSmallAndPersists() {
        let defaults = makeTestDefaults()
        let prefs = Preferences(defaults: defaults, legacy: nil)
        #expect(prefs.dockSize == .small)
        prefs.dockSize = .large
        #expect(defaults.string(forKey: "dockSize") == "large")
        #expect(Preferences(defaults: defaults, legacy: nil).dockSize == .large)
    }

    @Test func explicitlyDisabledAutoHideSurvivesTheOnByDefault() {
        let defaults = makeTestDefaults()
        defaults.set(false, forKey: "autoHide")
        #expect(Preferences(defaults: defaults, legacy: nil).autoHide == false)
    }

    @Test func invalidDockSizeFallsBackToSmall() {
        let defaults = makeTestDefaults()
        defaults.set("huge", forKey: "dockSize")
        #expect(Preferences(defaults: defaults, legacy: nil).dockSize == .small)
    }

    @Test func legacyGlassDockStyleReadsAsPill() {
        let defaults = makeTestDefaults()
        defaults.set("glass", forKey: "dockStyle")
        let prefs = Preferences(defaults: defaults, legacy: nil)
        #expect(prefs.dockStyle == .pill)
        prefs.dockStyle = .pill
        #expect(defaults.string(forKey: "dockStyle") == "pill")
    }

    // MARK: - com.pulsedock.mac → com.tokenly.mac (the rebrand moved the defaults domain)

    @Test func settingsMigrateFromTheOldPulseDockDomain() {
        let legacy = makeTestDefaults()
        legacy.set(95, forKey: "alertThreshold")
        legacy.set(false, forKey: "autoHide")
        legacy.set("large", forKey: "dockSize")
        legacy.set(["gemini", "claude", "codex"], forKey: "providerOrder")

        let defaults = makeTestDefaults()
        let prefs = Preferences(defaults: defaults, legacy: legacy)
        #expect(prefs.alertThreshold == 95)
        #expect(prefs.autoHide == false)
        #expect(prefs.dockSize == .large)
        #expect(prefs.providerOrder == [.gemini, .claude, .codex])
        #expect(defaults.bool(forKey: "migratedFromPulseDock"))
    }

    @Test func aValueAlreadyInTheNewDomainWinsOverTheLegacyOne() {
        let legacy = makeTestDefaults()
        legacy.set(95, forKey: "alertThreshold")
        legacy.set("left", forKey: "edge")

        let defaults = makeTestDefaults()
        defaults.set(80, forKey: "alertThreshold")
        let prefs = Preferences(defaults: defaults, legacy: legacy)
        #expect(prefs.alertThreshold == 80)     // the new domain is the truth
        #expect(prefs.edge == .left)            // …but an absent key still comes across
    }

    @Test func theFlagStopsASecondMigration() {
        let legacy = makeTestDefaults()
        legacy.set(95, forKey: "alertThreshold")

        let defaults = makeTestDefaults()
        #expect(Preferences(defaults: defaults, legacy: legacy).alertThreshold == 95)

        // A setting the user never had before appearing in the old domain afterwards must not be
        // pulled in: the copy happens exactly once, or clearing a setting would never stick.
        legacy.set("left", forKey: "edge")
        legacy.set("large", forKey: "dockSize")
        let second = Preferences(defaults: defaults, legacy: legacy)
        #expect(second.edge == .right)
        #expect(second.dockSize == .small)
        #expect(defaults.object(forKey: "edge") == nil)
        #expect(defaults.object(forKey: "dockSize") == nil)
    }

    @Test func withNoLegacyDomainTheDefaultsAreTheNormalOnesAndTheFlagIsStillSet() {
        let defaults = makeTestDefaults()
        let prefs = Preferences(defaults: defaults, legacy: nil)
        #expect(prefs.alertThreshold == 90)
        #expect(prefs.autoHide == true)
        #expect(prefs.dockSize == .small)
        #expect(prefs.providerOrder == [.claude, .codex, .gemini])
        #expect(defaults.bool(forKey: "migratedFromPulseDock"))
    }
}
