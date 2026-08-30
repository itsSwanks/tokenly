import ServiceManagement

enum LoginItem {
    /// What the system says about Pulse's login item, reduced to the three answers the
    /// settings toggle has to render.
    ///
    /// `.needsApproval` is the case that used to be lost: `register()` succeeds, but macOS
    /// parks the item in *Login Items & Extensions* until the user allows it, so
    /// `SMAppService.mainApp.status` reads `.requiresApproval` rather than `.enabled`.
    /// Treating that as "off" made the toggle snap back the instant it was flipped, with
    /// nothing on screen to say why.
    enum Outcome: Equatable { case on, off, needsApproval }

    static func outcome(for status: SMAppService.Status) -> Outcome {
        switch status {
        case .enabled: .on
        case .requiresApproval: .needsApproval
        default: .off       // .notRegistered, .notFound, and anything a later macOS adds
        }
    }

    static var current: Outcome { outcome(for: SMAppService.mainApp.status) }

    /// Registered as far as the toggle is concerned — approved, or waiting to be.
    static var isEnabled: Bool { current != .off }

    static func set(_ enabled: Bool) throws {
        if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
    }
}
