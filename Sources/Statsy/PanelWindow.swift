import AppKit
import StatsyKit
import SwiftUI

/// Places the panel on the small secondary display and keeps it there.
@MainActor
final class PanelWindow {
    private var window: NSWindow?
    /// Unsafe-nonisolated so `deinit` can unregister it: the token is only ever
    /// handed back to NotificationCenter, which is thread-safe.
    nonisolated(unsafe) private var screenObserver: (any NSObjectProtocol)?
    private let model: PanelModel

    init(model: PanelModel) {
        self.model = model
    }

    deinit {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
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
        // Above the menu bar: this display is dedicated to the panel, and at
        // .normal the menu bar draws straight over the header.
        window.level = .statusBar
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
