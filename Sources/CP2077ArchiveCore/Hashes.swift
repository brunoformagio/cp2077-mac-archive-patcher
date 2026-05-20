import Foundation

public enum Hashes {
    private static let fnvOffset: UInt64 = 0xcbf29ce484222325
    private static let fnvPrime: UInt64 = 0x100000001b3
    private static let crc64Poly: UInt64 = 0xC96C5795D7870F42

    private static let crc64Table: [UInt64] = (0..<256).map { index in
        var crc = UInt64(index)
        for _ in 0..<8 {
            crc = (crc & 1) != 0 ? (crc >> 1) ^ crc64Poly : crc >> 1
        }
        return crc
    }

    public static func fnv1a64Path(_ path: String) -> UInt64 {
        var hash = fnvOffset
        let normalized = path.lowercased().replacingOccurrences(of: "/", with: "\\")
        for byte in normalized.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* fnvPrime
        }
        return hash
    }

    public static func crc64(_ data: Data) -> UInt64 {
        var crc = UInt64.max
        for byte in data {
            let index = Int((crc ^ UInt64(byte)) & 0xff)
            crc = (crc >> 8) ^ crc64Table[index]
        }
        return ~crc
    }

    public static func hex64(_ value: UInt64) -> String {
        "0x" + String(value, radix: 16).leftPadded(to: 16, with: "0")
    }
}

extension String {
    func leftPadded(to length: Int, with character: Character) -> String {
        if count >= length { return self }
        return String(repeating: String(character), count: length - count) + self
    }
}

