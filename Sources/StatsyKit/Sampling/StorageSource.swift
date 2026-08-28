import Darwin
import Foundation
import IOKit

/// Reads volume capacity and block-device throughput.
///
/// Both are unprivileged. Per-process disk I/O is deliberately not collected:
/// `proc_pid_rusage` returns EPERM for other users' processes, and over a
/// one-second window almost nothing is doing disk I/O anyway, so a top-five
/// list would be empty nearly always.
public struct StorageSource: Sendable {
    private struct VolumeSpec {
        let role: VolumeRole
        let name: String
        let path: String
    }

    /// Volumes to report, in display order.
    private static let volumes = [
        VolumeSpec(role: .data, name: "Data", path: "/System/Volumes/Data"),
        VolumeSpec(role: .swap, name: "VM", path: "/System/Volumes/VM"),
        VolumeSpec(role: .system, name: "System", path: "/")
    ]

    public init() {}

    /// Capacity of the data volume plus a per-volume breakdown.
    public func capacity() -> StorageCapacity {
        let mounts = mountedFilesystems()
        var volumes: [VolumeUsage] = []
        var total: UInt64 = 0
        var used: UInt64 = 0
        var free: UInt64 = 0

        for volume in Self.volumes {
            guard let stats = mounts[volume.path] else { continue }
            let blockSize = UInt64(stats.f_bsize)
            let containerTotal = stats.f_blocks * blockSize

            // statfs reports the whole APFS container for every volume in it,
            // so a volume's own usage has to come from getattrlist instead.
            let volumeUsed = spaceUsed(path: volume.path) ?? 0
            volumes.append(
                VolumeUsage(
                    role: volume.role, name: volume.name,
                    used: volumeUsed, total: containerTotal
                )
            )

            // The container's figures are what "71% full" means for the device.
            if volume.role == .data {
                total = containerTotal
                used = (stats.f_blocks - stats.f_bfree) * blockSize
                free = stats.f_bavail * blockSize
            }
        }
        return StorageCapacity(total: total, used: used, free: free, volumes: volumes)
    }

    /// Lifetime bytes read and written, summed across block storage drivers.
    public func lifetimeBytes() -> (read: UInt64, written: UInt64) {
        var iterator: io_iterator_t = 0
        guard let matching = IOServiceMatching("IOBlockStorageDriver"),
              IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS
        else { return (0, 0) }
        defer { IOObjectRelease(iterator) }

        var read: UInt64 = 0
        var written: UInt64 = 0
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            guard let statistics = copyStatistics(of: service) else { continue }
            read += (statistics["Bytes (Read)"] as? NSNumber)?.uint64Value ?? 0
            written += (statistics["Bytes (Write)"] as? NSNumber)?.uint64Value ?? 0
        }
        return (read, written)
    }

    /// Fetches just the driver's `Statistics` dictionary.
    ///
    /// `IORegistryEntryCreateCFProperties` would copy and bridge every property
    /// of the entry to read two numbers out of it.
    private func copyStatistics(of service: io_registry_entry_t) -> [String: Any]? {
        IORegistryEntryCreateCFProperty(
            service, "Statistics" as CFString, kCFAllocatorDefault, 0
        )?.takeRetainedValue() as? [String: Any]
    }

    /// Bytes a single volume occupies, via `getattrlist(ATTR_VOL_SPACEUSED)`.
    ///
    /// This is the only cheap source of per-volume usage on APFS, and is what
    /// `df`'s Used column reports; statfs cannot distinguish volumes that share
    /// a container.
    private func spaceUsed(path: String) -> UInt64? {
        var attributes = attrlist()
        attributes.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        attributes.volattr = attrgroup_t(ATTR_VOL_INFO) | attrgroup_t(ATTR_VOL_SPACEUSED)

        // The reply is packed { UInt32 length; Int64 spaceUsed }, so the second
        // field is not naturally aligned and must be loaded unaligned.
        var reply = [UInt8](repeating: 0, count: 12)
        let status = path.withCString { cPath in
            withUnsafeMutablePointer(to: &attributes) { attributePointer in
                reply.withUnsafeMutableBytes { buffer in
                    getattrlist(cPath, attributePointer, buffer.baseAddress, buffer.count, 0)
                }
            }
        }
        guard status == 0 else { return nil }

        let used = reply.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 4, as: Int64.self) }
        return used >= 0 ? UInt64(used) : nil
    }

    /// Mounted filesystems keyed by mount point.
    ///
    /// `getmntinfo` is used rather than `statfs` because the C function
    /// `statfs` is unreachable from Swift — the struct of the same name
    /// shadows it — and this also yields every volume in one call.
    private func mountedFilesystems() -> [String: Darwin.statfs] {
        var buffer: UnsafeMutablePointer<Darwin.statfs>?
        let count = getmntinfo(&buffer, MNT_NOWAIT)
        guard count > 0, let buffer else { return [:] }

        var result: [String: Darwin.statfs] = [:]
        for index in 0..<Int(count) {
            var entry = buffer[index]
            let path = withUnsafeBytes(of: &entry.f_mntonname) { raw in
                String(bytes: raw.prefix { $0 != 0 }, encoding: .utf8) ?? ""
            }
            result[path] = entry
        }
        return result
    }
}
