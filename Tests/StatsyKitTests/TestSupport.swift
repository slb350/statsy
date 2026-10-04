import Foundation
@testable import StatsyKit

/// The captured scrapes under `Fixtures/`.
enum Fixtures {
    static func text(_ name: String) -> String {
        let url = Bundle.module.url(forResource: name, withExtension: "prom", subdirectory: "Fixtures")
        return (try? String(contentsOf: url!, encoding: .utf8)) ?? ""
    }
}

extension RemoteTarget {
    /// This target with one declaration changed and every other field kept.
    func replacing(collectorPrefix: String? = nil, unifiedMemory: Bool? = nil) -> RemoteTarget {
        RemoteTarget(
            sshUser: sshUser, sshHost: sshHost,
            exporterHost: exporterHost, exporterPort: exporterPort, localPort: localPort,
            platform: platform, hostName: hostName, model: model,
            gpuDescription: gpuDescription, clusters: clusters,
            volumes: volumes, diskDevices: diskDevices,
            collectorPrefix: collectorPrefix ?? self.collectorPrefix,
            unifiedMemory: unifiedMemory ?? self.unifiedMemory,
            ranksProcesses: ranksProcesses
        )
    }
}
