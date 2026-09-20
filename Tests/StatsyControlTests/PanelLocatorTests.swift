import Foundation
import Testing
@testable import StatsyControl

@Suite("Panel locator")
struct PanelLocatorTests {
    /// A locator over a fixed set of existing paths and an optional Launch
    /// Services answer.
    private func locator(
        existing: Set<String>,
        registered: URL? = nil
    ) -> PanelLocator {
        PanelLocator(
            bundleExists: { existing.contains($0.standardizedFileURL.path) },
            registeredBundle: { identifier in
                identifier == PanelLocator.panelBundleIdentifier ? registered : nil
            }
        )
    }

    @Test("prefers the panel sitting beside the controller")
    func prefersSibling() {
        let controller = URL(fileURLWithPath: "/Users/s/dev/statsy/.build/Statsy Menu.app")
        let sibling = URL(fileURLWithPath: "/Users/s/dev/statsy/.build/Statsy.app")
        let found = locator(
            existing: [sibling.path, "/Applications/Statsy.app"],
            registered: URL(fileURLWithPath: "/Applications/Statsy.app")
        ).locate(controllerBundle: controller)

        // A development controller must drive the development panel, not the
        // installed one, or a rebuild appears to change nothing.
        #expect(found == sibling)
    }

    @Test("falls back to the registered bundle when nothing sits alongside")
    func fallsBackToLaunchServices() {
        let controller = URL(fileURLWithPath: "/Applications/Statsy Menu.app")
        let registered = URL(fileURLWithPath: "/Users/s/Developer/Statsy.app")
        let found = locator(existing: [registered.path], registered: registered)
            .locate(controllerBundle: controller)

        #expect(found == registered)
    }

    @Test("ignores a registration pointing at a bundle that is gone")
    func ignoresStaleRegistration() {
        let installed = URL(fileURLWithPath: "/Applications/Statsy.app")
        let found = locator(
            existing: [installed.path],
            registered: URL(fileURLWithPath: "/Users/s/deleted/Statsy.app")
        ).locate(controllerBundle: URL(fileURLWithPath: "/Users/s/bin/Statsy Menu.app"))

        #expect(found == installed)
    }

    @Test("reports nothing when the panel is not installed anywhere")
    func reportsMissing() {
        let found = locator(existing: [])
            .locate(controllerBundle: URL(fileURLWithPath: "/Applications/Statsy Menu.app"))

        #expect(found == nil)
    }

    @Test("still searches the standard locations without a controller bundle")
    func worksWithoutAControllerBundle() {
        let installed = URL(fileURLWithPath: "/Applications/Statsy.app")
        #expect(locator(existing: [installed.path]).locate(controllerBundle: nil) == installed)
    }
}
