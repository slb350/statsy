import Foundation

/// Reads temperature sensors and fans from the SMC.
///
/// Key names are enumerated once at startup and filtered down to the clusters
/// the panel charts; each refresh then only reads those. On this machine that
/// is ~130 keys out of 361, which keeps a 1 Hz refresh cheap.
public final class SMCReader {
    /// Cached description of one sensor key.
    private struct SensorKey {
        let code: UInt32
        let name: String
        let info: SMCKeyData.KeyInfo
    }

    private let connection: SMCConnection
    private let sensorKeys: [SensorKey]
    private let fanKeys: [(index: Int, actual: SensorKey, maximum: SensorKey)]

    public init?() {
        // The request layout is only correct at this exact size; if a future
        // toolchain lays the struct out differently, fail rather than lie.
        guard MemoryLayout<SMCKeyData>.stride == 80, let connection = SMCConnection() else {
            return nil
        }
        self.connection = connection

        let allKeys = Self.enumerateKeys(connection)
        sensorKeys = allKeys.compactMap { name, code in
            guard ThermalCalculator.cluster(for: name) != nil,
                  let info = Self.keyInfo(connection, code: code)
            else { return nil }
            return SensorKey(code: code, name: name, info: info)
        }
        fanKeys = Self.discoverFans(connection)
    }

    /// Every charted temperature sensor, sampled now.
    public func sensors() -> [ThermalSensor] {
        sensorKeys.compactMap { key in
            guard let value = read(key) else { return nil }
            return ThermalSensor(key: key.name, celsius: value)
        }
    }

    /// Current and maximum speed for each fan.
    public func fans() -> [FanReading] {
        fanKeys.compactMap { fan in
            guard let actual = read(fan.actual), let maximum = read(fan.maximum) else {
                return nil
            }
            return FanReading(id: fan.index, actual: actual, maximum: maximum)
        }
    }

    // MARK: - Key discovery

    private static func enumerateKeys(_ connection: SMCConnection) -> [(String, UInt32)] {
        guard let total = value(connection, key: "#KEY"), total > 0 else { return [] }

        return (0..<Int(total)).compactMap { index in
            var request = SMCKeyData()
            request.data8 = SMCConnection.Command.readIndex.rawValue
            request.data32 = UInt32(index)
            guard let response = connection.call(request), response.key != 0 else { return nil }
            return (FourCharCode.decode(response.key), response.key)
        }
    }

    private static func discoverFans(_ connection: SMCConnection) -> [(Int, SensorKey, SensorKey)] {
        guard let count = value(connection, key: "FNum") else { return [] }

        return (0..<Int(count)).compactMap { index in
            let actualCode = FourCharCode.encode("F\(index)Ac")
            let maximumCode = FourCharCode.encode("F\(index)Mx")
            guard let actualInfo = keyInfo(connection, code: actualCode),
                  let maximumInfo = keyInfo(connection, code: maximumCode)
            else { return nil }
            return (
                index,
                SensorKey(code: actualCode, name: "F\(index)Ac", info: actualInfo),
                SensorKey(code: maximumCode, name: "F\(index)Mx", info: maximumInfo)
            )
        }
    }

    /// Reads one key by name, resolving its type on the way.
    private static func value(_ connection: SMCConnection, key: String) -> Double? {
        let code = FourCharCode.encode(key)
        guard let info = keyInfo(connection, code: code),
              let payload = readRaw(connection, code: code, info: info)
        else { return nil }
        return SMCDecoder.decode(payload: payload, info: info)
    }

    private static func keyInfo(_ connection: SMCConnection, code: UInt32) -> SMCKeyData.KeyInfo? {
        var request = SMCKeyData()
        request.key = code
        request.data8 = SMCConnection.Command.readKeyInfo.rawValue
        guard let response = connection.call(request), response.keyInfo.dataSize > 0 else {
            return nil
        }
        return response.keyInfo
    }

    private static func readRaw(
        _ connection: SMCConnection, code: UInt32, info: SMCKeyData.KeyInfo
    ) -> [UInt8]? {
        var request = SMCKeyData()
        request.key = code
        request.keyInfo = info
        request.data8 = SMCConnection.Command.readBytes.rawValue
        return connection.call(request)?.payload
    }

    private func read(_ key: SensorKey) -> Double? {
        guard let payload = Self.readRaw(connection, code: key.code, info: key.info) else {
            return nil
        }
        return SMCDecoder.decode(payload: payload, info: key.info)
    }
}

/// Decodes SMC payloads, whose encoding is named by the key's data type.
enum SMCDecoder {
    static func decode(payload: [UInt8], info: SMCKeyData.KeyInfo) -> Double? {
        let size = Int(info.dataSize)
        guard size > 0, size <= payload.count else { return nil }

        switch FourCharCode.decode(info.dataType) {
        case "flt ":
            guard size == 4 else { return nil }
            return Double(Float(bitPattern: littleEndian32(payload)))
        case "sp78":
            guard size == 2 else { return nil }
            return Double(Int16(bitPattern: bigEndian16(payload))) / 256
        case "fpe2":
            guard size == 2 else { return nil }
            return Double(bigEndian16(payload)) / 4
        case "ui8 ":
            return Double(payload[0])
        case "ui16":
            guard size == 2 else { return nil }
            return Double(bigEndian16(payload))
        case "ui32":
            guard size == 4 else { return nil }
            return Double(bigEndian32(payload))
        default:
            return nil
        }
    }

    private static func bigEndian16(_ bytes: [UInt8]) -> UInt16 {
        UInt16(bytes[0]) << 8 | UInt16(bytes[1])
    }

    private static func bigEndian32(_ bytes: [UInt8]) -> UInt32 {
        UInt32(bytes[0]) << 24 | UInt32(bytes[1]) << 16 | UInt32(bytes[2]) << 8 | UInt32(bytes[3])
    }

    private static func littleEndian32(_ bytes: [UInt8]) -> UInt32 {
        UInt32(bytes[3]) << 24 | UInt32(bytes[2]) << 16 | UInt32(bytes[1]) << 8 | UInt32(bytes[0])
    }
}
