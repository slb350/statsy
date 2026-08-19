import Foundation
import IOKit

/// A connection to the `AppleSMC` device.
///
/// The System Management Controller is where fan speeds and the hundreds of
/// on-die temperature sensors live. Access is unprivileged, but the interface
/// is a single ioctl-style struct call with no public header, so the request
/// layout below has to match the kernel's byte for byte.
final class SMCConnection {
    /// Selector for the SMC's struct method.
    private static let kernelIndex: UInt32 = 2

    enum Command: UInt8 {
        case readBytes = 5
        case readIndex = 8
        case readKeyInfo = 9
    }

    private var connection: io_connect_t = 0

    init?() {
        guard let matching = IOServiceMatching("AppleSMC") else { return nil }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard IOServiceOpen(service, mach_task_self_, 0, &connection) == kIOReturnSuccess else {
            return nil
        }
    }

    deinit {
        if connection != 0 { IOServiceClose(connection) }
    }

    /// Issues one SMC call. Returns nil if the kernel rejects it.
    func call(_ input: SMCKeyData) -> SMCKeyData? {
        var request = input
        var response = SMCKeyData()
        var responseSize = MemoryLayout<SMCKeyData>.stride

        let status = withUnsafePointer(to: &request) { requestPointer in
            withUnsafeMutablePointer(to: &response) { responsePointer in
                IOConnectCallStructMethod(
                    connection, Self.kernelIndex,
                    requestPointer, MemoryLayout<SMCKeyData>.stride,
                    responsePointer, &responseSize
                )
            }
        }
        guard status == kIOReturnSuccess, response.result == 0 else { return nil }
        return response
    }
}

// MARK: - Request layout

/// Mirrors the kernel's `SMCKeyData_t`, which is 80 bytes.
///
/// Field order and padding are load-bearing; `SMCReader` asserts the size at
/// startup so a layout change fails loudly rather than returning nonsense.
struct SMCKeyData {
    struct Version {
        var major: UInt8 = 0
        var minor: UInt8 = 0
        var build: UInt8 = 0
        var reserved: UInt8 = 0
        var release: UInt16 = 0
    }

    struct PLimitData {
        var version: UInt16 = 0
        var length: UInt16 = 0
        var cpuPLimit: UInt32 = 0
        var gpuPLimit: UInt32 = 0
        var memPLimit: UInt32 = 0
    }

    struct KeyInfo {
        var dataSize: UInt32 = 0
        var dataType: UInt32 = 0
        var dataAttributes: UInt8 = 0
        /// Explicit tail padding.
        ///
        /// C pads this struct to 12 bytes. Swift otherwise reuses the three
        /// slack bytes for the fields that follow it in `SMCKeyData`, which
        /// shortens the request to 76 bytes and misaligns everything after it.
        private var padding: (UInt8, UInt8, UInt8) = (0, 0, 0)
    }

    var key: UInt32 = 0
    var version = Version()
    var pLimitData = PLimitData()
    var keyInfo = KeyInfo()
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)

    /// Offset of `bytes` within the struct, used to read the payload back out.
    static let payloadOffset = 48
    static let payloadSize = 32
}

extension SMCKeyData {
    /// The payload as a byte array.
    var payload: [UInt8] {
        withUnsafeBytes(of: self) { raw in
            Array(raw[Self.payloadOffset..<(Self.payloadOffset + Self.payloadSize)])
        }
    }
}

/// Converts between four-character SMC keys and their packed representation.
enum FourCharCode {
    static func encode(_ text: String) -> UInt32 {
        let scalars = Array(text.utf8)
        guard scalars.count == 4 else { return 0 }
        return scalars.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    }

    static func decode(_ value: UInt32) -> String {
        let bytes = [
            UInt8((value >> 24) & 0xFF), UInt8((value >> 16) & 0xFF),
            UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF),
        ]
        return String(decoding: bytes, as: UTF8.self)
    }
}
