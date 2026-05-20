import AppKit
import CP2077ArchiveCore
import Foundation
import SwiftUI

enum ModStatus: String {
    case pending = "Pending"
    case planned = "Planned"
    case patched = "Patched"
    case failed = "Failed"
}

struct ModItem: Identifiable {
    let id = UUID()
    let url: URL
    var enabled = true
    var recordCount = 0
    var existingCount = 0
    var missingCount = 0
    var affectedArchives: [URL] = []
    var strategy: PatchStrategyKind?
    var status: ModStatus = .pending
    var message = ""

    var displayName: String {
        url.lastPathComponent
    }

    var strategyLabel: String {
        switch strategy {
        case .plugin: "Plugin method"
        case .hybrid: "Hybrid method"
        case .officialOverride: "Override method"
        case .aggressive: "Aggressive method"
        case nil: "Unknown"
        }
    }

    var requiresOfficialPatch: Bool {
        existingCount > 0
    }
}

struct BackupItem: Identifiable {
    let id: String
    let directory: URL
    let targetArchive: URL
    let sourceArchive: URL?
    let originalSize: UInt64
    let createdAt: Date?
    let note: String

    var fileName: String {
        targetArchive.lastPathComponent
    }

    var targetPath: String {
        targetArchive.path
    }

    var sourceName: String {
        sourceArchive?.lastPathComponent ?? "Unknown source"
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var gamePath = ""
    @Published var mods: [ModItem] = []
    @Published var logLines: [String] = []
    @Published var isWorking = false
    @Published var isScanning = false
    @Published var progress = 0.0
    @Published var progressLabel = "Idle"
    @Published var lastError: String?
    @Published var duplicateWarning: String?
    @Published var backups: [BackupItem] = []

    var gameURL: URL? {
        gamePath.isEmpty ? nil : URL(fileURLWithPath: gamePath)
    }

    var hasValidGamePath: Bool {
        guard let gameURL else { return false }
        return FileManager.default.fileExists(atPath: gameURL.appendingPathComponent("Cyberpunk2077.app").path)
            && FileManager.default.fileExists(atPath: gameURL.appendingPathComponent("archive/Mac/content").path)
    }

    var enabledMods: [ModItem] {
        mods.filter(\.enabled)
    }

    var enabledModsRequireOfficialPatch: Bool {
        enabledMods.contains(where: \.requiresOfficialPatch)
    }

    var hasBackups: Bool {
        !backups.isEmpty || backupsExistOnDisk()
    }

    var canPatch: Bool {
        hasValidGamePath && !enabledMods.isEmpty && !isWorking
    }

    func autoDetectGame() {
        if let detected = GameInstall.detectInstalledGame() {
            gamePath = detected.path
            appendLog("Detected game: \(detected.path)")
            replanAll()
        } else {
            lastError = "Could not auto-detect Cyberpunk 2077. Choose the game folder manually."
            appendLog("Auto-detect failed")
        }
    }

    func chooseGameFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose your Cyberpunk 2077 game folder"
        if panel.runModal() == .OK, let url = panel.url {
            gamePath = url.path
            appendLog("Selected game: \(url.path)")
            replanAll()
        }
    }

    func addModURLs(_ urls: [URL]) {
        var added = false
        var duplicates: [String] = []
        for url in urls where url.pathExtension.lowercased() == "archive" {
            guard !mods.contains(where: { $0.url.standardizedFileURL == url.standardizedFileURL }) else {
                duplicates.append(url.lastPathComponent)
                continue
            }
            mods.append(ModItem(url: url))
            appendLog("Added mod: \(url.lastPathComponent)")
            added = true
        }
        if !duplicates.isEmpty {
            let names = duplicates.joined(separator: ", ")
            duplicateWarning = "Already in the list: \(names)"
            appendLog("Ignored duplicate mod drop: \(names)")
        }
        if added {
            replanAll()
        }
    }

    func removeMods(at offsets: IndexSet) {
        mods.remove(atOffsets: offsets)
    }

    func removeMod(id: UUID) {
        mods.removeAll { $0.id == id }
    }

    func clearMods() {
        mods.removeAll()
        progress = 0
        progressLabel = "Idle"
        appendLog("Cleared mod list")
    }

    func rescanWithOverlay() {
        guard hasValidGamePath else { return }
        isScanning = true
        progressLabel = "Scanning..."
        Task {
            try? await Task.sleep(nanoseconds: 80_000_000)
            replanAll()
            isScanning = false
            progressLabel = "Scan complete"
        }
    }

    func replanAll() {
        guard hasValidGamePath, let gameURL else { return }
        let patcher = RDARPatcher(game: GameInstall(root: gameURL))
        for index in mods.indices {
            do {
                let scan = try ModScanner.scan(url: mods[index].url)
                let plan = try patcher.planHybrid(sourceArchive: mods[index].url)
                mods[index].recordCount = scan.archive.records.count
                mods[index].existingCount = plan.existingRecordCount
                mods[index].missingCount = plan.missingRecordCount
                mods[index].affectedArchives = plan.affectedOfficialArchives
                mods[index].strategy = plan.strategyKind
                mods[index].status = .planned
                mods[index].message = "\(plan.existingRecordCount) official overrides, \(plan.missingRecordCount) loose plugin records"
            } catch {
                mods[index].status = .failed
                mods[index].message = "\(error)"
            }
        }
    }

    func patchEnabledMods() {
        guard canPatch, let gameURL else { return }
        isWorking = true
        progress = 0
        progressLabel = "Preparing"
        lastError = nil
        appendLog("Starting patch run")

        let enabledIDs = enabledMods.map(\.id)
        let total = max(enabledIDs.count, 1)

        Task {
            let patcher = RDARPatcher(game: GameInstall(root: gameURL))
            for (step, id) in enabledIDs.enumerated() {
                guard let index = mods.firstIndex(where: { $0.id == id }) else { continue }
                let mod = mods[index]
                progress = Double(step) / Double(total)
                progressLabel = "Patching \(mod.displayName)"
                appendLog("Patching \(mod.displayName) with hybrid strategy")
                do {
                    let summary = try patcher.patchHybrid(sourceArchive: mod.url)
                    mods[index].status = .patched
                    mods[index].message = "\(summary.patchedExistingRecordCount) official records, \(summary.missingRecordCount) loose records"
                    if let loose = summary.looseArchive {
                        appendLog("Installed loose archive: \(loose.lastPathComponent)")
                    }
                    for official in summary.officialPatches {
                        appendLog("Patched \(official.targetArchive.lastPathComponent), backup: \(official.backupDirectory.lastPathComponent)")
                    }
                } catch {
                    mods[index].status = .failed
                    mods[index].message = "\(error)"
                    lastError = "\(error)"
                    appendLog("Failed \(mod.displayName): \(error)")
                    break
                }
            }
            progress = 1
            progressLabel = lastError == nil ? "Complete" : "Stopped"
            isWorking = false
            appendLog("Patch run finished! ✅ You can play the game now.")
            refreshBackups()
            replanAll()
        }
    }

    func refreshBackups() {
        guard let gameURL else {
            backups = []
            return
        }

        let backupDirectory = GameInstall(root: gameURL).backupDirectory
        let manager = FileManager.default
        guard let directories = try? manager.contentsOfDirectory(
            at: backupDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            backups = []
            return
        }

        let decoder = JSONDecoder()
        let formatter = ISO8601DateFormatter()
        backups = directories.compactMap { directory in
            guard directory.hasDirectoryPath else { return nil }
            let manifestURL = directory.appending(path: "manifest.json")
            guard let data = try? Data(contentsOf: manifestURL),
                  let manifest = try? decoder.decode(BackupManifest.self, from: data) else {
                return nil
            }
            return BackupItem(
                id: manifest.id,
                directory: directory,
                targetArchive: URL(fileURLWithPath: manifest.targetArchive),
                sourceArchive: manifest.sourceArchive.map { URL(fileURLWithPath: $0) },
                originalSize: manifest.originalSize,
                createdAt: formatter.date(from: manifest.createdAt),
                note: manifest.note
            )
        }
        .sorted { lhs, rhs in
            switch (lhs.createdAt, rhs.createdAt) {
            case let (left?, right?):
                return left > right
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                return lhs.id > rhs.id
            }
        }
    }

    func restoreBackup(id: String) {
        guard let gameURL, let backup = backups.first(where: { $0.id == id }) else { return }
        do {
            let restored = try BackupStore(game: GameInstall(root: gameURL)).restore(backupDirectory: backup.directory)
            appendLog("Restored game file from backup: \(restored.lastPathComponent)")
            progressLabel = "Restored \(restored.lastPathComponent)"
        } catch {
            lastError = "Could not restore backup: \(error)"
            appendLog("Restore failed: \(error)")
        }
    }

    func eraseBackup(id: String) {
        guard let backup = backups.first(where: { $0.id == id }) else { return }
        do {
            try FileManager.default.removeItem(at: backup.directory)
            appendLog("Erased backup: \(backup.fileName) (\(backup.id))")
            refreshBackups()
        } catch {
            lastError = "Could not erase backup: \(error)"
            appendLog("Erase backup failed: \(error)")
        }
    }

    private func backupsExistOnDisk() -> Bool {
        guard let gameURL else { return false }
        let backupDirectory = GameInstall(root: gameURL).backupDirectory
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: backupDirectory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return false
        }
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: backupDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        return !contents.isEmpty
    }

    func appendLog(_ line: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        logLines.append("[\(timestamp)] \(line)")
    }
}
