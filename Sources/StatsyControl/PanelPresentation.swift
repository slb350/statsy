import Foundation

/// What the controller knows about the panel process.
public enum PanelRunState: Sendable, CaseIterable {
    case running
    case stopped
    /// The panel bundle could not be found, so there is nothing to start.
    case missing
}

/// The menu bar item's appearance and its one action, derived from the state.
public struct PanelMenuPresentation: Sendable {
    public let toggleTitle: String
    public let isToggleEnabled: Bool
    public let symbolName: String
    public let accessibilityDescription: String

    public init(state: PanelRunState) {
        switch state {
        case .running:
            toggleTitle = "Stop Statsy"
            isToggleEnabled = true
            symbolName = "gauge.with.dots.needle.67percent"
            accessibilityDescription = "Statsy is running"
        case .stopped:
            toggleTitle = "Start Statsy"
            isToggleEnabled = true
            symbolName = "gauge.with.dots.needle.bottom.0percent"
            accessibilityDescription = "Statsy is stopped"
        case .missing:
            toggleTitle = "Statsy Not Found"
            isToggleEnabled = false
            symbolName = "gauge.with.dots.needle.bottom.0percent"
            accessibilityDescription = "Statsy is not installed"
        }
    }
}
