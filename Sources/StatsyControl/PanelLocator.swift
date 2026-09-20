import AppKit
import Foundation

/// Finds the Statsy panel bundle that this controller should drive.
///
/// The two are separate bundles, so the controller has to go looking. The
/// search order is the part worth pinning down, so both filesystem questions
/// default to the real ones and are injected only by the tests.
public struct PanelLocator: Sendable {
    public static let panelBundleIdentifier = "dev.steve.statsy"
    public static let panelBundleName = "Statsy.app"

    private let bundleExists: @Sendable (URL) -> Bool
    private let registeredBundle: @Sendable (String) -> URL?

    public init(
        bundleExists: @escaping @Sendable (URL) -> Bool = {
            FileManager.default.fileExists(atPath: $0.path)
        },
        registeredBundle: @escaping @Sendable (String) -> URL? = {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0)
        }
    ) {
        self.bundleExists = bundleExists
        self.registeredBundle = registeredBundle
    }

    /// The panel bundle, or nil when it is not installed.
    ///
    /// A panel sitting beside the controller wins over any other copy: the two
    /// bundles are built and installed as a pair, so a controller running out
    /// of `.build` must drive the panel it was just built with rather than an
    /// older one in `/Applications`.
    public func locate(controllerBundle: URL?) -> URL? {
        // Checked in order and lazily: when the panel sits beside the
        // controller, the Launch Services query never runs at all.
        if let sibling = controllerBundle?
            .deletingLastPathComponent()
            .appendingPathComponent(Self.panelBundleName),
            bundleExists(sibling) {
            return sibling
        }
        if let registered = registeredBundle(Self.panelBundleIdentifier),
            bundleExists(registered) {
            return registered
        }
        let installed = URL(fileURLWithPath: "/Applications")
            .appendingPathComponent(Self.panelBundleName)
        return bundleExists(installed) ? installed : nil
    }
}
