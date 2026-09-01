import SwiftUI
import PulseCore

/// Pure drawing. Hit-testing lives in `DockInteractionView`; this view never handles input,
/// so hover and press states arrive through the model rather than through gestures.
struct DockView: View {
    let model: DockModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let layout = model.layout
        panelContent(layout)
            // Panel-body coordinates: the content is laid out inside the slab, and the flare
            // margin is added by the offset + window frame below, so nothing here has to carry
            // `contentOrigin` around.
            .frame(width: layout.size.width, height: layout.size.height, alignment: .topLeading)
            // The dock is one Liquid Glass slab in the chosen silhouette (spec §18.2) — never
            // stacked, never tinted: everything inside it is drawn with vibrant fills instead.
            // The glass samples the desktop behind the panel because the window is transparent
            // and unopaque.
            //
            // The rings, labels and gear are the glass's *content* rather than siblings stacked
            // on top of it, so the framework resolves `.primary`/`.secondary` against the tone it
            // actually rendered. As siblings they resolved against the window's appearance
            // instead, which drew near-black labels on dark glass whenever the two disagreed.
            //
            // No SwiftUI `.shadow` here: it would be clipped at the hosting view's bounds and, on
            // the inward side, drawn *over* the desktop rather than behind the panel. The drop
            // shadow is the window's own (`DockPanel.hasShadow`), exactly as the callout does it.
            .glassEffect(.regular, in: DockShape(edge: layout.edge, style: model.style, metrics: layout.metrics))
            .offset(x: layout.contentOrigin.x, y: layout.contentOrigin.y)
            .frame(width: layout.windowSize.width, height: layout.windowSize.height, alignment: .topLeading)
            // A size change is a new `layout` value, and `DockLayout` is `Equatable`, so every
            // position and dimension above morphs on one settle spring — the same clock the window
            // frame animates on (spec §18.4).
            .animation(Motion.reduced(Motion.settle, reduceMotion: reduceMotion), value: layout)
    }

    /// Everything that sits inside the glass, positioned in panel-body coordinates.
    @ViewBuilder
    private func panelContent(_ layout: DockLayout) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(model.cells.enumerated()), id: \.element.id) { index, cell in
                if index < layout.cellFrames.count {
                    let frame = layout.cellFrames[index]
                    RingView(provider: cell.id, state: cell.state, metrics: layout.metrics)
                        .scaleEffect(model.pressedIndex == index ? 0.94 : (model.hoveredIndex == index ? 1.08 : 1))
                        .animation(Motion.reduced(Motion.lift, reduceMotion: reduceMotion), value: model.hoveredIndex)
                        .animation(Motion.reduced(Motion.lift, reduceMotion: reduceMotion), value: model.pressedIndex)
                        .position(x: frame.midX, y: frame.midY)
                }
            }

            Image(systemName: "gearshape.fill")
                .font(.system(size: layout.metrics.gearSize, weight: .semibold))
                .foregroundStyle(model.gearHovered ? .primary : .secondary)
                .position(x: layout.gearCenter.x, y: layout.gearCenter.y)
        }
    }
}
