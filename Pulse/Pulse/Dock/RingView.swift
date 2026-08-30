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

/// One provider cell: ring, dark well with the glyph, percentage label.
struct RingView: View {
    let provider: ProviderID
    let state: RingState

    @State private var pulseDim = false
    @State private var spin = false

    private let d = Metrics.ringDiameter

    var body: some View {
        VStack(spacing: Metrics.labelGap) {
            ZStack {
                track
                progress
                Circle().fill(Palette.well).frame(width: Metrics.wellRadius * 2, height: Metrics.wellRadius * 2)
                provider.glyph(size: Metrics.glyphSize)
            }
            .frame(width: d, height: d)
            .accessibilityElement()
            .accessibilityLabel("\(provider.displayName) usage \(state.label)")
            .accessibilityValue(state.percent.map { "\(Int($0.rounded())) percent" } ?? state.label)

            label
                .frame(height: Metrics.labelHeight)
        }
        .opacity(state.isDimmed ? 0.6 : 1)
        .onAppear { startAnimations() }
        .onChange(of: state) { _, _ in startAnimations() }
    }

    // SwiftUI's `Circle().stroke()` centres the stroke on the shape's own edge (r 24 in a
    // 48 pt frame), so without this inset the outer edge lands at ⌀ 51.5 instead of the
    // spec's ⌀ 48. Insetting by half the stroke moves the centreline to r 22.
    private var strokeInset: CGFloat { Metrics.ringStroke / 2 }

    @ViewBuilder private var track: some View {
        switch state {
        case .disconnected:
            Circle().inset(by: strokeInset)
                .stroke(Palette.disconnected, style: StrokeStyle(lineWidth: Metrics.ringStroke, lineCap: .round, dash: [3.4, 4.6]))
        default:
            Circle().inset(by: strokeInset).stroke(Palette.track, lineWidth: Metrics.ringStroke)
        }
    }

    @ViewBuilder private var progress: some View {
        switch state {
        case .loading:
            Circle().inset(by: strokeInset).trim(from: 0, to: 0.23)
                .stroke(Palette.gray, style: StrokeStyle(lineWidth: Metrics.ringStroke, lineCap: .round))
                .rotationEffect(.degrees(spin ? 270 : -90))
                .animation(.linear(duration: 1.1).repeatForever(autoreverses: false), value: spin)
        case .value(let pct, let level, let pulses, _, _):
            Circle().inset(by: strokeInset).trim(from: 0, to: min(1, max(0, pct / 100)))
                .stroke(level.color, style: StrokeStyle(lineWidth: Metrics.ringStroke, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(Motion.ease(Motion.ringSweep), value: pct)
                .opacity(pulses && pulseDim ? 0.4 : 1)
                .animation(pulses ? .easeInOut(duration: Motion.pulse / 2).repeatForever(autoreverses: true) : .default, value: pulseDim)
        case .disconnected:
            EmptyView()
        }
    }

    @ViewBuilder private var label: some View {
        switch state {
        case .value(_, _, _, true, _):
            Text(state.label).font(.system(size: 11, weight: .medium)).foregroundStyle(.white)
        default:
            Text(state.label).font(.system(size: 16, weight: .medium)).monospacedDigit().foregroundStyle(.white)
        }
    }

    private func startAnimations() {
        if case .loading = state { spin = true } else { spin = false }
        if case .value(_, _, true, _, _) = state { pulseDim = true } else { pulseDim = false }
    }
}
