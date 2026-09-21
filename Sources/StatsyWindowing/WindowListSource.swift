import AppKit

/// Reads the window server's on-screen window list.
///
/// Acquisition only, in the shape the rest of the codebase uses: the policy it
/// feeds is `ScreenOccupancy`, which is pure and carries the tests.
public enum WindowListSource {
    /// Every window currently on screen, in window-server coordinates.
    ///
    /// Desktop elements are excluded because the wallpaper, the backstop and
    /// the desktop icon layer all sit at large negative levels and cover the
    /// panel's display in full, so they are noise no policy will ever want.
    ///
    /// The list is walked as `NSDictionary` rather than bridged to
    /// `[[String: Any]]`. That bridge deep-copies all ~60 entries into Swift
    /// dictionaries, which measured as a quarter of the cost of the poll and is
    /// then entirely discarded.
    public static func onScreenWindows() -> [WindowReport] {
        guard let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as NSArray? else { return [] }

        var reports: [WindowReport] = []
        reports.reserveCapacity(list.count)
        for case let entry as NSDictionary in list {
            guard let layer = entry[kCGWindowLayer as String] as? NSNumber,
                  let bounds = entry[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds)
            else { continue }
            reports.append(WindowReport(layer: layer.intValue, frame: frame))
        }
        return reports
    }

    /// A display's frame in window-server coordinates.
    ///
    /// `NSScreen.frame` is in AppKit's space, with the origin at the bottom-left
    /// of the primary display and y increasing upward; window bounds are in the
    /// window server's, with the origin at the top-left and y increasing
    /// downward. `CGDisplayBounds` reports the same rect already in the window
    /// server's space, so there is no conversion to get wrong.
    public static func bounds(of screen: NSScreen) -> CGRect? {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        else { return nil }
        return CGDisplayBounds(CGDirectDisplayID(number.uint32Value))
    }
}
