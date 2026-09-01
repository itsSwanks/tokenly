import SwiftUI
import PulseCore

struct CalloutView: View {
    let model: CalloutModel
    var onRetry: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// One Liquid Glass bubble — card *and* tail in a single `CalloutBubbleShape` (spec §18.2),
    /// so the glass refracts through the tail and its rim light runs all the way round the point.
    ///
    /// The glass lives inside an `if`: `.glassEffectTransition(.materialize)` only plays when the
    /// glass is inserted or removed, and that insertion is `CalloutWindowController` flipping
    /// `model.isPresented` inside a `withAnimation`. The *card* stays in the tree either way —
    /// `CalloutWindowController.place()` measures `NSHostingView.fittingSize` to size the window
    /// before the callout is shown, and a gated card would measure empty.
    ///
    /// No SwiftUI `.shadow`: the bubble fills its window edge to edge apart from the transparent
    /// `CalloutPositioner.shadowMargin`, so `CalloutPanel.hasShadow` draws the drop shadow instead.
    var body: some View {
        card
            .padding(model.edge == .right ? .trailing : .leading, Metrics.tailLength)
            .background {
                if model.isPresented {
                    Color.clear
                        .glassEffect(.regular, in: CalloutBubbleShape(edge: model.edge, tailY: tailYFromTop))
                        .glassEffectTransition(.materialize)
                }
            }
            // The content motion that rides along with the glass transition: the bubble grows out
            // of the dock, so the anchor is the tail side.
            .scaleEffect(model.isPresented ? 1 : 0.94, anchor: model.edge == .right ? .trailing : .leading)
            .opacity(model.isPresented ? 1 : 0)
            .animation(Motion.reduced(Motion.materialize, reduceMotion: reduceMotion), value: model.isPresented)
            .background(GeometryReader { g in Color.clear.onAppear { model.height = g.size.height }.onChange(of: g.size.height) { _, h in model.height = h } })
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            switch model.status {
            case .loading:
                Text("Loading…").font(.system(size: 13)).foregroundStyle(.secondary)
            case .disconnected(let error):
                disconnected(error)
            case .live(let snap):
                windows(snap)
            case .stale(let snap, _):
                windows(snap)
                StaleFooter(text: "Last updated \(minutesAgo(snap.fetchedAt)) min ago · tap to retry", onRetry: onRetry)
            }
        }
        .padding(.vertical, Metrics.calloutPaddingV)
        .padding(.horizontal, Metrics.calloutPaddingH)
        .frame(width: Metrics.calloutWidth, alignment: .leading)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                model.provider.glyph(size: 17)
                Text("\(model.provider.displayName) Usage").font(.system(size: 15, weight: .semibold)).foregroundStyle(.primary)
                if let plan = model.status.snapshot?.plan {
                    Text(plan.uppercased()).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Palette.pill))
                }
            }
            if let session = model.status.snapshot?.sessionWindow, UsageLevel.isExhausted(percent: session.usedPercent) {
                Text(ResetFormatter.text(resetsAt: session.resetsAt, now: model.now))
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.red)
            }
        }
    }

    private func windows(_ snap: UsageSnapshot) -> some View {
        // Spacing inside a block is uneven by design (7 pt above the bar, 6 pt below), so the
        // stack has none of its own and each element carries its own top inset.
        ForEach(Array(snap.windows.enumerated()), id: \.offset) { _, w in
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(w.label).font(.system(size: 13)).foregroundStyle(.primary)
                    if w.kind == .session {
                        Text("● ring").font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(ResetFormatter.text(resetsAt: w.resetsAt, now: model.now))
                        .font(.system(size: 12)).monospacedDigit().foregroundStyle(.secondary)
                }
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Palette.track)
                        Capsule().fill(UsageLevel(percent: w.usedPercent).color)
                            .frame(width: g.size.width)
                            .scaleEffect(x: max(0.001, min(1, w.usedPercent / 100)), anchor: .leading)
                            .animation(Motion.sweep, value: w.usedPercent)
                    }
                }
                .frame(height: 5)
                .padding(.top, 7)
                Text("\(Int(w.usedPercent.rounded()))% Used").font(.system(size: 12)).monospacedDigit().foregroundStyle(.secondary)
                    .padding(.top, 6)
            }
        }
    }

    private func disconnected(_ error: ProviderError) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(message(for: error)).font(.system(size: 13)).foregroundStyle(.primary)
            RetryPill(action: onRetry)
        }
    }

    private func message(for error: ProviderError) -> String {
        switch error {
        case .credentialsMissing(let hint): "Not signed in. \(hint)"
        case .credentialsExpired(let hint): hint
        case .unsupportedAccount(let message): message
        case .unexpectedResponse: "Tokenly needs an update for \(model.provider.displayName)."
        case .network(let detail): "Can't reach \(model.provider.displayName) right now. \(detail)"
        case .rateLimited: "\(model.provider.displayName) is rate-limiting requests; retrying shortly."
        }
    }

    /// `CalloutPositioner` measures the tail from the bubble's bottom (AppKit); `CalloutBubbleShape`
    /// wants it from the top (SwiftUI). Before the first height is reported there is nothing to
    /// flip, so the tail sits at the shape's own clamp.
    private var tailYFromTop: CGFloat {
        model.height > 0 ? model.height - model.tailY : model.height / 2
    }

    private func minutesAgo(_ date: Date) -> Int { max(0, Int(model.now.timeIntervalSince(date) / 60)) }
}

/// The disconnected state's retry button. Its own view so the hover state can live in
/// `@State`, which a `some View`-returning method on `CalloutView` cannot hold.
private struct RetryPill: View {
    var action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Text("Retry").font(.system(size: 12, weight: .medium)).foregroundStyle(.primary)
                .padding(.horizontal, 14).padding(.vertical, 6)
                .background(Capsule().fill(hovered ? Palette.pillHover : Palette.pill))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

/// The stale state's "tap to retry" line. Same pill treatment as `RetryPill`, quieter, so the
/// tap target reads as one — it is easy to miss that the sentence is clickable at all.
private struct StaleFooter: View {
    let text: String
    var onRetry: () -> Void
    @State private var hovered = false

    var body: some View {
        Text(text)
            .font(.system(size: 11)).foregroundStyle(.secondary)
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(Capsule().fill(hovered ? Palette.pillHover : Palette.pill))
            .contentShape(Capsule())
            .onHover { hovered = $0 }
            .onTapGesture { onRetry() }
    }
}
