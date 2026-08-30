import SwiftUI
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
    let model: SettingsModel
    let actions: SettingsActions
    let updatesAvailable: Bool
    let version: String
    /// Shown as a link when the bundle declares one; `nil` keeps the About block text-only.
    var repositoryURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Pulse settings").font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                Spacer()
                Button(action: actions.close) { Image(systemName: "xmark").font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.gray) }
                    .buttonStyle(.plain).keyboardShortcut(.cancelAction)
            }

            providers

            section("Alert threshold") {
                Picker("", selection: Binding(get: { prefs.alertThreshold }, set: { actions.setThreshold($0) })) {
                    // The same set `Preferences` validates against, so the picker and the
                    // persisted value can never drift apart.
                    ForEach(Preferences.validThresholds.sorted(), id: \.self) { Text("\($0)%").tag($0) }
                }.pickerStyle(.segmented).labelsHidden()
            }

            section("Screen edge") {
                Picker("", selection: Binding(get: { prefs.edge }, set: { actions.setEdge($0) })) {
                    Text("Left").tag(ScreenEdge.left)
                    Text("Right").tag(ScreenEdge.right)
                }.pickerStyle(.segmented).labelsHidden()
            }

            section("Dock style") {
                Picker("", selection: Binding(get: { prefs.dockStyle }, set: { actions.setDockStyle($0) })) {
                    Text("Notch").tag(DockStyle.notch)
                    Text("Glass").tag(DockStyle.glass)
                }.pickerStyle(.segmented).labelsHidden()
            }

            toggleRow("Auto-hide", isOn: Binding(get: { prefs.autoHide }, set: { actions.setAutoHide($0) }))
            VStack(alignment: .leading, spacing: 6) {
                toggleRow("Launch at login", isOn: Binding(get: { prefs.launchAtLogin }, set: { actions.setLaunchAtLogin($0) }))
                // macOS took the registration but wants the user to allow it; the toggle stays
                // on and this says what is left to do, rather than silently snapping back.
                if model.loginItemNeedsApproval {
                    Text("Approve Pulse in System Settings → Login Items")
                        .font(.system(size: 11)).foregroundStyle(Palette.gray)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack {
                toggleRow("Check for updates automatically", isOn: Binding(get: { prefs.autoUpdate }, set: { actions.setAutoUpdate($0) }))
                Spacer()
                Button("Check now", action: actions.checkForUpdates).disabled(!updatesAvailable)
            }

            section("About") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Pulse \(version)").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                    Text("Pulse reads usage from your local Claude / Codex / Gemini CLI sign-ins. It talks only to those providers and to GitHub for updates. No analytics.")
                        .font(.system(size: 12)).foregroundStyle(Palette.gray).fixedSize(horizontal: false, vertical: true)
                    if let repositoryURL {
                        Link("View source on GitHub", destination: repositoryURL)
                            .font(.system(size: 12)).foregroundStyle(Palette.green)
                    }
                }
            }

            Button("Quit Pulse", action: actions.quit).buttonStyle(.plain).foregroundStyle(Palette.red).font(.system(size: 14, weight: .medium))
        }
        .padding(Metrics.settingsPadding)
        .frame(width: Metrics.settingsWidth)
        .background(RoundedRectangle(cornerRadius: Metrics.settingsRadius, style: .continuous).fill(Palette.panel))
        .shadow(color: .black.opacity(0.45), radius: 25, y: 18)
    }

    /// Reordering is ▲/▼ buttons rather than a drag handle in a `List`, because
    /// inside the non-activating settings panel a `List`'s `.onMove` drag gesture swallows plain
    /// row clicks and reinterprets them as row drags, so a tap on a provider's switch reordered the
    /// list *and* flipped a different provider's toggle. Buttons are unambiguous, need no `List`
    /// (hence no nested scroll view inside a fixed-height panel), and drive the same
    /// `actions.reorder` with the same whole-array contract.
    private var providers: some View {
        section("Providers") {
            VStack(spacing: 10) {
                ForEach(prefs.providerOrder, id: \.self) { id in
                    HStack(spacing: 10) {
                        reorderButtons(for: id)
                        id.glyph(size: 18)
                        Text(id.displayName).font(.system(size: 15)).foregroundStyle(.white)
                        Spacer()
                        Toggle("", isOn: Binding(get: { prefs.enabledProviders.contains(id) }, set: { actions.setEnabled(id, $0) }))
                            .toggleStyle(.switch).tint(Palette.green).labelsHidden()
                    }
                    .frame(height: 24)
                }
            }
        }
    }

    private func reorderButtons(for id: ProviderID) -> some View {
        let index = prefs.providerOrder.firstIndex(of: id)
        return VStack(spacing: 1) {
            arrow("chevron.up", enabled: (index ?? 0) > 0) { move(id, by: -1) }
            arrow("chevron.down", enabled: (index ?? 0) < prefs.providerOrder.count - 1) { move(id, by: 1) }
        }
        .frame(width: 14)
    }

    private func arrow(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(enabled ? Palette.gray : Palette.disconnected.opacity(0.5))
                .frame(width: 14, height: 11)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    /// Swap with the neighbour and hand the whole new order back, exactly as `.onMove` did.
    private func move(_ id: ProviderID, by delta: Int) {
        var order = prefs.providerOrder
        guard let i = order.firstIndex(of: id), order.indices.contains(i + delta) else { return }
        order.swapAt(i, i + delta)
        actions.reorder(order)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased()).font(.system(size: 12, weight: .medium)).tracking(0.6).foregroundStyle(Palette.gray)
            content()
        }
    }

    private func toggleRow(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(title).font(.system(size: 15)).foregroundStyle(.white)
            Spacer()
            Toggle("", isOn: isOn).toggleStyle(.switch).tint(Palette.green).labelsHidden()
        }
    }
}
