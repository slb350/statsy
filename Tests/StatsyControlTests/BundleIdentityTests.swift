import Foundation
import Testing
@testable import StatsyControl

@Suite("Bundle identity")
struct BundleIdentityTests {
    /// `make-app.sh` is the other authority on what the panel bundle is called
    /// and what identifier it carries. Rename it there and the controller stops
    /// finding the panel with no error anywhere — the same silent failure the
    /// SMC layout and SF Symbol tests exist to catch.
    @Test("the panel name and identifier agree with the build script")
    func matchesBuildScript() throws {
        let script = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // StatsyControlTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // package root
            .appendingPathComponent("make-app.sh")
        let text = try String(contentsOf: script, encoding: .utf8)

        let name = PanelLocator.panelBundleName.replacingOccurrences(of: ".app", with: "")
        #expect(text.contains("bundle \(name) "), "no bundle line builds \(name)")
        #expect(
            text.contains(PanelLocator.panelBundleIdentifier + "\n"),
            "\(PanelLocator.panelBundleIdentifier) is not the identifier any bundle is built with"
        )
    }
}
