import Darwin
import Foundation

public struct NetworkMetrics: Sendable, Equatable {
    public let lifetimeIn: UInt64
    public let lifetimeOut: UInt64

    public init(lifetimeIn: UInt64 = 0, lifetimeOut: UInt64 = 0) {
        self.lifetimeIn = lifetimeIn
        self.lifetimeOut = lifetimeOut
    }

    public static let empty = NetworkMetrics()
}

/// Sums per-interface byte counters since boot.
///
/// Read through the IF-MIB (`IFMIB_IFDATA` / `IFDATA_GENERAL`), which is the
/// only one of the three obvious sources that reports true 64-bit totals.
/// `getifaddrs` hands back 32-bit counters, and `NET_RT_IFLIST2` — despite
/// declaring `if_data64` — was observed wrapping at 4 GiB on this machine's
/// primary interface, reporting 27 MB against an actual 34 GB. These figures
/// agree with `netstat -ib`.
public struct NetworkSource: Sendable {
    public init() {}

    public func read() -> NetworkMetrics {
        var count: Int32 = 0
        var countSize = MemoryLayout<Int32>.stride
        var countMib: [Int32] = [CTL_NET, PF_LINK, NETLINK_GENERIC, IFMIB_SYSTEM, IFMIB_IFCOUNT]
        guard sysctl(&countMib, u_int(countMib.count), &count, &countSize, nil, 0) == 0,
              count > 0
        else { return .empty }

        var received: UInt64 = 0
        var sent: UInt64 = 0
        // Hoisted: allocating this per interface cost about as much as the
        // syscalls it accompanies.
        var mib: [Int32] = [CTL_NET, PF_LINK, NETLINK_GENERIC, IFMIB_IFDATA, 0, IFDATA_GENERAL]
        for index in 1...count {
            var data = ifmibdata()
            var size = MemoryLayout<ifmibdata>.stride
            mib[4] = index
            guard sysctl(&mib, u_int(mib.count), &data, &size, nil, 0) == 0 else { continue }
            // Loopback traffic never left the machine.
            guard data.ifmd_data.ifi_type != UInt8(IFT_LOOP) else { continue }
            received += data.ifmd_data.ifi_ibytes
            sent += data.ifmd_data.ifi_obytes
        }
        return NetworkMetrics(lifetimeIn: received, lifetimeOut: sent)
    }
}
