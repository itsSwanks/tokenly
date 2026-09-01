import SwiftUI
import AppKit
import PulseCore

/// `SettingsView` is a value type built and rendered on the main actor (`View.body` is
/// `@MainActor`-isolated), so every closure literal below inherits that isolation and may
/// freely touch `prefs` and `actions`. What it may *not* do is hand `Binding.init(get:set:)`
/// one of `SettingsActions`' stored closures directly: `set` is declared
/// `@isolated(any) @Sendable`, and a plain non-Sendable function *value* can't be converted
/// to it ("converting non-Sendable function value … may introduce data races"). Wrapping each
/// one in a closure literal — `{ actions.setEdge($0) }` — is the minimal fix: the literal is
/// formed here on the main actor, so it satisfies `@isolated(any)` while capturing `actions`
/// within its own isolation domain. Nothing is marked `@unchecked Sendable`.
struct SettingsView: View {
    let prefs: Preferences
    /// Observed directly (it is `@Observable`), so the provider rows' usage figures keep moving
    /// while the panel is open — no render plumbing, no copy of the statuses.
    let store: UsageStore
    let model: SettingsModel
    let actions: SettingsActions
    let updatesAvailable: Bool
    let version: String
    /// Shown as a link when the bundle declares one; `nil` keeps the footer link out entirely.
    var repositoryURL: URL?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The stationary coordinate space the reorder drag measures in (see the gesture comment).
    private static let sheetSpace = "settingsSheet"

    /// The provider drag in flight, if any. All geometry decisions are `ProviderReorder`'s.
    @State private var drag: ProviderDragState?

    private struct ProviderDragState {
        let id: ProviderID
        let from: Int
        var translation: CGFloat
    }

    /// One Liquid Glass sheet (spec §18.1) at System-Settings density (spec §19): a header, three
    /// inset grouped lists with hairline separators, a quiet footnote and a footer line. Green is
    /// reserved for *on* — the segmented pickers are untinted, so selection is the system's
    /// neutral raised pill in both appearances.
    ///
    /// The glass lives inside an `if` and the whole sheet is padded by
    /// `CalloutPositioner.shadowMargin`: the `if` is what `.glassEffectTransition(.materialize)`
    /// plays on, and the padding is the transparent band `SettingsPanel.hasShadow` drops its
    /// shadow into. `MarginHostingView` hit-tests that band away, so clicks there fall through.
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            sectionHeader("PROVIDERS")
            providersGroup
            optionsGroup
            behaviorGroup
            footnote
            footer
        }
        .padding(.top, Metrics.settingsPadding)
        .padding(.horizontal, Metrics.settingsPadding)
        .padding(.bottom, Metrics.settingsPaddingBottom)
        .frame(width: Metrics.settingsWidth)
        .coordinateSpace(name: Self.sheetSpace)
        .background {
            if model.isPresented {
                Color.clear
                    .glassEffect(.regular, in: .rect(cornerRadius: Metrics.settingsRadius))
                    .glassEffectTransition(.materialize)
            }
        }
        // The sheet grows out of the dock, so it scales from whichever side the dock is on.
        .scaleEffect(model.isPresented ? 1 : 0.94, anchor: prefs.edge == .right ? .trailing : .leading)
        .opacity(model.isPresented ? 1 : 0)
        .animation(Motion.reduced(Motion.materialize, reduceMotion: reduceMotion), value: model.isPresented)
        // Room for the window shadow (`SettingsPanel.hasShadow`); transparent, and
        // `MarginHostingView` hit-tests it away so clicks there reach the desktop.
        .padding(CalloutPositioner.shadowMargin)
    }

    // MARK: - Header (spec §19.2)

    private var header: some View {
        HStack(spacing: 9) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 19, height: 19)
                .clipShape(RoundedRectangle(cornerRadius: 5))
            Text("Tokenly").font(.system(size: 13, weight: .semibold)).tracking(-0.08).foregroundStyle(.primary)
            Text(version).font(.system(size: 11)).monospacedDigit().foregroundStyle(.secondary)
            Spacer()
            CloseButton(action: actions.close)
        }
        .padding(.horizontal, 4)
        .padding(.top, 2)
        .padding(.bottom, 12)
    }

    // MARK: - Providers (spec §19.3)

    private var providersGroup: some View {
        group {
            ForEach(Array(prefs.providerOrder.enumerated()), id: \.element) { index, id in
                providerRow(id, at: index)
            }
        }
    }

    private func providerRow(_ id: ProviderID, at index: Int) -> some View {
        let enabled = prefs.enabledProviders.contains(id)
        let dragged = drag?.id == id
        return VStack(spacing: 0) {
            if index > 0 { separator }
            HStack(spacing: 10) {
                grip(for: id, at: index)
                id.glyph(size: 15, color: enabled ? .primary : .primary.opacity(0.34))
                Text(id.displayName).font(.system(size: 13)).tracking(-0.08).foregroundStyle(.primary)
                Spacer(minLength: 8)
                Text(SettingsUsage.label(status: store.statuses[id], enabled: enabled))
                    .font(.system(size: 11)).monospacedDigit().foregroundStyle(.secondary)
                Toggle("", isOn: Binding(get: { prefs.enabledProviders.contains(id) }, set: { actions.setEnabled(id, $0) }))
                    .toggleStyle(.switch).controlSize(.small).tint(Palette.green).labelsHidden()
            }
            .padding(.horizontal, 10)
            .frame(height: Metrics.settingsRowHeight)
        }
        .offset(y: rowOffset(at: index))
        .zIndex(dragged ? 1 : 0)
        .shadow(color: .black.opacity(dragged ? 0.18 : 0), radius: dragged ? 6 : 0, y: dragged ? 2 : 0)
        .animation(Motion.reduced(Motion.settle, reduceMotion: reduceMotion), value: proposedIndex)
    }

    /// The two-bar grab handle. The drag gesture lives here and nowhere else — that scoping is
    /// load-bearing (see `ProviderReorder`): row taps and the switches stay unambiguous.
    private func grip(for id: ProviderID, at index: Int) -> some View {
        VStack(spacing: 2.5) {
            Capsule().fill(Palette.grip).frame(width: 11, height: 1.5)
            Capsule().fill(Palette.grip).frame(width: 11, height: 1.5)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 2)
        .contentShape(Rectangle())
        // The gesture measures in the *sheet's* coordinate space, never `.local`: the dragged row
        // offsets itself by this very translation, so a local-space reading would subtract the
        // row's own movement and oscillate around half the finger's travel — commits then depend
        // on where the bounce happens to be at mouse-up. The sheet doesn't move during a drag.
        .gesture(
            DragGesture(minimumDistance: 2, coordinateSpace: .named(Self.sheetSpace))
                .onChanged { value in
                    if drag == nil { drag = ProviderDragState(id: id, from: index, translation: 0) }
                    drag?.translation = value.translation.height
                }
                .onEnded { _ in commitDrag() }
        )
    }

    private var proposedIndex: Int? {
        guard let drag else { return nil }
        return ProviderReorder.proposedIndex(from: drag.from, translation: drag.translation,
                                             rowHeight: Metrics.settingsRowHeight, count: prefs.providerOrder.count)
    }

    private func rowOffset(at index: Int) -> CGFloat {
        guard let drag, let proposedIndex else { return 0 }
        if index == drag.from { return drag.translation }
        return ProviderReorder.rowOffset(index: index, draggedFrom: drag.from, proposed: proposedIndex,
                                         rowHeight: Metrics.settingsRowHeight)
    }

    private func commitDrag() {
        guard let drag, let proposedIndex else { return }
        if proposedIndex != drag.from {
            actions.reorder(ProviderReorder.reordered(prefs.providerOrder, from: drag.from, to: proposedIndex))
        }
        withAnimation(Motion.reduced(Motion.settle, reduceMotion: reduceMotion)) { self.drag = nil }
    }

    // MARK: - Options (spec §19.4)

    private var optionsGroup: some View {
        group {
            optionRow("Appearance", first: true,
                      options: [("Auto", AppearanceMode.auto), ("Light", .light), ("Dark", .dark)],
                      selection: prefs.appearance) { actions.setAppearance($0) }
            // The same set `Preferences` validates against, so the control and the
            // persisted value can never drift apart.
            optionRow("Alert threshold",
                      options: Preferences.validThresholds.sorted().map { ("\($0)%", $0) },
                      selection: prefs.alertThreshold) { actions.setThreshold($0) }
            optionRow("Screen edge",
                      options: [("Left", ScreenEdge.left), ("Right", .right)],
                      selection: prefs.edge) { actions.setEdge($0) }
            optionRow("Dock style",
                      options: [("Notch", DockStyle.notch), ("Pill", .pill)],
                      selection: prefs.dockStyle) { actions.setDockStyle($0) }
            optionRow("Dock size",
                      options: [("S", DockSize.small), ("M", .medium), ("L", .large)],
                      selection: prefs.dockSize) { actions.setDockSize($0) }
        }
    }

    private func optionRow<Selection: Hashable>(
        _ label: String, first: Bool = false,
        options: [(String, Selection)], selection: Selection, select: @escaping (Selection) -> Void
    ) -> some View {
        VStack(spacing: 0) {
            if !first { separator }
            HStack {
                Text(label).font(.system(size: 13)).tracking(-0.08).foregroundStyle(.primary)
                Spacer(minLength: 12)
                SegmentedControl(options: options.map { (label: $0.0, value: $0.1) },
                                 selection: selection, select: select)
            }
            .padding(.horizontal, 10)
            .frame(height: Metrics.settingsOptionRowHeight)
        }
    }

    // MARK: - Behavior (spec §19.5)

    private var behaviorGroup: some View {
        group {
            behaviorRow("Auto-hide", subtitle: "Retract to a glass handle at the edge", first: true,
                        isOn: Binding(get: { prefs.autoHide }, set: { actions.setAutoHide($0) }))
            // macOS took the registration but wants the user to allow it; the toggle stays on
            // and the subtitle says what is left to do, rather than silently snapping back.
            behaviorRow("Launch at login",
                        subtitle: model.loginItemNeedsApproval
                            ? "Approve Tokenly in System Settings → Login Items"
                            : "Start Tokenly when you sign in",
                        isOn: Binding(get: { prefs.launchAtLogin }, set: { actions.setLaunchAtLogin($0) }))
            behaviorRow("Automatic updates", subtitle: "Checked once a day",
                        isOn: Binding(get: { prefs.autoUpdate }, set: { actions.setAutoUpdate($0) })) {
                Button("Check now", action: actions.checkForUpdates)
                    .buttonStyle(.bordered).controlSize(.small).disabled(!updatesAvailable)
            }
        }
    }

    private func behaviorRow(
        _ title: String, subtitle: String, first: Bool = false, isOn: Binding<Bool>
    ) -> some View {
        behaviorRow(title, subtitle: subtitle, first: first, isOn: isOn) { EmptyView() }
    }

    private func behaviorRow<Accessory: View>(
        _ title: String, subtitle: String, first: Bool = false, isOn: Binding<Bool>,
        @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        VStack(spacing: 0) {
            if !first { separator }
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 13)).tracking(-0.08).foregroundStyle(.primary)
                    Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                accessory()
                Toggle("", isOn: isOn).toggleStyle(.switch).controlSize(.small).tint(Palette.green).labelsHidden()
            }
            .padding(.horizontal, 10)
            .frame(height: Metrics.settingsOptionRowHeight)
        }
    }

    // MARK: - Footnote + footer (spec §19.5)

    private var footnote: some View {
        Text("Reads usage from your local Claude, Codex and Gemini sign-ins. Talks only to those providers and to GitHub for updates. No analytics.")
            .font(.system(size: 11.5)).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
    }

    private var footer: some View {
        HStack {
            if let repositoryURL {
                Link("View source on GitHub", destination: repositoryURL)
                    .font(.system(size: 11.5)).foregroundStyle(Palette.link)
            }
            Spacer()
            QuitButton(action: actions.quit)
        }
        .padding(.top, 12)
        .padding(.horizontal, 4)
    }

    // MARK: - Shared pieces

    /// One inset grouped list (spec §19.1): radius-10, an adaptive fill and a 0.5 pt ring. The
    /// group is deliberately *not* clipped, so a lifted provider row may float past its bounds.
    private func group<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0, content: content)
            .background(RoundedRectangle(cornerRadius: Metrics.settingsGroupRadius).fill(Palette.group))
            .overlay(RoundedRectangle(cornerRadius: Metrics.settingsGroupRadius).strokeBorder(Palette.groupRing, lineWidth: 0.5))
            .padding(.bottom, 16)
    }

    private var separator: some View {
        Rectangle().fill(Palette.separator).frame(height: 0.5).padding(.leading, 10)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title).font(.system(size: 11, weight: .semibold)).tracking(0.5).foregroundStyle(.secondary)
            .padding(.horizontal, 4)
            .padding(.bottom, 6)
    }
}

/// The header's 20 pt circular close control: quiet until hovered, still `Esc`.
private struct CloseButton: View {
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.primary.opacity(hovered ? 0.16 : 0.08)))
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.cancelAction)
        .onHover { hovered = $0 }
    }
}

/// Quit is hover-only red (spec §19.5): secondary text that turns `quitHover` on a soft red pill,
/// so the panel's resting state carries no alarm colour.
private struct QuitButton: View {
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Text("Quit Tokenly")
                .font(.system(size: 11.5))
                .foregroundStyle(hovered ? Palette.quitHover : Color.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 6).fill(Palette.red.opacity(hovered ? 0.16 : 0)))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}
