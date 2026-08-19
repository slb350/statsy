import Darwin
import Foundation
import IOKit

/// Reads the fixed hardware description shown in the panel header.
public struct MachineSource: Sendable {
    public init() {}

    public func read(host: HostSource = HostSource()) -> MachineInfo {
        MachineInfo(
            model: host.sysctlString("machdep.cpu.brand_string") ?? "Mac",
            clusters: host.clusters(),
            gpuCoreCount: gpuCoreCount(),
            memoryBytes: host.physicalMemory,
            osVersion: osVersion()
        )
    }

    private func osVersion() -> String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion)"
    }



    /// GPU core count, published by the accelerator in the IO registry.
    private func gpuCoreCount() -> Int? {
        guard let matching = IOServiceMatching("AGXAccelerator") else { return nil }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        guard let property = IORegistryEntryCreateCFProperty(
            service, "gpu-core-count" as CFString, kCFAllocatorDefault, 0
        )?.takeRetainedValue() as? NSNumber else { return nil }
        return property.intValue
    }
}
