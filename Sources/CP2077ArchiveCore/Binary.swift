import Foundation

enum BinaryError: Error, CustomStringConvertible {
    case shortRead(URL, Int)
    case invalidOffset(Int)

    var description: String {
        switch self {
        case let .shortRead(url, count):
            return "short read from \(url.path), wanted \(count) bytes"
        case let .invalidOffset(offset):
            return "invalid binary offset \(offset)"
        }
    }
}

extension Data {
    func uint32LE(at offset: Int) throws -> UInt32 {
        guard offset >= 0, offset + 4 <= count else { throw BinaryError.invalidOffset(offset) }
        var value: UInt32 = 0
        for i in 0..<4 {
            value |= UInt32(self[offset + i]) << UInt32(i * 8)
        }
        return value
    }

    func int64LE(at offset: Int) throws -> Int64 {
        guard offset >= 0, offset + 8 <= count else { throw BinaryError.invalidOffset(offset) }
        return Int64(bitPattern: try uint64LE(at: offset))
    }

    func uint64LE(at offset: Int) throws -> UInt64 {
        guard offset >= 0, offset + 8 <= count else { throw BinaryError.invalidOffset(offset) }
        var value: UInt64 = 0
        for i in 0..<8 {
            value |= UInt64(self[offset + i]) << UInt64(i * 8)
        }
        return value
    }

    mutating func writeUInt32LE(_ value: UInt32, at offset: Int) throws {
        guard offset >= 0, offset + 4 <= count else { throw BinaryError.invalidOffset(offset) }
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { bytes in
            replaceSubrange(offset..<offset + 4, with: bytes)
        }
    }

    mutating func writeUInt64LE(_ value: UInt64, at offset: Int) throws {
        guard offset >= 0, offset + 8 <= count else { throw BinaryError.invalidOffset(offset) }
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { bytes in
            replaceSubrange(offset..<offset + 8, with: bytes)
        }
    }
}

func readData(url: URL, offset: UInt64, count: Int) throws -> Data {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    try handle.seek(toOffset: offset)
    let data = try handle.read(upToCount: count) ?? Data()
    guard data.count == count else { throw BinaryError.shortRead(url, count) }
    return data
}

func alignUp(_ value: UInt64, to alignment: UInt64) -> UInt64 {
    ((value + alignment - 1) / alignment) * alignment
}
