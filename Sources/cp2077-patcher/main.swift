import CP2077ArchiveCore
import Foundation

enum CLIError: Error, CustomStringConvertible {
    case usage(String)
    case missingValue(String)

    var description: String {
        switch self {
        case let .usage(message): return message
        case let .missingValue(flag): return "missing value for \(flag)"
        }
    }
}

@main
struct CP2077PatcherCLI {
    static func main() {
        do {
            try run()
        } catch {
            fputs("error: \(error)\n", stderr)
            exit(1)
        }
    }

    static func run() throws {
        var args = Array(CommandLine.arguments.dropFirst())
        guard let command = args.first else {
            printUsage()
            return
        }
        args.removeFirst()

        switch command {
        case "detect":
            try detect(args)
        case "scan":
            try scan(args)
        case "verify":
            try verify(args)
        case "patch":
            try patch(args)
        case "restore":
            try restore(args)
        case "help", "--help", "-h":
            printUsage()
        default:
            throw CLIError.usage("unknown command: \(command)")
        }
    }

    static func scan(_ args: [String]) throws {
        guard !args.isEmpty else { throw CLIError.usage("usage: cp2077-patcher scan MOD.archive [...]") }
        for arg in args {
            let url = URL(fileURLWithPath: arg)
            let scan = try ModScanner.scan(url: url)
            let archive = scan.archive
            print("\n\(url.path)")
            print("  records=\(archive.fileEntryCount) segments=\(archive.fileSegmentCount) deps=\(archive.dependencyCount)")
            print("  crcMatch=\(archive.storedCRC == archive.computedCRC)")
            print("  archiveOnlyCandidate=\(scan.likelyArchiveOnly)")
            for note in scan.notes {
                print("  note: \(note)")
            }
        }
    }

    static func detect(_ args: [String]) throws {
        if let detected = GameInstall.detectInstalledGame() {
            print(detected.path)
        } else {
            throw CLIError.usage("could not detect Cyberpunk 2077. Pass --game explicitly.")
        }
    }

    static func verify(_ args: [String]) throws {
        let options = try Options(args)
        guard let gamePath = options.value("--game") else {
            throw CLIError.usage("usage: cp2077-patcher verify --game GAME_DIR")
        }
        let game = GameInstall(root: URL(fileURLWithPath: gamePath))
        for archiveURL in try game.macArchives() {
            let archive = try RDARArchive.read(archiveURL)
            let ok = archive.storedCRC == archive.computedCRC
                && archive.indexPosition % 4096 == 0
                && archive.fileSize % 4096 == 0
            print("\(ok ? "OK  " : "BAD ") \(archiveURL.lastPathComponent) entries=\(archive.fileEntryCount) segments=\(archive.fileSegmentCount)")
        }
    }

    static func patch(_ args: [String]) throws {
        let options = try Options(args)
        guard let gamePath = options.value("--game") else {
            throw CLIError.usage("usage: cp2077-patcher patch --game GAME_DIR [--strategy hybrid|aggressive] [--target TARGET.archive] --mods MOD.archive [...]")
        }
        let modPaths = options.values(after: "--mods")
        guard !modPaths.isEmpty else {
            throw CLIError.usage("usage: cp2077-patcher patch --game GAME_DIR [--strategy hybrid|aggressive] [--target TARGET.archive] --mods MOD.archive [...]")
        }

        let game = GameInstall(root: URL(fileURLWithPath: gamePath))
        let patcher = RDARPatcher(game: game)
        let explicitTarget = options.value("--target").map { URL(fileURLWithPath: $0) }
        let strategy = options.value("--strategy") ?? "hybrid"

        for modPath in modPaths {
            let modURL = URL(fileURLWithPath: modPath)
            switch strategy {
            case "hybrid":
                if explicitTarget != nil {
                    print("warning: --target is ignored by --strategy hybrid")
                }
                let summary = try patcher.patchHybrid(sourceArchive: modURL)
                print("hybrid patched \(modURL.lastPathComponent)")
                print("  officialOverrideRecords=\(summary.patchedExistingRecordCount)")
                print("  loosePluginRecords=\(summary.missingRecordCount)")
                if let looseArchive = summary.looseArchive {
                    print("  looseArchive=\(looseArchive.path)")
                }
                for official in summary.officialPatches {
                    print("  officialArchive=\(official.targetArchive.path)")
                    print("    records=\(official.patchedCount) backup=\(official.backupDirectory.path)")
                }
            case "aggressive":
                let target = try patcher.chooseTarget(sourceArchive: modURL, explicitTarget: explicitTarget)
                let summary = try patcher.patchAll(sourceArchive: modURL, targetArchive: target)
                print("aggressively patched \(modURL.lastPathComponent) -> \(target.lastPathComponent)")
                print("  records=\(summary.patchedCount) inserted=\(summary.insertedCount) replaced=\(summary.replacedCount)")
                print("  backup=\(summary.backupDirectory.path)")
            default:
                throw CLIError.usage("unknown strategy: \(strategy)")
            }
        }
    }

    static func restore(_ args: [String]) throws {
        let options = try Options(args)
        guard let gamePath = options.value("--game") else {
            throw CLIError.usage("usage: cp2077-patcher restore --game GAME_DIR [--backup BACKUP_DIR | --latest]")
        }
        let store = BackupStore(game: GameInstall(root: URL(fileURLWithPath: gamePath)))
        let restored: URL
        if let backupPath = options.value("--backup") {
            restored = try store.restore(backupDirectory: URL(fileURLWithPath: backupPath))
        } else {
            restored = try store.restoreLatest()
        }
        print("restored \(restored.path)")
    }

    static func printUsage() {
        print("""
        cp2077-patcher

        Commands:
          scan MOD.archive [...]
          detect
          verify --game GAME_DIR
          patch --game GAME_DIR [--strategy hybrid|aggressive] [--target TARGET.archive] --mods MOD.archive [...]
          restore --game GAME_DIR [--backup BACKUP_DIR | --latest]

        Scope:
          Native macOS Cyberpunk 2077, archive-only PC .archive mods.
        """)
    }
}

struct Options {
    let args: [String]

    init(_ args: [String]) throws {
        self.args = args
    }

    func value(_ flag: String) -> String? {
        guard let index = args.firstIndex(of: flag), index + 1 < args.count else { return nil }
        let value = args[index + 1]
        return value.hasPrefix("--") ? nil : value
    }

    func values(after flag: String) -> [String] {
        guard let index = args.firstIndex(of: flag) else { return [] }
        var values: [String] = []
        for arg in args[(index + 1)...] {
            if arg.hasPrefix("--") { break }
            values.append(arg)
        }
        return values
    }
}
