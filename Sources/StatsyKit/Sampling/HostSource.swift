import Darwin
import Foundation

/// Reads kernel-wide counters via mach and sysctl.
///
/// Everything here is unprivileged and system-wide, which is why the panel's
/// headline figures are always accurate even though its per-process lists
/// depend on `top`.
public struct HostSource: Sendable {
    public init() {}

    /// Installed physical memory in bytes.
    public var physicalMemory: UInt64 { ProcessInfo.processInfo.physicalMemory }

    /// Per-core tick counters. Empty if the kernel call fails.
    public func cpuTicks() -> [CPUTicks] {
        var coreCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0

        let result = host_processor_info(
            mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &coreCount, &info, &infoCount
        )
        guard result == KERN_SUCCESS, let info else { return [] }
        defer {
            vm_deallocate(
                mach_task_self_,
                vm_address_t(UInt(bitPattern: info)),
                vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride)
            )
        }

        let states = Int(CPU_STATE_MAX)
        let values = UnsafeBufferPointer(start: info, count: Int(infoCount))
        return (0..<Int(coreCount)).map { core in
            let base = core * states
            return CPUTicks(
                user: UInt32(bitPattern: values[base + Int(CPU_STATE_USER)]),
                system: UInt32(bitPattern: values[base + Int(CPU_STATE_SYSTEM)]),
                idle: UInt32(bitPattern: values[base + Int(CPU_STATE_IDLE)]),
                nice: UInt32(bitPattern: values[base + Int(CPU_STATE_NICE)])
            )
        }
    }

    /// Virtual memory page counts, or nil if the kernel call fails.
    public func vmCounters() -> VMCounters? {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride
        )
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        var pageSize: vm_size_t = 0
        guard host_page_size(mach_host_self(), &pageSize) == KERN_SUCCESS else { return nil }

        return VMCounters(
            free: UInt64(stats.free_count),
            active: UInt64(stats.active_count),
            inactive: UInt64(stats.inactive_count),
            speculative: UInt64(stats.speculative_count),
            wired: UInt64(stats.wire_count),
            compressed: UInt64(stats.compressor_page_count),
            pageSize: UInt64(pageSize)
        )
    }

    public func loadAverage() -> LoadAverage {
        var values = [Double](repeating: 0, count: 3)
        guard getloadavg(&values, 3) == 3 else {
            return LoadAverage(one: 0, five: 0, fifteen: 0)
        }
        return LoadAverage(one: values[0], five: values[1], fifteen: values[2])
    }

    /// Wall-clock seconds since boot.
    ///
    /// `ProcessInfo.systemUptime` excludes time asleep and reads about seven
    /// hours short of `uptime(1)` on this machine, so boot time is read directly.
    public func uptime() -> TimeInterval {
        var boot = timeval()
        var size = MemoryLayout<timeval>.stride
        guard sysctlbyname("kern.boottime", &boot, &size, nil, 0) == 0, boot.tv_sec > 0 else {
            return ProcessInfo.processInfo.systemUptime
        }
        return Date().timeIntervalSince1970 - Double(boot.tv_sec)
    }

    public func swapUsage() -> (used: UInt64, total: UInt64) {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.stride
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else { return (0, 0) }
        return (UInt64(usage.xsu_used), UInt64(usage.xsu_total))
    }

    /// Core clusters as the hardware reports them.
    ///
    /// Names are not fixed across chips — this machine's M5 Max reports
    /// "Super" (6) and "Performance" (12) rather than the usual
    /// performance/efficiency split, so they are read rather than assumed.
    public func clusters() -> [CPUCluster] {
        let levels = sysctlInt("hw.nperflevels") ?? 0
        guard levels > 0 else { return [] }
        return (0..<levels).compactMap { level in
            guard let name = sysctlString("hw.perflevel\(level).name"),
                  let count = sysctlInt("hw.perflevel\(level).physicalcpu"), count > 0
            else { return nil }
            return CPUCluster(name: name, coreCount: count)
        }
    }

    func sysctlInt(_ name: String) -> Int? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.stride
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return Int(value)
    }

    func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        if let terminator = buffer.firstIndex(of: 0) { buffer.removeSubrange(terminator...) }
        return String(decoding: buffer, as: UTF8.self)
    }
}
