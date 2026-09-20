import AppKit
import StatsyControl

/// Starts and stops the panel, and reports whether it is up.
///
/// The panel is a separate process with no UI to quit from, so everything here
/// goes through Launch Services and `NSRunningApplication` rather than through
/// anything the panel itself provides.
@MainActor
final class PanelProcess {
    /// How long a polite terminate gets before the panel is killed outright.
    /// The point of this app is that the panel can always be got rid of.
    private static let terminationGrace = Duration.seconds(2)
    private static let terminationPoll = Duration.milliseconds(100)

    private let locator = PanelLocator()
    private var cachedBundleURL: URL?

    /// Called whenever the panel starts or stops, by this app or otherwise.
    var onStateChange: (() -> Void)?

    /// The panel bundle this controller drives, or nil if it is not installed.
    ///
    /// Cached, because `state` is read on every menu open and on every launch
    /// or quit anywhere on the system. Re-resolved only once the cached bundle
    /// stops existing, so moving or installing the panel is still picked up.
    var bundleURL: URL? {
        if let cachedBundleURL, FileManager.default.fileExists(atPath: cachedBundleURL.path) {
            return cachedBundleURL
        }
        cachedBundleURL = locator.locate(controllerBundle: Bundle.main.bundleURL)
        return cachedBundleURL
    }

    var state: PanelRunState {
        // Asked in this order so a running panel can always be stopped, even if
        // its bundle has been moved or deleted underneath it.
        if !runningPanels.isEmpty { return .running }
        return bundleURL == nil ? .missing : .stopped
    }

    private var runningPanels: [NSRunningApplication] {
        NSRunningApplication.runningApplications(
            withBundleIdentifier: PanelLocator.panelBundleIdentifier
        )
    }

    /// Watches for the panel starting or stopping outside this app — launched
    /// from Finder, or crashed — so the menu never shows a stale state.
    ///
    /// The observers are never removed: this object lives as long as the
    /// process does.
    func observeWorkspace() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
        ] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let application = note.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication
                guard application?.bundleIdentifier == PanelLocator.panelBundleIdentifier
                else { return }
                MainActor.assumeIsolated { self?.onStateChange?() }
            }
        }
    }

    func start() async throws {
        guard let bundleURL else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        // The panel is a background panel: opening it must not steal focus or
        // clutter the recent items menu.
        configuration.activates = false
        configuration.addsToRecentItems = false
        try await NSWorkspace.shared.openApplication(at: bundleURL, configuration: configuration)
    }

    func stop() async {
        let panels = runningPanels
        guard !panels.isEmpty else { return }
        for panel in panels {
            panel.terminate()
        }

        // Polled rather than slept out: the panel has nothing to save and is
        // normally gone in well under the grace period.
        var waited = Duration.zero
        while waited < Self.terminationGrace {
            if panels.allSatisfy(\.isTerminated) { return }
            try? await Task.sleep(for: Self.terminationPoll)
            waited += Self.terminationPoll
        }
        for panel in panels where !panel.isTerminated {
            panel.forceTerminate()
        }
    }
}
