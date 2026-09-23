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

/// The value following `flag`, or nil when the flag is absent, is the last
/// argument, or is followed by another flag: a flag with no value is a usage
/// error, not an index out of range, and `--render --fixture out.prom` must not
/// write a PNG named `--fixture`.
func argument(after flag: String, in arguments: [String]) -> String? {
    guard let index = arguments.firstIndex(of: flag) else { return nil }
    let next = arguments.index(after: index)
    guard next < arguments.endIndex else { return nil }
    let value = arguments[next]
    guard !value.hasPrefix("--") else { return nil }
    return value
}

/// `--target <id>` overrides the recorded selection, which is how the render
/// mode looks at a host without changing what the menu has chosen.
let selected: Target
do {
    selected = try TargetRegistry.target(from: arguments, default: TargetSelection().read())
} catch {
    FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
    exit(1)
}

// A capture that a live panel would silently ignore is a usage error, not a
// no-op: without `--render`, `--fixture` means nothing at all.
if arguments.contains("--fixture"), !arguments.contains("--render") {
    FileHandle.standardError.write(Data(("--fixture requires --render\n").utf8))
    exit(1)
}

if arguments.contains("--render") {
    guard let path = argument(after: "--render", in: arguments) else {
        FileHandle.standardError.write(
            Data(("usage: Statsy --render <path> [--target <id> --fixture <path>]\n").utf8)
        )
        exit(1)
    }

    let snapshot: Snapshot
    // Key off presence, not value: a present `--fixture` with no value must
    // error, not fall through to a live scrape the user did not ask for.
    if arguments.contains("--fixture") {
        guard let fixturePath = argument(after: "--fixture", in: arguments) else {
            FileHandle.standardError.write(Data("--fixture needs a value\n".utf8))
            exit(1)
        }
        // A fixture renders the remote layout with no host attached: the
        // mapper is pure, so the same transformation that reads a live
        // scrape reads a captured one. A priming scrape then a second one
        // 2 s later, the remote refresh interval, leave the cores idle,
        // which is fine — this mode checks layout.
        guard let remote = selected.remote,
              let text = try? String(contentsOfFile: fixturePath, encoding: .utf8)
        else {
            FileHandle.standardError.write(
                Data(("--fixture needs a remote --target and a readable file\n").utf8)
            )
            exit(1)
        }
        var mapper = RemoteMapper(target: remote)
        let samples = PrometheusText.parse(text, wanted: mapper.wants)
        // The capture must belong to the host it is named after: a scrape of
        // one host rendered under another's target would apply that target's
        // decisions (the unified-memory fold, the volumes) to the wrong
        // numbers — a confident wrong answer, so refuse it.
        guard samples.contains(where: {
            $0.name.hasPrefix(remote.collectorPrefix)
                && $0.labels["asset_host"] == remote.hostName
        }) else {
            FileHandle.standardError.write(
                Data(("fixture does not carry \(remote.hostName)'s collector metrics\n").utf8)
            )
            exit(1)
        }
        let metrics = MetricSet(samples)
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
