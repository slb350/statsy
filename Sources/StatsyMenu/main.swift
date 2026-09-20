import AppKit

/// A menu bar item and nothing else: the panel it controls has no UI to quit
/// from, which matters most when the display it lives on has been unplugged.
@MainActor
final class MenuAppDelegate: NSObject, NSApplicationDelegate {
    private let controller = StatusItemController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller.install()
    }
}

let application = NSApplication.shared
let delegate = MenuAppDelegate()
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
