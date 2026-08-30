import SwiftUI
import PulseCore

/// Pure drawing. Hit-testing lives in `DockInteractionView`; this view never handles input.
struct DockView: View {
    let model: DockModel

    var body: some View {
        let layout = model.layout
        ZStack(alignment: .topLeading) {
            panel(layout)
                .frame(width: layout.size.width, height: layout.size.height)
                .offset(x: layout.contentOrigin.x, y: layout.contentOrigin.y)

            ForEach(Array(model.cells.enumerated()), id: \.element.id) { index, cell in
                if index < layout.cellFrames.count {
                    let frame = layout.cellFrames[index]
                    RingView(provider: cell.id, state: cell.state)
                        .scaleEffect(model.hoveredIndex == index ? 1.03 : 1)
                        .animation(Motion.ease(0.16), value: model.hoveredIndex)
                        .position(x: frame.midX + layout.contentOrigin.x, y: frame.midY + layout.contentOrigin.y)
                }
            }

            Image(systemName: "gearshape.fill")
                .font(.system(size: Metrics.gearSize, weight: .semibold))
                .foregroundStyle(model.gearHovered ? Color.white : Palette.gray)
                .position(x: layout.gearCenter.x + layout.contentOrigin.x, y: layout.gearCenter.y + layout.contentOrigin.y)
        }
        .frame(width: layout.windowSize.width, height: layout.windowSize.height, alignment: .topLeading)
    }

    /// Notch is a flat opaque fill; Glass is a translucent tint over the window's vibrancy
    /// (`DockInteractionView`'s effect view), bordered and lit exactly like the callout.
    @ViewBuilder
    private func panel(_ layout: DockLayout) -> some View {
        let shape = DockShape(edge: layout.edge, style: model.style)
        switch model.style {
        case .notch:
            shape.fill(Palette.panel)
        case .glass:
            shape.fill(Palette.glassTint)
                // The highlight is laid out full-size and *then* clipped to the silhouette, so
                // its 1 pt strip stops at the rounded corners instead of overhanging them.
                .overlay {
                    VStack(spacing: 0) {
                        LinearGradient(colors: [Palette.glassHighlight, .clear], startPoint: .top, endPoint: .bottom)
                            .frame(height: 1)
                        Spacer(minLength: 0)
                    }
                    .clipShape(shape)
                }
                .overlay { shape.stroke(Palette.glassBorder, lineWidth: 1) }
                // No SwiftUI `.shadow` here: it would be clipped at the hosting view's bounds
                // and, on the inward side, drawn *over* the desktop rather than behind the
                // panel. The drop shadow is the window's own (`DockPanel.hasShadow`), exactly
                // as the callout does it.
        }
    }
}
