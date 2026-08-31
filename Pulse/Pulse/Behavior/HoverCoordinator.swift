import Foundation

/// Decides when the callout shows, follows, pins and hides. Pure: the caller runs
/// the timers and feeds `timeout(id:)` back in, so every path is unit-testable.
struct HoverCoordinator: Equatable {
    enum Event: Equatable {
        case hoverCell(Int?)      // nil = cursor left every ring (still over the dock or gone)
        case enterCallout
        case leaveCallout
        case clickCell(Int)
        case clickAway
        case timeout(id: Int)
        case forceHide            // dock collapsing, provider disabled, settings opened
    }

    enum Effect: Equatable {
        case show(Int)
        case move(Int)
        case hide
        case scheduleTimeout(after: TimeInterval, id: Int)
        case cancelTimeout(id: Int)
    }

    private(set) var visibleIndex: Int?
    private(set) var pinnedIndex: Int?
    private var pendingTimeout: Int?
    private var nextTimeoutID = 0

    mutating func handle(_ event: Event) -> [Effect] {
        switch event {
        case .hoverCell(let index?):
            var effects = cancelPending()
            guard pinnedIndex == nil else { return effects }
            if visibleIndex == nil { effects.append(.show(index)) }
            else if visibleIndex != index { effects.append(.move(index)) }
            visibleIndex = index
            return effects

        case .hoverCell(nil), .leaveCallout:
            guard pinnedIndex == nil, visibleIndex != nil, pendingTimeout == nil else { return [] }
            nextTimeoutID += 1
            pendingTimeout = nextTimeoutID
            return [.scheduleTimeout(after: Motion.hoverGrace, id: nextTimeoutID)]

        case .enterCallout:
            return cancelPending()

        case .timeout(let id):
            guard id == pendingTimeout else { return [] }
            pendingTimeout = nil
            visibleIndex = nil
            return [.hide]

        case .clickCell(let index):
            var effects = cancelPending()
            if pinnedIndex == index {
                pinnedIndex = nil                       // re-click unpins; stays visible while hovered
                return effects
            }
            pinnedIndex = index
            if visibleIndex == nil { effects.append(.show(index)) }
            else if visibleIndex != index { effects.append(.move(index)) }
            visibleIndex = index
            return effects

        case .clickAway:
            guard pinnedIndex != nil else { return [] }
            pinnedIndex = nil
            visibleIndex = nil
            return cancelPending() + [.hide]

        case .forceHide:
            let wasVisible = visibleIndex != nil
            pinnedIndex = nil
            visibleIndex = nil
            return cancelPending() + (wasVisible ? [.hide] : [])
        }
    }

    private mutating func cancelPending() -> [Effect] {
        guard let id = pendingTimeout else { return [] }
        pendingTimeout = nil
        return [.cancelTimeout(id: id)]
    }
}
