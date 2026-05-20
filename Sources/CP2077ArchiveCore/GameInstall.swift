import Foundation

public struct GameInstall: Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    public var macContentArchiveDirectory: URL {
        root.appending(path: "archive/Mac/content", directoryHint: .isDirectory)
    }

    public var macEP1ArchiveDirectory: URL {
        root.appending(path: "archive/Mac/ep1", directoryHint: .isDirectory)
    }

    public var patcherDirectory: URL {
        root.appending(path: "archive/Mac/_cp2077_mac_patcher", directoryHint: .isDirectory)
    }

    public var backupDirectory: URL {
        patcherDirectory.appending(path: "backups", directoryHint: .isDirectory)
    }

    public var managedLooseArchiveDirectory: URL {
        macContentArchiveDirectory
    }

    public func macArchives() throws -> [URL] {
        let manager = FileManager.default
        let dirs = [macContentArchiveDirectory, macEP1ArchiveDirectory]
        return try dirs.flatMap { dir -> [URL] in
            guard manager.fileExists(atPath: dir.path) else { return [] }
            return try manager.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ).filter { $0.pathExtension == "archive" }
        }.sorted { $0.path < $1.path }
    }

    public func officialMacArchives() throws -> [URL] {
        try macArchives().filter { url in
            let name = url.lastPathComponent
            return !name.hasPrefix("basegame_99_")
                && !url.path.contains("/_cp2077_mac_patcher/")
                && !url.path.contains("/_disabled_mod_tests/")
        }
    }

    public static func defaultCandidates() -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            home.appending(path: "Library/Application Support/Steam/steamapps/common/Cyberpunk 2077", directoryHint: .isDirectory),
            home.appending(path: "Library/Application Support/GOG.com/Galaxy/Applications/55230414410511377", directoryHint: .isDirectory)
        ]
    }

    public static func detectInstalledGame() -> URL? {
        defaultCandidates().first { candidate in
            FileManager.default.fileExists(atPath: candidate.appending(path: "Cyberpunk2077.app").path)
        }
    }
}
