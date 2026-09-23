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

    let snapshot: Snapshot
    if let fixtureIndex = arguments.firstIndex(of: "--fixture") {
        // A fixture renders the remote layout with no host attached: the
        // mapper is pure, so the same transformation that reads a live
        // scrape reads a captured one. Two identical scrapes a second apart
        // leave the cores idle, which is fine — this mode checks layout.
        let fixturePath = arguments[arguments.index(after: fixtureIndex)]
        guard let remote = selected.remote,
              let text = try? String(contentsOfFile: fixturePath, encoding: .utf8)
        else {
            FileHandle.standardError.write(
                Data(("--fixture needs a remote --target and a readable file\n").utf8)
            )
            exit(1)
        }
        var mapper = RemoteMapper(target: remote)
        let metrics = MetricSet(text: text, wanted: mapper.wants)
        let now = Date()
        _ = mapper.snapshot(from: metrics, now: now, link: LinkStatus(state: .live))
        snapshot = mapper.snapshot(
            from: metrics, now: now.addingTimeInterval(2), link: LinkStatus(state: .live)
        )
    } else {
        let provider = SnapshotProviderFactory.provider(for: selected)
        snapshot = await provider.primedSample()
        await provider.stop()
    }
    try PanelRender.write(snapshot: snapshot, to: path)
    print("wrote \(path)")
    exit(0)
}

let application = NSApplication.shared
let delegate = AppDelegate(target: selected)
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
