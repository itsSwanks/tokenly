import Testing
import SwiftUI
@testable import Pulse

@Suite struct DockShapeTests {
    let rect = CGRect(x: 0, y: 0, width: 78, height: 400)

    @Test func rightEdgeShapeIsFlushOnTheRightAndRoundedOnTheLeft() {
        let path = DockShape(edge: .right).path(in: rect)
        let box = path.boundingRect
        #expect(box.maxX == 78)
        #expect(box.minX == 0)
        // Flares extend 20 pt above and below the panel body along the screen edge.
        #expect(box.minY == -20)
        #expect(box.maxY == 420)
        // A point just inside the top-left corner is outside the rounded corner…
        #expect(path.contains(CGPoint(x: 2, y: 2)) == false)
        // …and a point on the screen-edge side at the same height is inside.
        #expect(path.contains(CGPoint(x: 76, y: 2)) == true)
        // The flare region: just above the panel, touching the edge, is filled.
        #expect(path.contains(CGPoint(x: 77, y: -10)) == true)
        // The concave cutout: 22 pt in from the edge and 14 pt above the panel is empty.
        #expect(path.contains(CGPoint(x: 56, y: -14)) == false)
    }

    /// The Glass style is a flare-less slab: its bounding box is exactly the panel rect, and
    /// the region a flare would have filled — above the panel, on the screen edge — is empty.
    @Test func glassStyleHasNoFlares() {
        let path = DockShape(edge: .right, style: .glass).path(in: rect)
        let box = path.boundingRect
        #expect(box.minX == 0)
        #expect(box.maxX == 78)
        #expect(box.minY == 0)
        #expect(box.maxY == 400)
        #expect(path.contains(CGPoint(x: 77, y: -10)) == false)   // no flare above the panel
        #expect(path.contains(CGPoint(x: 77, y: 410)) == false)   // none below either
        // Same inward radius as the notch: the top-left corner is still rounded away…
        #expect(path.contains(CGPoint(x: 2, y: 2)) == false)
        // …while the screen-edge side stays flat and filled right to the corner.
        #expect(path.contains(CGPoint(x: 76, y: 2)) == true)
        #expect(path.contains(CGPoint(x: 39, y: 200)) == true)
    }

    @Test func glassMirrorsOnTheLeftEdge() {
        let right = DockShape(edge: .right, style: .glass).path(in: rect)
        let left = DockShape(edge: .left, style: .glass).path(in: rect)
        #expect(left.boundingRect == right.boundingRect)
        for (x, y) in [(2.0, 2.0), (76.0, 2.0), (39.0, 200.0), (2.0, 398.0)] {
            #expect(right.contains(CGPoint(x: x, y: y)) == left.contains(CGPoint(x: 78 - x, y: y)))
        }
    }

    /// A handle-sized slab (9 × 69, three dots) at the 6 pt handle radius. Only one vertical
    /// side is rounded, so the radius is bounded by the full width and by half the height —
    /// 6 fits. Clamping against half the *width* too would silently flatten it to 4.5.
    ///
    /// The radius is read off `contains`: a larger radius removes *more* of the corner square,
    /// and the probes below sit in the lune between the two arcs — inside the 4.5 pt corner,
    /// outside the 6 pt one — so each reads `true` at 4.5 and `false` at 6. (`boundingRect`
    /// discriminates too, but only by a rounding crumb: the 4.5 pt arcs miss their tangents by
    /// ~8e-6 pt and the box comes out a hair taller than `rect`.)
    @Test func handleSizedSlabKeepsItsFullRadius() {
        let handle = CGRect(x: 0, y: 0, width: 9, height: 69)
        let path = EdgeSlabPath.path(in: handle, radius: 6, roundedSide: .left)
        #expect(path.boundingRect == handle)
        // Top inward corner: the 6 pt arc is centred at (6, 6), a 4.5 pt one would be at
        // (4.5, 4.5). (1.5, 1.5) is 6.36 pt from the first (outside it) and 4.24 pt from the
        // second (inside it).
        #expect(path.contains(CGPoint(x: 1.5, y: 1.5)) == false)
        // Bottom inward corner, centres (6, 63) and (4.5, 64.5): the same two distances.
        #expect(path.contains(CGPoint(x: 1.5, y: 67.5)) == false)
        // Between the corners the slab is still full width, and the screen-edge side stays
        // square right up to the top.
        #expect(path.contains(CGPoint(x: 0.5, y: 34.5)) == true)
        #expect(path.contains(CGPoint(x: 8.5, y: 0.5)) == true)
        // Mirrored: the same lune probe against a right-rounded slab (arc centre (3, 6)).
        let mirrored = EdgeSlabPath.path(in: handle, radius: 6, roundedSide: .right)
        #expect(mirrored.contains(CGPoint(x: 7.5, y: 1.5)) == false)
    }

    /// `DockShape.contains(windowPoint:layout:style:)` is what `DockInteractionView.hitTest`
    /// asks, in the dock window's own top-left-origin coordinates: the flare margin is 20 pt
    /// tall at each end of the window and mostly empty, and clicks landing there have to fall
    /// through to whatever is behind the panel.
    @Test func windowHitTestingExcludesTheTransparentFlareCorners() {
        let layout = DockLayout(cellCount: 3, edge: .right)
        let inset = DockLayout.flareInset                        // 20
        let bottom = layout.windowSize.height                    // 357 for three cells

        // Inside the body, over a ring: hit.
        #expect(DockShape.contains(windowPoint: CGPoint(x: 39, y: inset + 40), layout: layout, style: .notch))
        // Top-left of the window — the flare's concave side, transparent in the Notch style.
        #expect(DockShape.contains(windowPoint: CGPoint(x: 4, y: 4), layout: layout, style: .notch) == false)
        // 6 pt above the panel body and hard against the screen edge: that is where the flare
        // fills. (Its arc is centred at (58, 0) with r = 20, so at y = 14 it starts at x ≈ 72.3.)
        #expect(DockShape.contains(windowPoint: CGPoint(x: 77, y: inset - 6), layout: layout, style: .notch))
        // …while at the same height, further in, the concave cutout is empty.
        #expect(DockShape.contains(windowPoint: CGPoint(x: 60, y: inset - 6), layout: layout, style: .notch) == false)
        // The lower flare behaves the same way.
        #expect(DockShape.contains(windowPoint: CGPoint(x: 4, y: bottom - 4), layout: layout, style: .notch) == false)
        #expect(DockShape.contains(windowPoint: CGPoint(x: 77, y: bottom - inset + 6), layout: layout, style: .notch))
        #expect(DockShape.contains(windowPoint: CGPoint(x: 60, y: bottom - inset + 6), layout: layout, style: .notch) == false)
        // And the body's own rounded inward corner is transparent too.
        #expect(DockShape.contains(windowPoint: CGPoint(x: 2, y: inset + 2), layout: layout, style: .notch) == false)
    }

    /// The Glass style draws no flares at all, so the whole margin — screen-edge side included —
    /// is click-through.
    @Test func glassWindowHitTestingExcludesTheWholeFlareMargin() {
        let layout = DockLayout(cellCount: 3, edge: .right)
        let bottom = layout.windowSize.height
        #expect(DockShape.contains(windowPoint: CGPoint(x: 77, y: 4), layout: layout, style: .glass) == false)
        #expect(DockShape.contains(windowPoint: CGPoint(x: 77, y: bottom - 4), layout: layout, style: .glass) == false)
        #expect(DockShape.contains(windowPoint: CGPoint(x: 39, y: DockLayout.flareInset + 40), layout: layout, style: .glass))
    }

    /// Mirrored on the left edge: the corner that fills is the one against that screen edge.
    @Test func windowHitTestingMirrorsOnTheLeftEdge() {
        let layout = DockLayout(cellCount: 3, edge: .left)
        let y = DockLayout.flareInset - 6
        #expect(DockShape.contains(windowPoint: CGPoint(x: 1, y: y), layout: layout, style: .notch))
        #expect(DockShape.contains(windowPoint: CGPoint(x: 18, y: y), layout: layout, style: .notch) == false)
        #expect(DockShape.contains(windowPoint: CGPoint(x: 74, y: 4), layout: layout, style: .notch) == false)
    }

    @Test func leftEdgeShapeIsTheMirrorImage() {
        let right = DockShape(edge: .right).path(in: rect)
        let left = DockShape(edge: .left).path(in: rect)
        for (x, y) in [(2.0, 2.0), (76.0, 2.0), (77.0, -10.0), (56.0, -14.0), (39.0, 200.0)] {
            #expect(right.contains(CGPoint(x: x, y: y)) == left.contains(CGPoint(x: 78 - x, y: y)))
        }
    }
}
