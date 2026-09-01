import AppKit
import PulseCore

/// Composition root. Owns every long-lived object; nothing else holds global state.
@MainActor
final class AppController {
    let prefs: Preferences
    let store: UsageStore
    let dock: DockWindowController
    let callout: CalloutWindowController
    let alerts: AlertCenter
    let banner: AlertBannerWindowController
    let driver: PollDriver
    let updater: UpdaterController

    private var hover = HoverCoordinator()
    private var hoverTimers: [Int: DispatchWorkItem] = [:]
    private var clickAwayMonitor: Any?

    private var edge = EdgeTracker()
    private var mouse: MouseMonitor?
    private var graceCheckTimer: DispatchWorkItem?
    // Optional rather than a `let`: its own initializer's closure captures `self`, which the
    // compiler rejects mid-init for a property that isn't yet marked assigned — `self` can't be
    // "complete" while this very statement is still computing one of its stored properties. An
    // `Optional` already counts as initialized via its implicit `nil`, so assigning the real value
    // once the rest of `self` is set (last line of `init`) is an ordinary post-init mutation.
    private var screens: ScreenObserver?
    private var dragging = false         // first drag delta force-hides the callout
    private var settingsOpen = false     // holds the dock open while the panel is up
    private var settings: SettingsWindowController?

    init() {
        prefs = Preferences()
        store = UsageStore(providers: [ClaudeProvider(), CodexProvider(), GeminiProvider()], enabled: prefs.enabledProviders)
        dock = DockWindowController(store: store, prefs: prefs)
        callout = CalloutWindowController(store: store, prefs: prefs)
        // Alerts fan out to both channels: the system poster (a no-op until macOS ever grants
        // an ad-hoc app authorization — it answers UNErrorDomain Code=1 today) and Pulse's own
        // glass banner, which needs no permission and works for every install.
        let banner = AlertBannerWindowController()
        self.banner = banner
        alerts = AlertCenter(prefs: prefs, poster: CompositePoster(
            system: UserNotificationPoster(),
            banner: { [weak banner] title, body in
                Task { @MainActor in banner?.show(title: title, body: body) }
            }))
        updater = UpdaterController(prefs: prefs)
        // The login item is owned by the system, not by us: trust `SMAppService` over whatever
        // the last run persisted, so a login item removed in System Settings shows as off here.
        prefs.launchAtLogin = LoginItem.isEnabled
        // Every capture here is weak, including `store`/`prefs`, so a torn-down
        // `AppController` can never be kept alive by its own poll driver's tick closure.
        driver = PollDriver(store: store, onTick: { [weak dock, weak callout, weak alerts, weak store, weak prefs] in
            dock?.render()
            callout?.render()
            if let alerts, let store, let prefs {
                alerts.process(statuses: store.statuses, order: prefs.enabledOrdered)
            }
        })

        dock.interaction.onHoverCell = { [weak self] i in self?.dock.model.hoveredIndex = i; self?.send(.hoverCell(i)) }
        dock.interaction.onHoverGear = { [weak self] on in self?.dock.model.gearHovered = on }
        dock.interaction.onExit = { [weak self] in
            self?.dock.model.hoveredIndex = nil
            self?.dock.model.gearHovered = false
            self?.send(.hoverCell(nil))
        }
        dock.interaction.onClickCell = { [weak self] i in self?.send(.clickCell(i)) }
        // The first delta of a drag force-hides the callout before moving the dock,
        // so a pinned or hovered callout never has to track a window that just relocated under it.
        dock.interaction.onDrag = { [weak self] dy in
            guard let self else { return }
            if !self.dragging {
                self.dragging = true
                self.send(.forceHide)
            }
            self.dock.drag(by: dy)
        }
        dock.interaction.onDragEnded = { [weak self] in
            self?.dragging = false
            self?.dock.dragEnded()
        }
        dock.interaction.onClickGear = { [weak self] in self?.openSettings() }
        dock.interaction.onRightClick = { [weak self] _ in self?.openSettings() }
        callout.onEnter = { [weak self] in self?.send(.enterCallout) }
        callout.onExit = { [weak self] in self?.send(.leaveCallout) }
        callout.onRetry = { [weak self] id in
            Task { @MainActor [weak self] in
                await self?.store.refreshNow(id)
                self?.dock.render()
                self?.callout.render()
            }
        }
        // `show()` rather than `reposition()`: it is idempotent (render, reposition, order front)
        // and it re-places the handle, which `reposition` knows nothing about, on whatever
        // `visibleFrame` the new arrangement gives the dock's screen. It also covers the one case
        // `reposition` cannot — a launch with no displays attached, where `show()` bailed out and
        // the panel was never ordered in; plugging a monitor in now brings the dock up.
        screens = ScreenObserver(onChange: { [weak self] in
            self?.dock.show()
            self?.send(.forceHide)
        })
    }

    func start() {
        applyAppearance()
        dock.show()
        // The banner belongs on the dock's screen, on the dock's side.
        banner.placement = { [weak self] in (self?.dock.screen, self?.prefs.edge ?? .right) }
        alerts.warmUp()
        driver.start()
        screens?.start()
        applyAutoHide()
        // Global monitors only report clicks in *other* apps — exactly "away" from the dock.
        clickAwayMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor [weak self] in self?.send(.clickAway) }
        }
    }

    func stop() {
        settings?.close()
        callout.hide()
        driver.stop()
        screens?.stop()
        mouse?.stop()
        mouse = nil
        cancelGraceCheck()
        if let clickAwayMonitor { NSEvent.removeMonitor(clickAwayMonitor) }
        clickAwayMonitor = nil
        for item in hoverTimers.values { item.cancel() }
        hoverTimers.removeAll()
    }

    /// One assignment themes everything (spec §19.6): every surface draws with adaptive glass and
    /// dynamic colours, so pinning (or un-pinning) the app-wide appearance is the whole feature.
    func applyAppearance() {
        if let name = prefs.appearance.pinnedAppearanceName {
            NSApp.appearance = NSAppearance(named: name)
        } else {
            NSApp.appearance = nil
        }
    }

    /// Auto-hide on: retract off-screen, rest on the glass handle, and follow the mouse.
    /// Off: expanded, handle gone, no monitor.
    func applyAutoHide() {
        mouse?.stop(); mouse = nil
        cancelGraceCheck()
        if prefs.autoHide {
            edge.force(.collapsed)
            dock.setCollapsed(true, animated: false)
            dock.setHandleEnabled(true)
            let m = MouseMonitor { [weak self] p in self?.mouseMoved(to: p) }
            m.start()
            mouse = m
        } else {
            edge.force(.expanded)
            dock.setHandleEnabled(false)
            dock.setCollapsed(false, animated: false)
        }
    }

    private func mouseMoved(to p: NSPoint) {
        // Points that aren't on the dock's screen produce no distance at all, so a cursor parked
        // on another display neither expands nor collapses this one.
        guard let screen = dock.screen,
              let distance = DockPositioner.distanceToEdge(point: p, edge: prefs.edge,
                                                           visible: screen.visibleFrame, screenFrame: screen.frame)
        else { return }
        let holdOpen = hover.pinnedIndex != nil || settingsOpen
        let wasCounting = graceCheckTimer != nil
        switch edge.update(distance: distance, holdOpen: holdOpen, now: Date()) {
        case .expand:
            // The 9 pt handle sits wholly inside the 44 pt `edgeProximity` band, so the cursor
            // reaching it expands the dock from here; the handle window itself never has to
            // receive a mouse event.
            cancelGraceCheck()
            dock.setCollapsed(false, animated: true)
        case .collapse:
            cancelGraceCheck()
            send(.forceHide); dock.setCollapsed(true, animated: true)
        case nil:
            if edge.state == .expanded, !holdOpen, distance > Metrics.edgeFarAway {
                guard !wasCounting else { break }
                // The tracker's grace clock only advances on events; re-evaluate once it has elapsed
                // so a perfectly still cursor still collapses the dock.
                let work = DispatchWorkItem { [weak self] in
                    Task { @MainActor [weak self] in self?.mouseMoved(to: NSEvent.mouseLocation) }
                }
                graceCheckTimer = work
                DispatchQueue.main.asyncAfter(deadline: .now() + Motion.collapseGrace + 0.02, execute: work)
            } else {
                cancelGraceCheck()
            }
        }
    }

    private func cancelGraceCheck() {
        graceCheckTimer?.cancel()
        graceCheckTimer = nil
    }

    /// Opens (or, on a second gear click, closes) the settings panel beside the dock.
    /// Every action closure captures `self` weakly and reaches `prefs`/`dock`/
    /// `settings`/`updater` through it, so the panel can never keep a torn-down controller alive.
    func openSettings() {
        if settings?.isOpen == true { settings?.close(); return }
        guard let screen = dock.screen else { return }
        send(.forceHide)
        let actions = SettingsActions(
            reorder: { [weak self] order in self?.prefs.providerOrder = order; self?.dock.render() },
            setEnabled: { [weak self] id, on in
                guard let self else { return }
                if on { prefs.enabledProviders.insert(id) } else { prefs.enabledProviders.remove(id) }
                store.setEnabled(id, on)
                dock.render()
            },
            setThreshold: { [weak self] in self?.prefs.alertThreshold = $0 },
            setAppearance: { [weak self] mode in
                self?.prefs.appearance = mode
                self?.applyAppearance()
            },
            setEdge: { [weak self] edge in
                guard let self else { return }
                prefs.edge = edge
                dock.render(); dock.reposition(animated: true)
                settings?.close()
            },
            setDockStyle: { [weak self] style in
                guard let self else { return }
                prefs.dockStyle = style
                dock.render()
            },
            setDockSize: { [weak self] size in
                guard let self else { return }
                prefs.dockSize = size
                dock.render()
            },
            setAutoHide: { [weak self] on in self?.prefs.autoHide = on; self?.applyAutoHide() },
            setLaunchAtLogin: { [weak self] on in
                guard let self else { return }
                try? LoginItem.set(on)
                // `.needsApproval` counts as on: the registration went through, macOS is only
                // waiting to be told it may run Pulse at login, and the hint says so.
                let outcome = LoginItem.current
                prefs.launchAtLogin = outcome != .off
                settings?.setLoginItemNeedsApproval(outcome == .needsApproval)
            },
            setAutoUpdate: { [weak self] on in self?.prefs.autoUpdate = on; self?.updater.automaticallyChecks = on },
            checkForUpdates: { [weak self] in self?.updater.checkForUpdates() },
            quit: { NSApp.terminate(nil) },
            close: { [weak self] in self?.settings?.close() }
        )
        let controller = SettingsWindowController(prefs: prefs, store: store, actions: actions, updatesAvailable: updater.isConfigured)
        controller.onClose = { [weak self] in
            self?.settingsOpen = false
            if self?.prefs.autoHide == true { self?.mouseMoved(to: NSEvent.mouseLocation) }
        }
        settings = controller
        settingsOpen = true
        controller.open(besideDock: dock.panel.frame, edge: prefs.edge, screen: screen)
    }

    /// Screen y of a ring's center, from the dock window's frame and its layout.
    private func ringCenterScreenY(index: Int) -> CGFloat {
        let layout = dock.model.layout
        let centerTopLeft = layout.cellCenters[index].y + layout.contentOrigin.y
        return dock.panel.frame.maxY - centerTopLeft
    }

    private func apply(_ effects: [HoverCoordinator.Effect]) {
        for effect in effects {
            switch effect {
            case .show(let i):
                guard let screen = dock.screen, i < dock.model.cells.count, i < dock.model.layout.cellCenters.count else { continue }
                callout.show(provider: dock.model.cells[i].id, ringCenterY: ringCenterScreenY(index: i), dockFrame: dock.panel.frame, screen: screen)
            case .move(let i):
                guard let screen = dock.screen, i < dock.model.cells.count, i < dock.model.layout.cellCenters.count else { continue }
                // An earlier `.show` may have been dropped by this same bounds guard, leaving the
                // coordinator visible but the panel ordered out. Re-show rather than move a hidden
                // window, so the two can never drift apart.
                if callout.isVisible {
                    callout.move(provider: dock.model.cells[i].id, ringCenterY: ringCenterScreenY(index: i), dockFrame: dock.panel.frame, screen: screen)
                } else {
                    callout.show(provider: dock.model.cells[i].id, ringCenterY: ringCenterScreenY(index: i), dockFrame: dock.panel.frame, screen: screen)
                }
            case .hide:
                callout.hide()
            case .scheduleTimeout(let after, let id):
                let item = DispatchWorkItem { [weak self] in
                    Task { @MainActor [weak self] in
                        guard let self, self.hoverTimers.removeValue(forKey: id) != nil else { return }
                        self.send(.timeout(id: id))
                    }
                }
                hoverTimers[id] = item
                DispatchQueue.main.asyncAfter(deadline: .now() + after, execute: item)
            case .cancelTimeout(let id):
                hoverTimers.removeValue(forKey: id)?.cancel()
            }
        }
    }

    private func send(_ event: HoverCoordinator.Event) { apply(hover.handle(event)) }
}
