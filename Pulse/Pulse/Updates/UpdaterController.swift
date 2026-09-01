import Foundation
import Sparkle

/// Sparkle is only started when Info.plist carries an https feed URL (filled in by
/// the release tooling). Until then "Check now" is disabled and nothing is contacted.
enum UpdaterGate {
    static func feedURL(in info: [String: Any]) -> URL? {
        guard let raw = info["SUFeedURL"] as? String, let url = URL(string: raw), url.scheme == "https", url.host != nil else { return nil }
        return url
    }
}

@MainActor
final class UpdaterController {
    private let controller: SPUStandardUpdaterController?
    let isConfigured: Bool

    init(bundle: Bundle = .main, prefs: Preferences) {
        let configured = UpdaterGate.feedURL(in: bundle.infoDictionary ?? [:]) != nil
            && !((bundle.infoDictionary?["SUPublicEDKey"] as? String) ?? "").isEmpty
        isConfigured = configured
        controller = configured ? SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil) : nil
        controller?.updater.automaticallyChecksForUpdates = prefs.autoUpdate
    }

    var automaticallyChecks: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set { controller?.updater.automaticallyChecksForUpdates = newValue }
    }

    func checkForUpdates() { controller?.checkForUpdates(nil) }
}
