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
    var gearHovered = false
}
