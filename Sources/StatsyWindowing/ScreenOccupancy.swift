import AppKit

/// One on-screen window, as the window server reports it.
public struct WindowReport: Sendable, Equatable {
    public let layer: Int
    /// In window-server coordinates: origin at the top-left of the primary
    /// display, y increasing downward. `WindowListSource.bounds(of:)` returns a
    /// display's frame in the same space.
    public let frame: CGRect

    public init(layer: Int, frame: CGRect) {
        self.layer = layer
        self.frame = frame
    }
}

/// Chooses the panel's window level so that an alert opening on the panel's
/// display is not hidden underneath it.
///
/// The panel rests above the menu bar, which also puts it above every modal
/// alert. An alert that opens on its display is then invisible and unreachable,
/// and because it is modal its application stops responding with nothing on
/// screen to explain why. That is the failure this exists to prevent.
public enum ScreenOccupancy {
    /// Above `.mainMenu`, so the menu bar does not draw over the header on the
    /// display the panel owns.
    public static let restingLevel: NSWindow.Level = .statusBar

    /// Below `.modalPanel`, so the obstruction draws over the panel instead.
    public static let duckedLevel: NSWindow.Level = .normal

    /// The level the panel should be at, given what is on its display now.
    public static func level(given windows: [WindowReport], on screen: CGRect) -> NSWindow.Level {
        isObstructed(by: windows, on: screen) ? duckedLevel : restingLevel
    }

    /// True when a window on the panel's display would be hidden underneath it.
    ///
    /// The band is everything above `.normal` up to and including `.modalPanel`,
    /// which is the range a transient prompt occupies. Ordinary windows fall
    /// below it because sitting above them is the panel's whole purpose.
    /// Everything from `.utilityWindow` (19) up is above it because that range
    /// is furniture rather than a prompt, and furniture never goes away: the
    /// Dock sits at 20 and follows the pointer onto this display, the menu bar
    /// at 24 is drawn on every display while "Displays have separate Spaces" is
    /// on, and the status items share the panel's own 25. Ducking for any of
    /// those would retire the panel for good.
    static func isObstructed(by windows: [WindowReport], on screen: CGRect) -> Bool {
        let floor = NSWindow.Level.normal.rawValue
        let ceiling = NSWindow.Level.modalPanel.rawValue
        return windows.contains { window in
            window.layer > floor
                && window.layer <= ceiling
                && window.frame.intersects(screen)
        }
    }
}
