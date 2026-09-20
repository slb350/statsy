import Foundation

/// Where the chosen target is recorded, and how both apps agree on it.
///
/// A file rather than a shared `UserDefaults` suite: an app group needs a
/// signing entitlement these ad-hoc bundles do not carry, and the panel has to
/// notice a change made by the menu while it is already running. One line of
/// text in Application Support needs neither.
public struct TargetSelection: Sendable {
    private static let directory = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Statsy", isDirectory: true)

    public static let file = directory.appendingPathComponent("target", isDirectory: false)

    public let url: URL

    public init(url: URL = TargetSelection.file) {
        self.url = url
    }

    /// The selected target, falling back to local.
    ///
    /// An unreadable or unrecognised selection is the local machine rather than
    /// an error: the panel must come up showing something.
    public func read() -> Target {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            return TargetRegistry.local
        }
        let id = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return TargetRegistry.target(id: id) ?? TargetRegistry.local
    }

    public func write(_ target: Target) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try (target.id + "\n").write(to: url, atomically: true, encoding: .utf8)
    }
}
