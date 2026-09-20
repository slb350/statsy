import AppKit
import Foundation
import StatsyKit

/// A panel, not an app: no Dock icon, no menu bar presence.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model: PanelModel
    private lazy var panel = PanelWindow(model: model)

    init(target: Target) {
        model = PanelModel(target: target)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Sampling starts and stops with the window, so `PanelWindow` drives
        // both: neither should run while the panel's display is absent.
        panel.show()
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.stop()
    }
}

let arguments = CommandLine.arguments

/// `--target <id>` overrides the recorded selection, which is how the render
/// mode looks at a host without changing what the menu has chosen.
let selected: Target
do {
    selected = try TargetRegistry.target(from: arguments, default: TargetSelection().read())
} catch {
    FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
    exit(1)
}

if let renderIndex = arguments.firstIndex(of: "--render") {
    let path = arguments[arguments.index(after: renderIndex)]
    let provider = SnapshotProviderFactory.provider(for: selected)
    let snapshot = await provider.primedSample()
    await provider.stop()
    try PanelRender.write(snapshot: snapshot, to: path)
    print("wrote \(path)")
    exit(0)
}

let application = NSApplication.shared
let delegate = AppDelegate(target: selected)
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
