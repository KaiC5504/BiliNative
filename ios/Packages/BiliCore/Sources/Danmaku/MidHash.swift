import Foundation

/// The `midHash` on a danmaku is the CRC-32 of the sender's uid, which is how a user block rule matches.
public enum MidHash {
    private static let table: [UInt32] = (0..<256).map { index in
        var c = UInt32(index)
        for _ in 0..<8 { c = c & 1 == 1 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
        return c
    }

    public static func of(uid: Int64) -> String {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in String(uid).utf8 {
            crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return String(crc ^ 0xFFFF_FFFF, radix: 16)
    }
}
