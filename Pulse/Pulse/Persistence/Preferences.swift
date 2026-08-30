import Foundation
import Observation
import PulseCore

/// Every persisted setting, backed by UserDefaults and nothing else (spec §8).
/// Reads validate; writes happen in `didSet` (or, for `providerOrder`, its setter)
/// so the store is always current.
@MainActor
@Observable
final class Preferences {
    static let defaultOrder: [ProviderID] = [.claude, .codex, .gemini]
    static let validThresholds: Set<Int> = [80, 90, 95]

    private let defaults: UserDefaults

    // `providerOrder` is backed by a plain stored property instead of a `didSet` on the
    // public var: under `@Observable`, a stored property's synthesized setter re-invokes
    // `didSet` on any self-reassignment (unlike a non-observed stored property, where it
    // doesn't), and `didSet` here unconditionally rewrites `providerOrder` to its normalized
    // form — so a naive `didSet` recurses forever. Tracking is preserved manually via
    // `access(keyPath:)` / `withMutation(keyPath:)`.
    @ObservationIgnored private var storedProviderOrder: [ProviderID]

    var providerOrder: [ProviderID] {
        get {
            access(keyPath: \.providerOrder)
            return storedProviderOrder
        }
        set {
            withMutation(keyPath: \.providerOrder) {
                storedProviderOrder = Self.normalizedOrder(newValue)
            }
            persistProviderOrder()
        }
    }
    var enabledProviders: Set<ProviderID> { didSet { defaults.set(enabledProviders.map(\.rawValue).sorted(), forKey: "enabledProviders") } }
    var edge: ScreenEdge { didSet { defaults.set(edge.rawValue, forKey: "edge") } }
    var dockStyle: DockStyle { didSet { defaults.set(dockStyle.rawValue, forKey: "dockStyle") } }
    var dockYFraction: Double { didSet { defaults.set(dockYFraction, forKey: "dockYFraction") } }
    var dockScreenName: String? { didSet { defaults.set(dockScreenName, forKey: "dockScreenName") } }
    var alertThreshold: Int { didSet { defaults.set(alertThreshold, forKey: "alertThreshold") } }
    var autoHide: Bool { didSet { defaults.set(autoHide, forKey: "autoHide") } }
    var launchAtLogin: Bool { didSet { defaults.set(launchAtLogin, forKey: "launchAtLogin") } }
    var autoUpdate: Bool { didSet { defaults.set(autoUpdate, forKey: "autoUpdate") } }
    var firedAlerts: [String: Double] { didSet { defaults.set(firedAlerts, forKey: "firedAlerts") } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let rawStrings = defaults.array(forKey: "providerOrder") as? [String]
        let decoded = rawStrings?.compactMap(ProviderID.init(rawValue:))
        if let rawStrings, let decoded, rawStrings.count == decoded.count {
            storedProviderOrder = Self.normalizedOrder(decoded)
        } else {
            storedProviderOrder = Self.defaultOrder
        }
        if let raw = defaults.array(forKey: "enabledProviders") as? [String] {
            enabledProviders = Set(raw.compactMap(ProviderID.init(rawValue:)))
        } else {
            enabledProviders = Set(Self.defaultOrder)
        }
        edge = defaults.string(forKey: "edge").flatMap(ScreenEdge.init(rawValue:)) ?? .right
        dockStyle = defaults.string(forKey: "dockStyle").flatMap(DockStyle.init(rawValue:)) ?? .notch
        let y = defaults.object(forKey: "dockYFraction") as? Double
        dockYFraction = (y.map { (0...1).contains($0) } ?? false) ? y! : 0.5
        dockScreenName = defaults.string(forKey: "dockScreenName")
        let threshold = defaults.object(forKey: "alertThreshold") as? Int
        alertThreshold = threshold.flatMap { Self.validThresholds.contains($0) ? $0 : nil } ?? 90
        autoHide = defaults.bool(forKey: "autoHide")
        launchAtLogin = defaults.bool(forKey: "launchAtLogin")
        autoUpdate = defaults.object(forKey: "autoUpdate") as? Bool ?? true
        firedAlerts = defaults.dictionary(forKey: "firedAlerts") as? [String: Double] ?? [:]
    }

    private func persistProviderOrder() {
        defaults.set(storedProviderOrder.map(\.rawValue), forKey: "providerOrder")
    }

    /// Every provider exactly once, preserving first-seen order, with any
    /// missing providers appended in their default-order position.
    private static func normalizedOrder(_ order: [ProviderID]) -> [ProviderID] {
        var seen = Set<ProviderID>()
        var result: [ProviderID] = []
        for id in order where !seen.contains(id) {
            seen.insert(id)
            result.append(id)
        }
        for id in defaultOrder where !seen.contains(id) {
            result.append(id)
        }
        return result
    }
}
