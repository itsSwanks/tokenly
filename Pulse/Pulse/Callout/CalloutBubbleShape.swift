import SwiftUI

/// Card and tail as one path (spec §18.2), so the glass — and its rim light — wraps the tail.
/// `tailY` is the tail's centre measured from the top of `rect`.
struct CalloutBubbleShape: Shape {
    let edge: ScreenEdge
    var tailY: CGFloat
    var animatableData: CGFloat { get { tailY } set { tailY = newValue } }

    func path(in rect: CGRect) -> Path {
        let tail = Metrics.tailLength, half = Metrics.tailHalfHeight
        let card = edge == .right
            ? CGRect(x: rect.minX, y: rect.minY, width: rect.width - tail, height: rect.height)
            : CGRect(x: rect.minX + tail, y: rect.minY, width: rect.width - tail, height: rect.height)
        var p = RoundedRectangle(cornerRadius: Metrics.calloutRadius, style: .continuous).path(in: card)
        let y = min(max(tailY, card.minY + Metrics.calloutRadius + half), card.maxY - Metrics.calloutRadius - half)
        var t = Path()
        if edge == .right {
            t.move(to: CGPoint(x: card.maxX - 0.5, y: y - half))
            t.addLine(to: CGPoint(x: rect.maxX, y: y))
            t.addLine(to: CGPoint(x: card.maxX - 0.5, y: y + half))
        } else {
            // Bottom vertex first — the mirror of the right-edge order, so the tail winds the same
            // way the rounded rect does. Wound the other way it is a *negative* subpath: the
            // non-zero fill rule both CG and SwiftUI use would cancel the 0.5 pt weld to zero and
            // slit the tail off the card, and `Path.contains` would report the tail as empty.
            t.move(to: CGPoint(x: card.minX + 0.5, y: y + half))
            t.addLine(to: CGPoint(x: rect.minX, y: y))
            t.addLine(to: CGPoint(x: card.minX + 0.5, y: y - half))
        }
        t.closeSubpath()
        p.addPath(t)
        return p
    }
}
