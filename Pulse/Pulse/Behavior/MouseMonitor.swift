import AppKit

/// Global + local mouse-moved feed, throttled to ~30 Hz. Global monitors see the
/// cursor over other apps; the local one covers our own panels.
@MainActor
final class MouseMonitor {
    private let onMove: (NSPoint) -> Void
    private var global: Any?
    private var local: Any?
    private var last = Date.distantPast
    private let minInterval: TimeInterval = 1.0 / 30

    init(onMove: @escaping (NSPoint) -> Void) { self.onMove = onMove }

    func start() {
        guard global == nil else { return }
        global = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] _ in
            Task { @MainActor in self?.report() }
        }
        local = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
            Task { @MainActor in self?.report() }
            return event
        }
    }

    func stop() {
        if let global { NSEvent.removeMonitor(global) }
        if let local { NSEvent.removeMonitor(local) }
        global = nil; local = nil
    }

    private func report() {
        let now = Date()
        guard now.timeIntervalSince(last) >= minInterval else { return }
        last = now
        onMove(NSEvent.mouseLocation)
    }
}
