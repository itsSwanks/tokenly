import SwiftUI
import PulseCore

extension UsageLevel {
    var color: Color {
        switch self {
        case .green: Palette.green
        case .yellow: Palette.yellow
        case .orange: Palette.orange
        case .red: Palette.red
        }
    }
}

/// One provider cell: ring, vibrant well with the glyph, percentage label. Everything it draws
/// sits *inside* the dock's single glass slab, so the well and track are `.primary` fills at an
/// opacity rather than more glass (spec §18.2), and every dimension comes from `metrics`.
struct RingView: View {
    let provider: ProviderID
    let state: RingState
    let metrics: DockMetrics

    @State private var pulseDim = false
    @State private var spin = false

    private var d: CGFloat { metrics.ringDiameter }

    var body: some View {
        VStack(spacing: metrics.labelGap) {
            ZStack {
                track
                progress
                well
                provider.glyph(size: metrics.glyphSize)
            }
            .frame(width: d, height: d)
            .accessibilityElement()
            .accessibilityLabel("\(provider.displayName) usage \(state.label)")
            .accessibilityValue(state.percent.map { "\(Int($0.rounded())) percent" } ?? state.label)

            label
                .frame(height: metrics.labelHeight)
        }
        .opacity(state.isDimmed ? 0.6 : 1)
        .onAppear { startAnimations() }
        .onChange(of: state) { _, _ in startAnimations() }
    }

    // SwiftUI's `Circle().stroke()` centres the stroke on the shape's own edge (r 24 in a
    // 48 pt frame), so without this inset the outer edge lands at ⌀ 51.5 instead of the
    // spec's ⌀ 48. Insetting by half the stroke moves the centreline to r 22.
    private var strokeInset: CGFloat { metrics.ringStroke / 2 }

    /// The disc the glyph sits on: a vibrant fill with a hairline catching the light on its
    /// upper edge, so it reads as pressed into the glass rather than laid on top of it.
    private var well: some View {
        Circle()
            .fill(Palette.well)
            .overlay(
                Circle().strokeBorder(
                    LinearGradient(colors: [Palette.hairline, .clear], startPoint: .top, endPoint: .bottom),
                    lineWidth: 1)
            )
            .frame(width: metrics.wellRadius * 2, height: metrics.wellRadius * 2)
    }

    @ViewBuilder private var track: some View {
        switch state {
        case .disconnected:
            Circle().inset(by: strokeInset)
                .stroke(Palette.disconnected, style: StrokeStyle(lineWidth: metrics.ringStroke, lineCap: .round, dash: [3.4, 4.6]))
        default:
            Circle().inset(by: strokeInset).stroke(Palette.track, lineWidth: metrics.ringStroke)
        }
    }

    @ViewBuilder private var progress: some View {
        switch state {
        case .loading:
            Circle().inset(by: strokeInset).trim(from: 0, to: 0.23)
                .stroke(Color.secondary, style: StrokeStyle(lineWidth: metrics.ringStroke, lineCap: .round))
                .rotationEffect(.degrees(spin ? 270 : -90))
                .animation(.linear(duration: 1.1).repeatForever(autoreverses: false), value: spin)
        case .value(let pct, let level, let pulses, _, _):
            Circle().inset(by: strokeInset).trim(from: 0, to: min(1, max(0, pct / 100)))
                .stroke(level.color, style: StrokeStyle(lineWidth: metrics.ringStroke, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(Motion.sweep, value: pct)
                .opacity(pulses && pulseDim ? 0.4 : 1)
                .animation(pulses ? .easeInOut(duration: Motion.pulse / 2).repeatForever(autoreverses: true) : .default, value: pulseDim)
        case .disconnected:
            EmptyView()
        }
    }

    /// The percentage rolls digit by digit as it changes; "Limit reached" and "—" are words, so
    /// they just swap. `.numericText(value:)` needs the number itself, and only `.value` has one.
    @ViewBuilder private var label: some View {
        switch state {
        case .value(_, _, _, true, _):
            Text(state.label)
                .font(.system(size: metrics.smallLabelFontSize, weight: .medium))
                .foregroundStyle(.primary)
        default:
            Text(state.label)
                .font(.system(size: metrics.percentFontSize, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .contentTransition(.numericText(value: state.percent ?? 0))
                .animation(Motion.sweep, value: state.percent)
        }
    }

    private func startAnimations() {
        if case .loading = state { spin = true } else { spin = false }
        if case .value(_, _, true, _, _) = state { pulseDim = true } else { pulseDim = false }
    }
}
