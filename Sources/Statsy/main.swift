import AppKit

/// A panel, not an app: no Dock icon, no menu bar presence.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = PanelModel()
    private lazy var panel = PanelWindow(model: model)

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.start()
        panel.show()
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.stop()
    }
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
