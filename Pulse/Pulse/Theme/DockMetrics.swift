import CoreGraphics

/// The dock's size setting (spec §18.3). One factor scales the slab and everything in it.
enum DockSize: String, Codable, Sendable, CaseIterable {
    case small, medium, large

    var scale: CGFloat {
        switch self {
        case .small: 0.8
        case .medium: 1.0
        case .large: 1.25
        }
    }
}

/// Every dock dimension, derived from one scale so the three sizes stay proportional.
/// Medium reproduces the v3 constants exactly. Widths that must be whole points are rounded;
/// strokes and radii are left fractional so rings stay concentric at every size.
struct DockMetrics: Equatable, Sendable {
    let scale: CGFloat

    init(scale: CGFloat) { self.scale = scale }
    init(size: DockSize) { self.init(scale: size.scale) }

    static let medium = DockMetrics(size: .medium)

    var panelWidth: CGFloat { (78 * scale).rounded() }
    var paddingTop: CGFloat { 18 * scale }
    var paddingBottom: CGFloat { 10 * scale }
    var cellGap: CGFloat { 22 * scale }
    var ringDiameter: CGFloat { 48 * scale }
    var ringStroke: CGFloat { 3.5 * scale }
    var wellRadius: CGFloat { 16.5 * scale }
    var glyphSize: CGFloat { 18 * scale }
    var labelGap: CGFloat { 7 * scale }
    var labelHeight: CGFloat { 20 * scale }
    var cellHeight: CGFloat { ringDiameter + labelGap + labelHeight }
    var gearRowHeight: CGFloat { 20 * scale }
    var gearSize: CGFloat { 13 * scale }
    var innerRadius: CGFloat { 22 * scale }
    var flareRadius: CGFloat { 20 * scale }
    var percentFontSize: CGFloat { 16 * scale }
    var smallLabelFontSize: CGFloat { 11 * scale }
}
