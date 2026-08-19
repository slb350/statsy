import StatsyKit
import SwiftUI

/// Drives the panel: one sampling loop, published on the main actor.
@MainActor
@Observable
final class PanelModel {
    private(set) var snapshot = Snapshot.placeholder

    private let engine = MetricsEngine()
    private var loop: Task<Void, Never>?

    /// Refresh cadence. One second is enough for a glanceable panel and keeps
    /// the app's own cost far below what it is measuring.
    private let interval: Duration

    init(interval: Duration = .seconds(1)) {
        self.interval = interval
    }

    func start() {
        guard loop == nil else { return }
        loop = Task { [engine, interval] in
            await engine.start()
            while !Task.isCancelled {
                let next = await engine.sample()
                self.snapshot = next
                try? await Task.sleep(for: interval)
            }
            await engine.stop()
        }
    }

    func stop() {
        loop?.cancel()
        loop = nil
    }
}
