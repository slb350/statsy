import Foundation

/// Whether the numbers on screen are current, and how they got there.
///
/// Local sampling cannot fail, so it has no state worth reporting. A remote
/// target can be unreachable, slow, or serving readings a minute old, and a
/// frozen panel that still looks healthy is the worst thing a monitor can do.
public struct LinkStatus: Sendable, Equatable {
    public enum State: Sendable, Equatable {
        /// Sampled in this process. Always current.
        case local
        /// The last fetch succeeded.
        case live
        /// The last fetch failed, so these readings are the previous ones.
        case stale
        /// Nothing has been read yet, or the link has been down long enough
        /// that the last readings are not worth showing.
        case down
    }

    public let state: State
    /// Seconds since the last successful fetch. Zero while local.
    public let age: TimeInterval
    /// Why the link is stale or down, for the panel to show.
    public let detail: String?

    public init(state: State, age: TimeInterval = 0, detail: String? = nil) {
        self.state = state
        self.age = age
        self.detail = detail
    }

    public static let local = LinkStatus(state: .local)

}

/// Unit and endpoint health, as the fleet collector reports it.
///
/// Distinct from the metrics beside it in one way that matters: the collector
/// runs on a one-minute timer, so this is up to a minute behind everything
/// node_exporter reads at scrape time.
public struct ServiceHealth: Sendable, Equatable {
    public let activeUnits: Int
    public let totalUnits: Int
    public let endpoints: [EndpointReadiness]
    /// Age of the collector's own run, from its published timestamp.
    public let collectionAge: TimeInterval?

    public init(
        activeUnits: Int = 0, totalUnits: Int = 0,
        endpoints: [EndpointReadiness] = [], collectionAge: TimeInterval? = nil
    ) {
        self.activeUnits = activeUnits
        self.totalUnits = totalUnits
        self.endpoints = endpoints
        self.collectionAge = collectionAge
    }

    public static let empty = ServiceHealth()

    public var isEmpty: Bool { totalUnits == 0 && endpoints.isEmpty }
    public var allUnitsActive: Bool { activeUnits == totalUnits }
}

public struct EndpointReadiness: Sendable, Equatable, Identifiable {
    public var id: String { name }
    public let name: String
    public let ready: Bool

    public init(name: String, ready: Bool) {
        self.name = name
        self.ready = ready
    }
}
