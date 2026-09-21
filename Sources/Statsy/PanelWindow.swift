import AppKit
import StatsyKit
import StatsyWindowing
import SwiftUI

/// Places the panel on the small secondary display and keeps it there.
@MainActor
final class PanelWindow {
    private var window: NSWindow?
    /// Unsafe-nonisolated so `deinit` can unregister it: the token is only ever
    /// handed back to NotificationCenter, which is thread-safe.
    nonisolated(unsafe) private var screenObserver: (any NSObjectProtocol)?
    /// Unsafe-nonisolated for the same reason as `screenObserver`: `deinit`
    /// only cancels it, which is safe from any thread.
    nonisolated(unsafe) private var duckLoop: Task<Void, Never>?
    private let model: PanelModel

    /// Matches `TopProcessSource`'s interval rather than the 1s snapshot poll.
    /// A window-list read costs ~0.36ms, so this is 0.02% of a core and cost is
    /// not what sets the interval; it bounds how long an alert can stay buried,
    /// and 2s is short enough not to be noticed while reaching for the mouse.
    private static let duckInterval: Duration = .seconds(2)

    init(model: PanelModel) {
        self.model = model
    }

    deinit {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
        duckLoop?.cancel()
    }

    /// The display the panel belongs on: the one matching its exact pixel size.
    ///
    /// Nil when that display is not attached. The panel is built for one piece
    /// of hardware at 1:1 scale; on any other display it is a 1280x480
    /// always-on-top slab over whatever the machine is actually being used for,
    /// so it hides rather than following the user home.
    static func targetScreen() -> NSScreen? {
        NSScreen.screens.first { $0.frame.size == PanelView.size }
    }

    func show() {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: PanelView.size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = true
        window.backgroundColor = .black
        window.hasShadow = false
        window.isMovableByWindowBackground = false
        window.level = ScreenOccupancy.restingLevel
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenNone]
        window.contentView = NSHostingView(rootView: PanelRoot(model: model))
        self.window = window

        // Shows the panel, or leaves it hidden, according to what is attached.
        reposition()

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reposition() }
        }
    }

    /// Puts the panel below anything on its display that it would otherwise
    /// hide, and back on top once that window has gone.
    ///
    /// Changing the level rather than ordering the window out keeps
    /// `reposition()` the only thing that owns presence and the sampling
    /// lifecycle, so ducking cannot stop sampling or make the panel flicker.
    /// While ducked the menu bar does draw over the header, which is the price
    /// of letting an alert through and lasts only as long as the alert.
    private func updateDucking() {
        guard let window, window.isVisible else { return }
        guard let screen = Self.targetScreen(),
              let bounds = WindowListSource.bounds(of: screen) else { return }

        let wanted = ScreenOccupancy.level(
            given: WindowListSource.onScreenWindows(),
            on: bounds
        )
        if window.level != wanted {
            window.level = wanted
        }
    }

    /// The poll runs only while the panel is on screen, for the same reason
    /// sampling does: an absent display must not keep costing anything.
    private func startDucking() {
        duckLoop?.cancel()
        duckLoop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.duckInterval)
                guard let self else { return }
                self.updateDucking()
            }
        }
    }

    private func stopDucking() {
        duckLoop?.cancel()
        duckLoop = nil
    }

    /// Re-seats the window after a display is attached, removed or rearranged,
    /// and puts the panel away entirely while its display is absent.
    ///
    /// Sampling stops with it: idle, the panel and its `top` child are the most
    /// expensive thing running for no reason at all.
    func reposition() {
        guard let window else { return }
        guard let screen = Self.targetScreen() else {
            if window.isVisible {
                window.orderOut(nil)
                model.stop()
                stopDucking()
            }
            return
        }

        let frame = screen.frame
        window.setFrame(
            NSRect(
                x: frame.minX,
                y: frame.maxY - PanelView.size.height,
                width: PanelView.size.width,
                height: PanelView.size.height
            ),
            display: true
        )

        if !window.isVisible {
            model.start()
            window.orderFrontRegardless()
            startDucking()
        }
    }
}

/// Observes the model so the hosted view refreshes on each snapshot.
private struct PanelRoot: View {
    let model: PanelModel

    var body: some View {
        PanelView(snapshot: model.snapshot)
    }
}
