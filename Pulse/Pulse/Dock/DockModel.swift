import Observation
import PulseCore

struct DockCell: Identifiable, Equatable {
    let id: ProviderID
    let state: RingState
}

/// Everything `DockView` draws. Updated by `DockWindowController.render()`.
@MainActor
@Observable
final class DockModel {
    var layout = DockLayout(cellCount: 0, edge: .right)
    var style: DockStyle = .notch
    var cells: [DockCell] = []
    var hoveredIndex: Int?
    /// The cell being held down, fed from `DockInteractionView`: the SwiftUI tree gets no
    /// events of its own, so the press dip is state rather than a gesture.
    var pressedIndex: Int?
    var gearHovered = false
}
