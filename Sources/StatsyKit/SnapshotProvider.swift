import Foundation

/// Something that can produce snapshots for the panel.
///
/// The local engine and a remote host differ in everything except this: they
/// are started, polled, and stopped. Making that the seam means `PanelModel`
/// never learns which kind of target it is showing, and the views see one
/// `Snapshot` either way.
public protocol SnapshotProvider: Sendable {
    /// Primes whatever baselines the provider needs before its first sample.
    func start() async
    func stop() async
    func sample() async -> Snapshot

    /// How often this provider is worth polling.
    ///
    /// Local sampling is nearly free and runs at 1 Hz. A remote target costs a
    /// round trip and a scrape on the host being measured, and monitoring that
    /// distorts what it measures is the thing this app exists not to be.
    var refreshInterval: Duration { get }
}

public extension SnapshotProvider {
    var refreshInterval: Duration { .seconds(1) }

    /// One snapshot with real rates behind it, for the probe and the renderer.
    ///
    /// `start()` takes the baseline, so a single interval and a single sample
    /// is all a difference needs. The caller still owns `stop()`, because the
    /// probe prints from the snapshot before tearing the provider down.
    func primedSample() async -> Snapshot {
        await start()
        try? await Task.sleep(for: refreshInterval)
        return await sample()
    }
}

extension MetricsEngine: SnapshotProvider {}

/// Builds the provider for a target.
public enum SnapshotProviderFactory {
    public static func provider(for target: Target) -> any SnapshotProvider {
        switch target.source {
        case .local: MetricsEngine()
        case .remote(let remote): RemoteSnapshotProvider(target: remote)
        }
    }
}
