import Foundation

/// Version 1 wire format. Decode bytes explicitly: BLE integers are little endian.
public struct DistanceFrame: Equatable {
    public static let serviceUUID = "A3C90001-8E64-4B6B-9C21-42B72A103A10"
    public static let measurementUUID = "A3C90002-8E64-4B6B-9C21-42B72A103A10"
    public static let infoUUID = "A3C90003-8E64-4B6B-9C21-42B72A103A10"
    public let sequence: UInt16
    public let uptimeMilliseconds: UInt32
    public let distanceMillimeters: UInt16
    public let isValid: Bool
    public let isSimulated: Bool
    public let sensorStatus: UInt8

    public enum DecodeError: Error { case length, version, reserved, inconsistentReading }

    public init(data: Data) throws {
        let b = Array(data)
        guard b.count == 12 else { throw DecodeError.length }
        guard b[0] == 1 else { throw DecodeError.version }
        guard b[1] & 0xFC == 0, b[11] == 0 else { throw DecodeError.reserved }
        sequence = UInt16(b[2]) | UInt16(b[3]) << 8
        uptimeMilliseconds = UInt32(b[4]) | UInt32(b[5]) << 8 | UInt32(b[6]) << 16 | UInt32(b[7]) << 24
        distanceMillimeters = UInt16(b[8]) | UInt16(b[9]) << 8
        isValid = b[1] & 1 != 0
        isSimulated = b[1] & 2 != 0
        sensorStatus = b[10]
        guard isValid ? (40...4000).contains(distanceMillimeters) && sensorStatus == 0
                      : distanceMillimeters == UInt16.max && sensorStatus != 0 else {
            throw DecodeError.inconsistentReading
        }
    }

    public static func encode(sequence: UInt16, uptime: UInt32, distance: UInt16?, simulated: Bool, status: UInt8 = 0) -> Data {
        let valid = distance.map { (40...4000).contains($0) } == true && status == 0
        let mm = valid ? distance! : UInt16.max
        return Data([1, (valid ? 1 : 0) | (simulated ? 2 : 0),
                     UInt8(truncatingIfNeeded: sequence), UInt8(truncatingIfNeeded: sequence >> 8),
                     UInt8(truncatingIfNeeded: uptime), UInt8(truncatingIfNeeded: uptime >> 8),
                     UInt8(truncatingIfNeeded: uptime >> 16), UInt8(truncatingIfNeeded: uptime >> 24),
                     UInt8(truncatingIfNeeded: mm), UInt8(truncatingIfNeeded: mm >> 8),
                     valid ? 0 : (status == 0 ? 1 : status), 0])
    }
}

/// Sequence arithmetic also accepts the UInt16 wrap from 65535 to 0.
public struct FrameSequence {
    private var last: UInt16?
    public init() {}
    public mutating func accept(_ sequence: UInt16) -> Bool {
        if let last {
            let delta = sequence &- last
            guard delta > 0 && delta < 32768 else { return false }
        }
        last = sequence
        return true
    }
}
