import AppKit
import Testing
@testable import StatsyWindowing

/// The panel's display in window-server coordinates, as `CGDisplayBounds`
/// reports it: a 1280x480 strip sitting below the 2560x1440 primary.
private let strip = CGRect(x: 1280, y: 1440, width: 1280, height: 480)

private func report(layer: NSWindow.Level, _ frame: CGRect) -> WindowReport {
    WindowReport(layer: layer.rawValue, frame: frame)
}

/// For the levels AppKit does not name. `NSWindow.Level` has no `.utility`, and
/// CoreGraphics is the authoritative spelling for both.
private func report(cgLevel key: CGWindowLevelKey, _ frame: CGRect) -> WindowReport {
    WindowReport(layer: Int(CGWindowLevelForKey(key)), frame: frame)
}

/// A rect wholly inside the strip, the size of a standard alert.
private let onStrip = CGRect(x: 1790, y: 1524, width: 260, height: 234)

@Suite("Screen occupancy")
struct ScreenOccupancyTests {
    @Test("an empty window list leaves the panel in place")
    func emptyListIsClear() {
        #expect(ScreenOccupancy.isObstructed(by: [], on: strip) == false)
    }

    @Test("a modal alert on the panel's display obstructs it")
    func modalAlertObstructs() {
        // Measured: a running app-modal NSAlert reports layer 8 to the window
        // server, though NSAlert.window.level reads 0 before it is displayed.
        #expect(ScreenOccupancy.isObstructed(by: [report(layer: .modalPanel, onStrip)], on: strip))
    }

    @Test("a floating panel on the display obstructs it")
    func floatingPanelObstructs() {
        #expect(ScreenOccupancy.isObstructed(by: [report(layer: .floating, onStrip)], on: strip))
    }

    @Test("the Dock never ducks the panel, even parked on its display")
    func dockDoesNotObstruct() {
        // The Dock sits at level 20 and, with "Displays have separate Spaces"
        // on, follows the pointer onto whichever display is active. A band that
        // admitted it would duck the panel the first time the pointer crossed
        // over and never restore it.
        let dock = report(cgLevel: .dockWindow, CGRect(x: 1280, y: 1440, width: 1280, height: 480))
        #expect(ScreenOccupancy.isObstructed(by: [dock], on: strip) == false)
    }

    @Test("a utility window does not duck the panel")
    func utilityWindowDoesNotObstruct() {
        // Level 19. An inspector or palette parked on the display is furniture
        // that stays put, not a prompt waiting to be answered.
        let utility = report(cgLevel: .utilityWindow, onStrip)
        #expect(ScreenOccupancy.isObstructed(by: [utility], on: strip) == false)
    }

    @Test("the menu bar is permanent furniture and never ducks the panel")
    func menuBarDoesNotObstruct() {
        let menuBar = report(layer: .mainMenu, CGRect(x: 1280, y: 1440, width: 1280, height: 30))
        #expect(ScreenOccupancy.isObstructed(by: [menuBar], on: strip) == false)
    }

    @Test("menu bar extras sit at the panel's own level and never duck it")
    func menuExtrasDoNotObstruct() {
        // Control Center hosts every status item at .statusBar, the same level
        // as the panel, so they are already resolved by ordering.
        let extra = report(layer: .statusBar, CGRect(x: 1936, y: 1440, width: 28, height: 30))
        #expect(ScreenOccupancy.isObstructed(by: [extra], on: strip) == false)
    }

    @Test("an ordinary application window does not duck the panel")
    func ordinaryWindowDoesNotObstruct() {
        // The whole point of the panel is to sit above ordinary windows. A
        // window dragged onto the strip must not make it vanish.
        #expect(ScreenOccupancy.isObstructed(by: [report(layer: .normal, strip)], on: strip) == false)
    }

    @Test("desktop and wallpaper windows do not duck the panel")
    func desktopLayersDoNotObstruct() {
        let wallpaper = WindowReport(layer: -2147483624, frame: strip)
        #expect(ScreenOccupancy.isObstructed(by: [wallpaper], on: strip) == false)
    }

    @Test("an alert on another display does not duck the panel")
    func alertElsewhereDoesNotObstruct() {
        let alert = report(layer: .modalPanel, CGRect(x: 1150, y: 332, width: 260, height: 202))
        #expect(ScreenOccupancy.isObstructed(by: [alert], on: strip) == false)
    }

    @Test("a window merely touching the display edge does not duck the panel")
    func edgeContactDoesNotObstruct() {
        let above = report(layer: .modalPanel, CGRect(x: 1280, y: 1240, width: 300, height: 200))
        #expect(above.frame.maxY == strip.minY)
        #expect(ScreenOccupancy.isObstructed(by: [above], on: strip) == false)
    }
}

@Suite("Panel level")
struct PanelLevelTests {
    @Test("rests above the menu bar so the header stays legible")
    func restsAboveMenuBar() {
        #expect(ScreenOccupancy.restingLevel.rawValue > NSWindow.Level.mainMenu.rawValue)
        #expect(ScreenOccupancy.level(given: [], on: strip) == ScreenOccupancy.restingLevel)
    }

    @Test("ducks below a modal alert so it can be seen and answered")
    func ducksBelowModalAlert() {
        #expect(ScreenOccupancy.duckedLevel.rawValue < NSWindow.Level.modalPanel.rawValue)
        let level = ScreenOccupancy.level(given: [report(layer: .modalPanel, onStrip)], on: strip)
        #expect(level == ScreenOccupancy.duckedLevel)
    }

    @Test("no single static level satisfies both, which is why this is dynamic")
    func noStaticLevelWorks() {
        // Pins the reason the mechanism exists: clearing the menu bar and
        // yielding to an alert are mutually exclusive as fixed levels.
        #expect(NSWindow.Level.mainMenu.rawValue > NSWindow.Level.modalPanel.rawValue)
    }
}
