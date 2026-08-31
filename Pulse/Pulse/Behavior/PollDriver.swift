import AppKit
import Network
import PulseCore

/// Drives `UsageStore`: a 1-second timer calls `tick()`; waking from sleep or
/// regaining the network calls `refreshNow()`. The store decides what is due.
@MainActor
final class PollDriver {
    private let store: UsageStore
    private let interval: TimeInterval
    private let onTick: () -> Void
    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private var pathMonitor: NWPathMonitor?
    private var wasSatisfied: Bool?
    private var ticking = false

    private(set) var isRunning = false

    init(store: UsageStore, interval: TimeInterval = 1, onTick: @escaping () -> Void) {
        self.store = store
        self.interval = interval
        self.onTick = onTick
    }

    /// - Parameter observingSystemEvents: `false` installs neither the wake observer nor the
    ///   `NWPathMonitor`. Only tests pass it: a live monitor reports the machine's real network
    ///   from a background queue at a moment nobody controls, and one offline→online edge lands
    ///   an extra `refreshNow()` in the middle of a test that counts fetches exactly. The timer
    ///   and the first poll are unaffected, so `start()` still means "running".
    func start(observingSystemEvents: Bool = true) {
        guard !isRunning else { return }
        isRunning = true
        // Render on *every* fire, before starting the poll. `handleTick` only reports
        // once a whole `store.tick()` has finished, so one provider stuck on a slow request — or
        // behind a system prompt — would otherwise hold every ring at `.loading` for as long as it
        // hangs. The store publishes each provider's status as that provider lands, so this cheap
        // redraw always shows the freshest thing known; `handleTick` still renders again at the end.
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.onTick()
                await self?.handleTick()
            }
        }
        t.tolerance = interval * 0.2
        RunLoop.main.add(t, forMode: .common)
        timer = t

        if observingSystemEvents {
            wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in await self?.handleWake() }
            }

            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { [weak self] path in
                let satisfied = path.status == .satisfied
                Task { @MainActor [weak self] in await self?.handleNetworkPath(satisfied: satisfied) }
            }
            monitor.start(queue: DispatchQueue(label: "com.pulsedock.mac.network"))
            pathMonitor = monitor
        }
        Task { await handleTick() }
    }

    func stop() {
        timer?.invalidate(); timer = nil
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        wakeObserver = nil
        pathMonitor?.cancel(); pathMonitor = nil
        isRunning = false
    }

    /// One poll cycle; overlapping calls are dropped (the store also guards in-flight providers).
    func handleTick() async {
        guard !ticking else { return }
        ticking = true
        defer { ticking = false }
        await store.tick()
        onTick()
    }

    /// Both handlers are reached from observers registered in `start()`. A notification or
    /// path update already dispatched when `stop()` runs still lands afterwards, so each one
    /// checks that the driver is meant to be polling before touching the store.
    func handleWake() async {
        guard isRunning else { return }
        await store.refreshNow(nil)
        onTick()
    }

    /// Refresh on the offline→online edge only; the first report just records the state.
    func handleNetworkPath(satisfied: Bool) async {
        guard isRunning else { return }
        defer { wasSatisfied = satisfied }
        guard let previous = wasSatisfied, !previous, satisfied else { return }
        await store.refreshNow(nil)
        onTick()
    }
}
