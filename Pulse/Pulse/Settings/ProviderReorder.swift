import Foundation

/// The provider rows' drag-to-reorder, minus the gesture (spec §19.3): every decision the drag
/// makes lives here, pure, so the geometry is testable and `SettingsView` only wires fingers to
/// answers. The gesture itself is scoped to the row's grip — which is what makes this drag safe
/// where the old `List.onMove` attempt was not: a `List` turned *any* row click into a potential
/// drag and swallowed taps meant for the switches; a grip-only `DragGesture` cannot.
enum ProviderReorder {
    /// Where the dragged row would land if dropped now: its start slot plus however many whole
    /// rows the finger has travelled, clamped into the list.
    static func proposedIndex(from: Int, translation: CGFloat, rowHeight: CGFloat, count: Int) -> Int {
        guard count > 0, rowHeight > 0 else { return from }
        let moved = from + Int((translation / rowHeight).rounded())
        return min(max(moved, 0), count - 1)
    }

    /// How far a *non-dragged* row steps aside: one row's height, and only for rows sitting
    /// between the drag's origin and its proposed slot. The dragged row is the caller's business —
    /// it follows the live translation instead.
    static func rowOffset(index: Int, draggedFrom from: Int, proposed: Int, rowHeight: CGFloat) -> CGFloat {
        if index == from { return 0 }
        if from < index, index <= proposed { return -rowHeight }
        if proposed <= index, index < from { return rowHeight }
        return 0
    }

    /// The committed order: one element moved, everything else stable. Indices that don't exist
    /// (a drop after the orders changed under the drag) leave the order untouched.
    static func reordered<T>(_ order: [T], from: Int, to: Int) -> [T] {
        guard order.indices.contains(from), order.indices.contains(to), from != to else { return order }
        var result = order
        result.insert(result.remove(at: from), at: to)
        return result
    }
}
