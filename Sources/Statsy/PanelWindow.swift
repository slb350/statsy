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
    /// Falls back to any external display, then to whatever is attached, so the
    /// app stays usable when the panel is unplugged. The fallback asks
    /// CoreGraphics which display is built in rather than comparing against
    /// `NSScreen.main`, which follows keyboard focus and would move the panel
    /// around as the user switches windows.
    static func targetScreen() -> NSScreen? {
        let screens = NSScreen.screens
        if let exact = screens.first(where: { $0.frame.size == PanelView.size }) {
            return exact
        }
        return screens.first { !$0.isBuiltIn } ?? screens.first
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

        reposition()
        window.orderFrontRegardless()

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reposition() }
        }
    }

    /// Re-seats the window after a display is attached, removed or rearranged.
    func reposition() {
        guard let window, let screen = Self.targetScreen() else { return }
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
    }
}

private extension NSScreen {
    /// Whether this is the machine's built-in display.
    var isBuiltIn: Bool {
        guard let number = deviceDescription[
            NSDeviceDescriptionKey("NSScreenNumber")
        ] as? NSNumber else { return false }
        return CGDisplayIsBuiltin(CGDirectDisplayID(number.uint32Value)) != 0
    }
}

/// Observes the model so the hosted view refreshes on each snapshot.
private struct PanelRoot: View {
    let model: PanelModel

    var body: some View {
        PanelView(snapshot: model.snapshot)
    }
}
