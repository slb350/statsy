import Foundation

/// The targets the panel knows about.
///
/// Host facts here come from the homelab repository's `docs/01-hosts.md` and
/// from each exporter's own unit or compose file; where an exporter listens is
/// the one fact a wrong guess turns into a tunnel to nothing.
public enum TargetRegistry {
    public static let local = Target(id: "local", name: "This Mac", source: .local)

    public static let homelabAI1 = linux(
        id: "homelab-ai-1",
        // UFW admits 9100 from the operations host only, and the listener is
        // bound to the LAN address rather than loopback, so the tunnel lands
        // on the host's own address from inside.
        endpoint: ExporterEndpoint(address: "192.168.68.88", localPort: 19100, exporterHost: "192.168.68.88"),
        model: "Threadripper 3960X 24C/48T", gpuDescription: "3 × RTX 3080 20 GB",
        volumes: [
            RemoteVolume(mountPoint: "/", name: "Root", role: .system),
            RemoteVolume(mountPoint: "/srv", name: "Srv", role: .data),
            RemoteVolume(mountPoint: "/mnt/nas-storage", name: "NAS", role: .network)
        ],
        diskDevices: ["nvme0n1"]
    )

    public static let strix = linux(
        id: "strix",
        // Same shape as ai-1: the exporter binds its LAN address and UFW keeps
        // it narrow, so the tunnel lands on it from inside.
        endpoint: ExporterEndpoint(address: "192.168.68.63", localPort: 19163, exporterHost: "192.168.68.63"),
        model: "Ryzen AI Max 395 16C/32T", gpuDescription: "Radeon 8060S 128 GB (unified)",
        volumes: [
            RemoteVolume(mountPoint: "/", name: "Root", role: .system)
            // /mnt/coldstore (NFS from BabyNas) is deliberately absent: the
            // fleet's contract checks its presence but never stats it — a
            // stalled hard mount would wedge the collector — and node_exporter
            // publishes no capacity for it either, so no safe source can ever
            // fill the row.
        ],
        diskDevices: ["nvme0n1"],
        unifiedMemory: true
    )

    public static let homelab1 = linux(
        id: "homelab-1",
        // The native exporter retains the LAN binding after the OS rebuild.
        endpoint: ExporterEndpoint(address: "192.168.68.73", localPort: 19173, exporterHost: "192.168.68.73"),
        model: "Core i5-12600K 10C/16T", gpuDescription: "Radeon AI PRO R9700 32 GB",
        volumes: [
            RemoteVolume(mountPoint: "/", name: "Root", role: .system),
            RemoteVolume(mountPoint: "/srv", name: "Srv", role: .data)
            // The native exporter's default filter excludes NFS capacity.
            // NAS mounts remain present but have no capacity series to draw.
        ],
        // NVMe enumeration changed with the motherboard: /srv is nvme0n1,
        // root's LVM is on nvme1n1. Both physical devices still count once.
        diskDevices: ["nvme0n1", "nvme1n1"],
        // The fan controller owns the Radeon wake/read/suspend cycle and
        // publishes cached telemetry. A second hwmon reader defeats suspend.
        disabledCollectors: ["hwmon"]
    )

    public static let homelabLegion = linux(
        id: "homelab-legion",
        // This exporter listens on every address, so loopback reaches it.
        endpoint: ExporterEndpoint(address: "192.168.68.72", localPort: 19172, exporterHost: "127.0.0.1"),
        model: "Ryzen Z1 Extreme 8C/16T", gpuDescription: "Radeon 780M",
        volumes: [
            RemoteVolume(mountPoint: "/", name: "Root", role: .system),
            RemoteVolume(mountPoint: "/srv", name: "Srv", role: .data),
            RemoteVolume(mountPoint: "/mnt/nas-storage", name: "NAS", role: .network)
        ],
        diskDevices: ["nvme0n1"]
    )

    /// The SSH address and both ends of its exporter forward travel together.
    private struct ExporterEndpoint {
        let address: String
        let localPort: Int
        let exporterHost: String
    }

    /// A Linux host reached as `steve`, named the same in the menu, the header
    /// and its collector's `asset_host` label.
    private static func linux(
        id: String, endpoint: ExporterEndpoint,
        model: String, gpuDescription: String? = nil, volumes: [RemoteVolume],
        diskDevices: [String], unifiedMemory: Bool = false,
        disabledCollectors: Set<String> = []
    ) -> Target {
        Target(
            id: id,
            name: id,
            source: .remote(
                RemoteTarget(
                    sshUser: "steve", sshHost: endpoint.address,
                    exporterHost: endpoint.exporterHost, localPort: endpoint.localPort,
                    hostName: id, model: model, gpuDescription: gpuDescription,
                    volumes: volumes, diskDevices: diskDevices,
                    unifiedMemory: unifiedMemory, disabledCollectors: disabledCollectors
                )
            )
        )
    }

    public static let macMini2 = macMini(
        id: "mac-mini-2", address: "192.168.68.82", localPort: 19182,
        network: [
            RemoteVolume(
                mountPoint: "/Users/stephenbrandon/NAS/models", name: "Models", role: .network
            ),
            RemoteVolume(
                mountPoint: "/Users/stephenbrandon/NAS/novels-backups", name: "Backups",
                role: .network
            )
        ]
    )

    public static let macMini3 = macMini(
        id: "mac-mini-3", address: "192.168.68.84", localPort: 19184,
        network: [
            RemoteVolume(
                mountPoint: "/Users/stephenbrandon/NAS/novels-backups", name: "Backups",
                role: .network
            )
        ]
    )

    public static let macMiniM6 = Target(
        id: "mac-mini-m6", name: "mac-mini-m6",
        source: .remote(
            RemoteTarget(
                sshUser: "stephenbrandon", sshHost: "192.168.70.165",
                // Root launchd owns the loopback-only exporter.
                exporterHost: "127.0.0.1", localPort: 19265,
                platform: .macOS, hostName: "mac-mini-m6",
                model: "Apple M6", gpuDescription: "12-core GPU",
                // IODeviceTree: cpu0–5 E, cpu6–7 P (Super), cpu8–11 M
                // (Performance). hw.perflevel reports the opposite tier order.
                clusters: [
                    CPUCluster(name: "Efficiency", coreCount: 6),
                    CPUCluster(name: "Super", coreCount: 2),
                    CPUCluster(name: "Performance", coreCount: 4)
                ],
                volumes: [
                    RemoteVolume(mountPoint: "/System/Volumes/Data", name: "Data", role: .data),
                    RemoteVolume(
                        mountPoint: "/Users/stephenbrandon/NAS/models", name: "Models", role: .network
                    ),
                    RemoteVolume(
                        mountPoint: "/Users/stephenbrandon/NAS/novels-backups", name: "Backups",
                        role: .network
                    )
                ],
                diskDevices: ["disk0"]
            )
        )
    )

    /// The two M1 minis differ only in address and NAS mounts.
    ///
    /// Their exporter is a loopback-only LaunchAgent, so the forward lands on
    /// 127.0.0.1. APFS reports one container's capacity for every volume in
    /// it, so the Data volume stands for the whole disk.
    private static func macMini(
        id: String, address: String, localPort: Int, network: [RemoteVolume]
    ) -> Target {
        Target(
            id: id,
            name: id,
            source: .remote(
                RemoteTarget(
                    sshUser: "stephenbrandon",
                    sshHost: address,
                    exporterHost: "127.0.0.1",
                    localPort: localPort,
                    platform: .macOS,
                    hostName: id,
                    model: "Apple M1",
                    gpuDescription: "8-core GPU",
                    // M1 numbers its efficiency cores first.
                    clusters: [
                        CPUCluster(name: "Efficiency", coreCount: 4),
                        CPUCluster(name: "Performance", coreCount: 4)
                    ],
                    volumes: [
                        RemoteVolume(mountPoint: "/System/Volumes/Data", name: "Data", role: .data)
                    ] + network,
                    diskDevices: ["disk0"]
                )
            )
        )
    }

    public static let all: [Target] = [
        local, homelabAI1, strix, homelab1, homelabLegion, macMini2, macMini3, macMiniM6
    ]

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
