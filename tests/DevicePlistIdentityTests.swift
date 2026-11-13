import Foundation

struct IdentityTestError: Error { let message: String }
func mustReject(_ message: String, _ work: () throws -> Void) throws {
    do { try work() } catch is IdentityTestError { throw IdentityTestError(message: message) } catch { return }
    throw IdentityTestError(message: message)
}
@main struct DevicePlistIdentityTests {
    static func main() throws {
        let udid = "0123456789ABCDEF0123456789ABCDEF01234567"
        let serial = "TESTSERIAL12"
        let reference = try DevicePlistIdentity(properties: ["UniqueDeviceID": udid, "SerialNumber": serial, "UniqueChipID": UInt64(123456789)])
        func data(_ extra: [String: Any]) throws -> Data {
            try PropertyListSerialization.data(fromPropertyList: ["CacheExtra": extra], format: .binary, options: 0)
        }
        let owned = try DevicePlistIdentity(plist: data([
            "re6Zb+zwFKJNlkQTUeT+/w": udid.lowercased(), "VasUgeSzVyHdB27g2XpN0g": serial,
            "h9jDsbgj7xIVeIQ8S3/X3Q": "iPhone19,1", "h63QSdBCiT/z0WU6rdQv6Q": "CH"
        ]))
        try owned.requireMatch(with: reference)
        try DevicePlistIdentity(properties: ["SerialNumber": serial, "UniqueChipID": "0x75BCD15"]).requireMatch(with: reference)
        try mustReject("Same model and region do not prove ownership") {
            try DevicePlistIdentity(plist: data(["h9jDsbgj7xIVeIQ8S3/X3Q": "iPhone19,1", "h63QSdBCiT/z0WU6rdQv6Q": "CH"]))
                .requireMatch(with: reference)
        }
        try mustReject("One matching identifier is insufficient") {
            try DevicePlistIdentity(properties: ["SerialNumber": serial]).requireMatch(with: reference)
        }
        try mustReject("Any conflicting known identifier rejects the file, even with two matches") {
            try DevicePlistIdentity(properties: ["UniqueDeviceID": udid, "SerialNumber": serial, "UniqueChipID": 99])
                .requireMatch(with: reference)
        }
        try mustReject("Reject another device's identifiers") {
            try DevicePlistIdentity(properties: ["UniqueDeviceID": String(repeating: "A", count: 40), "SerialNumber": "OTHERPHONE12"])
                .requireMatch(with: reference)
        }
        try mustReject("Cannot use a missing device identity as a wildcard") {
            try owned.requireMatch(with: DevicePlistIdentity(properties: [:]))
        }
        try mustReject("Reject conflicting clear and hashed aliases") {
            _ = try DevicePlistIdentity(properties: ["SerialNumber": serial, "VasUgeSzVyHdB27g2XpN0g": "OTHERPHONE12"])
        }
        try mustReject("Boolean ECID is invalid") { _ = try DevicePlistIdentity(properties: ["UniqueChipID": true]) }
        try mustReject("Fractional ECID is invalid") { _ = try DevicePlistIdentity(properties: ["UniqueChipID": 123.5]) }
        try mustReject("Conflicting trusted sources cannot be silently merged") {
            _ = try reference.mergingTrusted(DevicePlistIdentity(properties: ["SerialNumber": "OTHERPHONE12"]))
        }
        if let path = ProcessInfo.processInfo.environment["GX_TEST_MG_EXPORT"] {
            let bytes = try Data(contentsOf: URL(fileURLWithPath: path))
            let parsed = try DevicePlistIdentity(plist: bytes)
            if parsed.values.count < 2 {
                try mustReject("Unidentifiable exports are refused, even if supplied by the owner") { try parsed.requireMatch(with: parsed) }
            } else { try parsed.requireMatch(with: parsed) }
        }
        print("PASS: two-identifier ownership checks, foreign/missing identity rejection, conflicting aliases, ECID types, and trusted-source consistency.")
    }
}
