import Foundation

/// A machine the panel can be pointed at.
public struct Target: Sendable, Equatable, Identifiable {
    public let id: String
    /// What the menu calls it.
    public let name: String
    public let source: Source

    public enum Source: Sendable, Equatable {
        case local
        case remote(RemoteTarget)
    }

    public init(id: String, name: String, source: Source) {
        self.id = id
        self.name = name
        self.source = source
    }

    public var remote: RemoteTarget? {
        guard case .remote(let target) = source else { return nil }
        return target
    }

}

/// One volume the panel should show for a remote target.
///
/// Listed explicitly rather than discovered: a Linux host mounts a dozen
/// filesystems that mean nothing on a glanceable panel, and the role is a
/// decision about what a mount is for, which the mount table cannot answer.
public struct RemoteVolume: Sendable, Equatable {
    public let mountPoint: String
    public let name: String
    public let role: VolumeRole

    public init(mountPoint: String, name: String, role: VolumeRole) {
        self.mountPoint = mountPoint
        self.name = name
        self.role = role
    }
}

/// Everything needed to reach a host's node_exporter and read it correctly.
public struct RemoteTarget: Sendable, Equatable {
    public let sshUser: String
    public let sshHost: String
    /// Where node_exporter listens, addressed as the target host sees it.
    ///
    /// Not necessarily loopback: ai-1's exporter binds its LAN address
    /// specifically, so a forward to `127.0.0.1:9100` there connects to nothing.
    public let exporterHost: String
    public let exporterPort: Int
    /// This end of the tunnel, on loopback.
    public let localPort: Int

    /// Header facts the exporter does not publish.
    public let hostName: String
    public let model: String
    public let gpuDescription: String?

    public let volumes: [RemoteVolume]
    /// The block device whose counters drive the throughput readout. Picking
    /// one avoids double-counting the LVM mappers stacked on top of it.
    public let diskDevice: String
    /// Namespace of the fleet collector's textfile metrics. Everything else
    /// host-specific already comes from here; leaving this one hard-coded in
    /// the mapper meant a host with a differently-prefixed collector would draw
    /// no GPUs and no services, with nothing reporting why.
    public let collectorPrefix: String

    public init(
        sshUser: String, sshHost: String,
        exporterHost: String, exporterPort: Int = 9100, localPort: Int,
        hostName: String, model: String, gpuDescription: String? = nil,
        volumes: [RemoteVolume], diskDevice: String,
        collectorPrefix: String = "homelab_"
    ) {
        self.sshUser = sshUser
        self.sshHost = sshHost
        self.exporterHost = exporterHost
        self.exporterPort = exporterPort
        self.localPort = localPort
        self.hostName = hostName
        self.model = model
        self.gpuDescription = gpuDescription
        self.volumes = volumes
        self.diskDevice = diskDevice
        self.collectorPrefix = collectorPrefix
    }

    public var metricsURL: URL? {
        URL(string: "http://127.0.0.1:\(localPort)/metrics")
    }
}

/// The targets the panel knows about.
public enum TargetRegistry {
    public static let local = Target(id: "local", name: "This Mac", source: .local)

    public static let homelabAI1 = Target(
        id: "homelab-ai-1",
        name: "homelab-ai-1",
        source: .remote(
            RemoteTarget(
                sshUser: "steve",
                sshHost: "192.168.68.88",
                // UFW admits 9100 from the operations host only, and the
                // listener is bound to the LAN address rather than loopback,
                // so the tunnel lands on the host's own address from inside.
                exporterHost: "192.168.68.88",
                localPort: 19100,
                hostName: "homelab-ai-1",
                model: "Threadripper 3960X 24C/48T",
                gpuDescription: "3 × RTX 3080 20 GB",
                volumes: [
                    RemoteVolume(mountPoint: "/", name: "Root", role: .system),
                    RemoteVolume(mountPoint: "/srv", name: "Srv", role: .data),
                    RemoteVolume(mountPoint: "/mnt/nas-storage", name: "NAS", role: .network),
                ],
                diskDevice: "nvme0n1"
            )
        )
    )

    public static let all: [Target] = [local, homelabAI1]

    public static func target(id: String) -> Target? {
        all.first { $0.id == id }
    }
}

/// A `--target` argument naming a machine that is not in the registry.
public struct UnknownTarget: Error, LocalizedError {
    public let id: String

    public var errorDescription: String? {
        let known = TargetRegistry.all.map(\.id).joined(separator: ", ")
        return "unknown target '\(id)'. known targets: \(known)"
    }
}

public extension TargetRegistry {
    /// Resolves a `--target <id>` argument, or `fallback` when the flag is absent.
    ///
    /// The wording of the failure lives here rather than in each executable, so
    /// the panel and the probe cannot drift into answering the same flag
    /// differently. An unrecognised id throws rather than falling back to the
    /// local machine: a tool asked to look at another host and quietly
    /// reporting on this one is worse than refusing.
    static func target(
        from arguments: [String], default fallback: @autoclosure () -> Target
    ) throws -> Target {
        guard let flag = arguments.firstIndex(of: "--target") else { return fallback() }
        let next = arguments.index(after: flag)
        guard next < arguments.endIndex else { throw UnknownTarget(id: "") }
        let id = arguments[next]
        guard let target = target(id: id) else { throw UnknownTarget(id: id) }
        return target
    }
}
