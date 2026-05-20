import Foundation

public struct ModScan: Sendable {
    public let archive: RDARArchive
    public let likelyArchiveOnly: Bool
    public let notes: [String]
}

public enum ModScanner {
    public static func scan(url: URL) throws -> ModScan {
        let archive = try RDARArchive.read(url)
        var notes: [String] = []
        if archive.dependencyCount > 0 {
            notes.append("archive index has dependency entries; insertion of dependency-bearing new records is not supported yet")
        }
        if archive.records.isEmpty {
            notes.append("archive has no records")
        }
        return ModScan(archive: archive, likelyArchiveOnly: true, notes: notes)
    }
}

