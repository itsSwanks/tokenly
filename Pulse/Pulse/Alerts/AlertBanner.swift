import AppKit
import SwiftUI
import PulseCore

/// One alert the banner shows.
struct BannerItem: Equatable, Identifiable {
    let id: UUID
    let title: String
    let body: String

    init(id: UUID = UUID(), title: String, body: String) {
        self.id = id
        self.title = title
        self.body = body
    }
}

/// Presentation state plus a FIFO of alerts that arrived while one was showing.
/// Pure data so the queue behaviour is unit-testable; the window controller drives timing.
@MainActor
@Observable
final class AlertBannerModel {
    var current: BannerItem?
    var isPresented = false
    private(set) var queue: [BannerItem] = []

    var hasQueued: Bool { !queue.isEmpty }

    func enqueue(_ item: BannerItem) { queue.append(item) }

    /// Pops the next alert into `current`; false when the queue is empty.
    @discardableResult
    func advance() -> Bool {
        guard !queue.isEmpty else { current = nil; return false }
        current = queue.removeFirst()
        return true
    }
}

/// The banner itself: macOS-notification-shaped, but Pulse's own Liquid Glass — the system
/// refuses `UserNotifications` to an anonymously (ad-hoc) signed app with
/// `UNErrorDomain Code=1`, so the app draws its alerts itself (spec §7 note).
struct AlertBannerView: View {
    let model: AlertBannerModel
    var onTap: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack {
            if let item = model.current {
                HStack(spacing: 10) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable().frame(width: 30, height: 30)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.title).font(.system(size: 12, weight: .bold)).foregroundStyle(.primary)
                        Text(item.body).font(.system(size: 12)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 10).padding(.horizontal, 12)
                .frame(width: AlertBannerWindowController.bannerWidth)
                .background {
                    if model.isPresented {
                        Color.clear
                            .glassEffect(.regular, in: .rect(cornerRadius: 14))
                            .glassEffectTransition(.materialize)
                    }
                }
                .scaleEffect(model.isPresented ? 1 : 0.9, anchor: .top)
                .opacity(model.isPresented ? 1 : 0)
                .animation(Motion.reduced(Motion.materialize, reduceMotion: reduceMotion), value: model.isPresented)
                .contentShape(RoundedRectangle(cornerRadius: 14))
                .onTapGesture(perform: onTap)
            }
        }
        .padding(AlertBannerWindowController.shadowMargin)
    }
}

/// Owns the banner window: a small non-activating glass panel that materializes below the menu
/// bar on the dock's side of its screen, holds, dissolves, and then shows the next queued alert.
@MainActor
final class AlertBannerWindowController {
    static let bannerWidth: CGFloat = 300
    static let shadowMargin: CGFloat = 30
    /// How long a banner stays before dissolving on its own.
    static let holdSeconds: TimeInterval = 4.2

    let panel: FloatingPanel
    let model = AlertBannerModel()
    /// Where the banner belongs right now — the dock's screen and edge. Re-read per show.
    var placement: () -> (screen: NSScreen?, edge: ScreenEdge) = { (NSScreen.main, .right) }

    private let hosting: MarginHostingView<AlertBannerView>
    private var hideToken = 0

    init() {
        panel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: Self.bannerWidth + 2 * Self.shadowMargin, height: 120))
        let view = AlertBannerView(model: model)
        hosting = MarginHostingView(rootView: view)
        hosting.margin = Self.shadowMargin
        hosting.rootView = AlertBannerView(model: model, onTap: { [weak self] in self?.dismissCurrent() })
        panel.contentView = hosting
        panel.hasShadow = true
        panel.alphaValue = 1
    }

    /// Queue an alert; present immediately when nothing is showing.
    func show(title: String, body: String) {
        model.enqueue(BannerItem(title: title, body: body))
        guard model.current == nil else { return }
        presentNext()
    }

    /// Pop the next queued alert and materialize it, scheduling its own dissolve.
    private func presentNext() {
        guard model.advance() else { return }
        place()
        panel.orderFrontRegardless()
        panel.invalidateShadow()
        withAnimation(Motion.reduced(Motion.materialize, reduceMotion: reduceMotion)) {
            model.isPresented = true
        }
        hideToken += 1
        let token = hideToken
        // Same post-sleep re-check as the dock (`FloatingPanel.ensureOnScreen`): an alert whose
        // order-front was swallowed would play out entirely off the WindowServer's list and the
        // user would simply never see it. A beat later, because the server's on-screen list only
        // updates a turn after the order.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self, token == self.hideToken, self.model.current != nil else { return }
            self.panel.ensureOnScreen()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.holdSeconds) { [weak self] in
            guard let self, token == self.hideToken else { return }
            self.dismissCurrent()
        }
    }

    /// Dissolve the current banner; when the dissolve lands, show the next queued one.
    func dismissCurrent() {
        guard model.current != nil, model.isPresented else { return }
        hideToken += 1
        let token = hideToken
        withAnimation(Motion.reduced(Motion.materialize, reduceMotion: reduceMotion)) {
            model.isPresented = false
        }
        let wait = reduceMotion ? Motion.reducedSeconds : Motion.materializeSeconds
        DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in
            guard let self, token == self.hideToken else { return }
            self.model.current = nil
            if self.model.hasQueued {
                self.presentNext()
            } else {
                self.panel.orderOut(nil)
            }
        }
    }

    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    /// Below the menu bar, inset from the dock's edge — where macOS banners live, on the
    /// side the dock occupies.
    private func place() {
        let (screenMaybe, edge) = placement()
        guard let screen = screenMaybe else { return }
        let visible = screen.visibleFrame
        hosting.layoutSubtreeIfNeeded()
        let height = max(60, hosting.fittingSize.height)
        let width = Self.bannerWidth + 2 * Self.shadowMargin
        let inset: CGFloat = 14 - Self.shadowMargin   // the *banner* sits 14 pt in; the margin overhangs
        let x = edge == .right ? visible.maxX - width - inset : visible.minX + inset
        let y = visible.maxY - height - (12 - Self.shadowMargin)
        panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
        panel.invalidateShadow()
    }
}

/// Fans one alert out to both channels: the system poster (a no-op until macOS ever grants
/// authorization — see the Code=1 note above) and Pulse's own banner, which always works.
final class CompositePoster: NotificationPosting {
    private let system: any NotificationPosting
    private let banner: @Sendable (String, String) -> Void

    init(system: any NotificationPosting, banner: @escaping @Sendable (String, String) -> Void) {
        self.system = system
        self.banner = banner
    }

    func post(title: String, body: String, identifier: String) {
        system.post(title: title, body: body, identifier: identifier)
        banner(title, body)
    }

    /// Only the system channel has an authorization to warm up.
    func warmUp() { system.warmUp() }
}
