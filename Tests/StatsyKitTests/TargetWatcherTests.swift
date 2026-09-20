import Foundation
import Testing
@testable import StatsyKit

/// The watcher is the one piece of the switching path with no other cover.
///
/// It is worth a real filesystem test rather than a stub: the bug it exists to
/// avoid is watching the selection file directly, which works once and then
/// silently never fires again, because an atomic write replaces the inode.
@Suite("Target watcher", .serialized)
struct TargetWatcherTests {
    /// Collects callbacks off the watcher's queue.
    private final class Box: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [Target] = []

        func append(_ target: Target) {
            lock.withLock { values.append(target) }
        }

        var current: [Target] {
            lock.withLock { values }
        }
    }

    private func temporaryDirectory() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("statsy-watch-\(UUID().uuidString)", isDirectory: true)
    }

    /// Waits for a condition rather than sleeping a fixed span, so a slow
    /// machine does not fail a test that a fast one passes.
    private func wait(
        upTo seconds: TimeInterval = 5, until condition: @escaping () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(25))
        }
    }

    @Test("reports a selection written after it started")
    func noticesChange() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let selection = TargetSelection(url: directory.appendingPathComponent("target"))
        let seen = Box()

        let watcher = TargetWatcher(selection: selection)
        watcher.start(from: TargetRegistry.local) { target in seen.append(target) }
        defer { watcher.stop() }

        try selection.write(TargetRegistry.homelabAI1)
        await wait { !seen.current.isEmpty }
        #expect(seen.current.map(\.id) == ["homelab-ai-1"])
    }

    @Test("keeps reporting after the file has been replaced once")
    func survivesAtomicReplacement() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let selection = TargetSelection(url: directory.appendingPathComponent("target"))
        let seen = Box()

        let watcher = TargetWatcher(selection: selection)
        watcher.start(from: TargetRegistry.local) { target in seen.append(target) }
        defer { watcher.stop() }

        try selection.write(TargetRegistry.homelabAI1)
        await wait { seen.current.count == 1 }
        // The second write is the one a file-descriptor watch would miss.
        try selection.write(TargetRegistry.local)
        await wait { seen.current.count == 2 }

        #expect(seen.current.map(\.id) == ["homelab-ai-1", "local"])
    }


    /// Undock, change the target from the menu, redock. The panel stops
    /// sampling while its display is away, so nothing is watching when the
    /// selection changes; coming back it must notice rather than resume on the
    /// machine it was showing before.
    @Test("reports a change made while it was stopped")
    func noticesChangeMadeWhileStopped() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let selection = TargetSelection(url: directory.appendingPathComponent("target"))
        let seen = Box()

        try selection.write(TargetRegistry.homelabAI1)

        let watcher = TargetWatcher(selection: selection)
        // The caller still believes it is showing the local machine.
        watcher.start(from: TargetRegistry.local) { target in seen.append(target) }
        defer { watcher.stop() }

        await wait { !seen.current.isEmpty }
        #expect(seen.current.map(\.id) == ["homelab-ai-1"])
    }

    @Test("stays quiet while the file agrees with what the caller is showing")
    func ignoresRedundantWrites() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let selection = TargetSelection(url: directory.appendingPathComponent("target"))
        let seen = Box()

        try selection.write(TargetRegistry.homelabAI1)
        let watcher = TargetWatcher(selection: selection)
        watcher.start(from: TargetRegistry.homelabAI1) { target in seen.append(target) }
        defer { watcher.stop() }

        // Neither starting in agreement nor rewriting the same value may tear
        // down a healthy provider to rebuild an identical one.
        try selection.write(TargetRegistry.homelabAI1)
        try await Task.sleep(for: .milliseconds(400))
        #expect(seen.current.isEmpty)
    }

    @Test("stops reporting once stopped")
    func stops() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let selection = TargetSelection(url: directory.appendingPathComponent("target"))
        let seen = Box()

        let watcher = TargetWatcher(selection: selection)
        watcher.start(from: TargetRegistry.local) { target in seen.append(target) }
        watcher.stop()

        try selection.write(TargetRegistry.homelabAI1)
        try await Task.sleep(for: .milliseconds(400))
        #expect(seen.current.isEmpty)
    }
}
