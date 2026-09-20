import StatsyKit
import SwiftUI

/// Drives the panel: one sampling loop, published on the main actor.
///
/// The provider behind it can change while the panel is running, because the
/// menu bar app can repoint it at another machine without restarting it. The
/// loop is torn down and rebuilt around the new provider rather than shared,
/// so a slow remote scrape can never be folded into the next target's rates.
@MainActor
@Observable
final class PanelModel {
    private(set) var snapshot = Snapshot.placeholder
    private(set) var target: Target

    private var loop: Task<Void, Never>?
    private let watcher = TargetWatcher()
    /// Whether the panel wants to be sampling, as distinct from whether a loop
    /// happens to be running: a target switch stops and restarts the loop
    /// without changing the answer.
    private var isSampling = false

    init(target: Target = TargetSelection().read()) {
        self.target = target
    }

    func start() {
        guard !isSampling else { return }
        isSampling = true
        // From the target this model believes it is showing, so a selection
        // made while the panel was parked is picked up here rather than lost.
        watcher.start(from: target) { [weak self] target in
            self?.switchTo(target)
        }
        startLoop()
    }

    func stop() {
        isSampling = false
        watcher.stop()
        stopLoop()
    }

    /// Repoints the panel at another machine.
    ///
    /// The placeholder goes back on screen for the moment it takes the new
    /// provider to connect. Leaving the previous host's numbers up would be
    /// showing one machine's readings under another machine's name.
    func switchTo(_ target: Target) {
        guard target != self.target else { return }
        self.target = target
        snapshot = .placeholder
        guard isSampling else { return }
        stopLoop()
        startLoop()
    }

    private func startLoop() {
        let provider = SnapshotProviderFactory.provider(for: target)
        loop = Task {
            await provider.start()
            while !Task.isCancelled {
                self.snapshot = await provider.sample()
                try? await Task.sleep(for: provider.refreshInterval)
            }
            await provider.stop()
        }
    }

    private func stopLoop() {
        loop?.cancel()
        loop = nil
    }
}
