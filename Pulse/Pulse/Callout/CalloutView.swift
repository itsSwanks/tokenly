import SwiftUI
import PulseCore

struct CalloutView: View {
    let model: CalloutModel
    var onRetry: () -> Void = {}

    /// True for one frame after every show/move, then animated away — the "glass frost".
    @State private var frosted = false

    var body: some View {
        HStack(spacing: 0) {
            if model.edge == .left { tail(flipped: true) }
            card
            if model.edge == .right { tail(flipped: false) }
        }
        .background(GeometryReader { g in Color.clear.onAppear { model.height = g.size.height }.onChange(of: g.size.height) { _, h in model.height = h } })
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            switch model.status {
            case .loading:
                Text("Loading…").font(.system(size: 13)).foregroundStyle(Palette.gray)
            case .disconnected(let error):
                disconnected(error)
            case .live(let snap):
                windows(snap)
            case .stale(let snap, _):
                windows(snap)
                StaleFooter(text: "Last updated \(minutesAgo(snap.fetchedAt)) min ago · tap to retry", onRetry: onRetry)
            }
        }
        // The frost is on the content only: blurring the glass tint too would smear its
        // border and leave a soft-edged rectangle over the vibrancy.
        .blur(radius: frosted ? 14 : 0)
        .animation(Motion.ease(Motion.frostIn), value: frosted)
        .opacity(frosted ? 0 : 1)
        // Opacity lands at 40 % of the blur's duration, per the design's easing note.
        .animation(Motion.ease(Motion.frostIn * 0.4), value: frosted)
        .padding(.vertical, Metrics.calloutPaddingV)
        .padding(.horizontal, Metrics.calloutPaddingH)
        .frame(width: Metrics.calloutWidth, alignment: .leading)
        // No SwiftUI `.shadow` here: the card fills its content-sized window edge to edge, so a
        // SwiftUI shadow has nowhere to spill. `CalloutPanel.hasShadow` draws it instead.
        .background(glass)
        .opacity(model.isPresented ? 1 : 0)
        .animation(.easeOut(duration: Motion.calloutFadeIn), value: model.isPresented)
        .task(id: model.frostKey) { await replayFrost() }
    }

    /// The tint and border that sit on top of the window's vibrancy (`CalloutContainerView`).
    private var glass: some View {
        RoundedRectangle(cornerRadius: Metrics.calloutRadius, style: .continuous)
            .fill(Palette.glassTint)
            .overlay(alignment: .top) {
                LinearGradient(colors: [Palette.glassHighlight, .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 1)
            }
            .overlay {
                RoundedRectangle(cornerRadius: Metrics.calloutRadius, style: .continuous)
                    .strokeBorder(Palette.glassBorder, lineWidth: 1)
            }
    }

    /// Snap to frosted without animation, let one frame render, then de-blur.
    /// A cancelled sleep means another show/move arrived — leave the card frosted and let
    /// that task run the de-blur, so the replay never flashes sharp in between.
    private func replayFrost() async {
        var snap = Transaction()
        snap.disablesAnimations = true
        withTransaction(snap) { frosted = true }
        do { try await Task.sleep(for: .milliseconds(16)) } catch { return }
        frosted = false
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                model.provider.glyph(size: 17)
                Text("\(model.provider.displayName) Usage").font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                if let plan = model.status.snapshot?.plan {
                    Text(plan.uppercased()).font(.system(size: 10, weight: .semibold)).foregroundStyle(Palette.gray)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Palette.track))
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
                    Text(w.label).font(.system(size: 13)).foregroundStyle(.white)
                    if w.kind == .session {
                        Text("● ring").font(.system(size: 10)).foregroundStyle(Palette.gray)
                    }
                    Spacer()
                    Text(ResetFormatter.text(resetsAt: w.resetsAt, now: model.now))
                        .font(.system(size: 12)).monospacedDigit().foregroundStyle(Palette.gray)
                }
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Palette.track)
                        Capsule().fill(UsageLevel(percent: w.usedPercent).color)
                            .frame(width: g.size.width)
                            .scaleEffect(x: max(0.001, min(1, w.usedPercent / 100)), anchor: .leading)
                            .animation(Motion.ease(Motion.ringSweep), value: w.usedPercent)
                    }
                }
                .frame(height: 5)
                .padding(.top, 7)
                Text("\(Int(w.usedPercent.rounded()))% Used").font(.system(size: 12)).monospacedDigit().foregroundStyle(Palette.gray)
                    .padding(.top, 6)
            }
        }
    }

    private func disconnected(_ error: ProviderError) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(message(for: error)).font(.system(size: 13)).foregroundStyle(.white)
            RetryPill(action: onRetry)
        }
    }

    private func message(for error: ProviderError) -> String {
        switch error {
        case .credentialsMissing(let hint): "Not signed in. \(hint)"
        case .credentialsExpired(let hint): hint
        case .unsupportedAccount(let message): message
        case .unexpectedResponse: "Pulse needs an update for \(model.provider.displayName)."
        case .network(let detail): "Can't reach \(model.provider.displayName) right now. \(detail)"
        case .rateLimited: "\(model.provider.displayName) is rate-limiting requests; retrying shortly."
        }
    }

    /// The rotation has to be applied *before* the offset: outside it, it would mirror the
    /// translation too and land the left-edge tail at `-tailOffset`.
    private func tail(flipped: Bool) -> some View {
        TailShape().fill(Palette.glassTail)
            .frame(width: Metrics.tailLength, height: Metrics.tailHalfHeight * 2)
            .rotationEffect(.degrees(flipped ? 180 : 0))
            .offset(y: tailOffset)
    }

    /// SwiftUI y grows downward; `tailY` is measured from the bottom.
    private var tailOffset: CGFloat {
        guard model.height > 0 else { return 0 }
        return (model.height - model.tailY) - model.height / 2
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
            Text("Retry").font(.system(size: 12, weight: .medium)).foregroundStyle(.white)
                .padding(.horizontal, 14).padding(.vertical, 6)
                .background(Capsule().fill(hovered ? Palette.pillHover : Palette.track))
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
            .font(.system(size: 11)).foregroundStyle(Palette.gray)
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(Capsule().fill(hovered ? Palette.pillHover : Palette.track))
            .contentShape(Capsule())
            .onHover { hovered = $0 }
            .onTapGesture { onRetry() }
    }
}

/// Solid triangle pointing right (rotated for the left edge).
struct TailShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}
