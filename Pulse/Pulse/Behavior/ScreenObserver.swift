import AppKit

/// Fires when displays are added/removed or resolutions change so the dock re-clamps.
@MainActor
final class ScreenObserver {
    private let onChange: () -> Void
    private var token: NSObjectProtocol?

    init(onChange: @escaping () -> Void) { self.onChange = onChange }

    func start() {
        token = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.onChange() }
        }
    }

    func stop() {
        if let token { NotificationCenter.default.removeObserver(token) }
        token = nil
    }
}
