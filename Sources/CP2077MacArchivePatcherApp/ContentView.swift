import AppKit
import CP2077ArchiveCore
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var model = AppModel()
    @State private var isDropTargeted = false
    @State private var showPatchConfirmation = false
    @State private var showBackupManager = false
    @State private var acknowledgedOfficialOverride = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ZStack {
                HSplitView {
                    leftPane
                        .frame(minWidth: 610)
                    rightPane
                        .frame(minWidth: 320)
                }
                if model.isScanning {
                    scanningOverlay
                }
            }
            Divider()
            footer
        }
        .onAppear {
            model.autoDetectGame()
            model.refreshBackups()
        }
        .alert("Patch Error", isPresented: Binding(
            get: { model.lastError != nil },
            set: { if !$0 { model.lastError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.lastError ?? "")
        }
        .alert("Duplicate archive", isPresented: Binding(
            get: { model.duplicateWarning != nil },
            set: { if !$0 { model.duplicateWarning = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.duplicateWarning ?? "")
        }
        .sheet(isPresented: $showPatchConfirmation) {
            PatchConfirmationSheet(
                enabledCount: model.enabledMods.count,
                requiresOfficialPatch: model.enabledModsRequireOfficialPatch,
                acknowledgedOfficialOverride: $acknowledgedOfficialOverride,
                onCancel: {
                    showPatchConfirmation = false
                },
                onConfirm: {
                    showPatchConfirmation = false
                    model.patchEnabledMods()
                }
            )
        }
        .sheet(isPresented: $showBackupManager) {
            BackupManagerSheet(
                backups: model.backups,
                onRefresh: model.refreshBackups,
                onRestore: model.restoreBackup,
                onErase: model.eraseBackup,
                onClose: {
                    showBackupManager = false
                }
            )
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(nsImage: NSImage(named: "AppIcon") ?? NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 4) {
                    Text("CP2077 Mac Archive Patcher v1.0")
                        .font(.title2.bold())
                    Text("Native macOS, archive-only PC mods")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                statusPill
            }

            HStack(spacing: 8) {
                TextField("Cyberpunk 2077 game folder", text: $model.gamePath)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { model.replanAll() }
                Button("Auto-detect") { model.autoDetectGame() }
                Button("Choose...") { model.chooseGameFolder() }
            }
        }
        .padding(16)
    }

    private var statusPill: some View {
        Text(model.hasValidGamePath ? "Verified" : "Not found")
            .font(.caption.bold())
            .foregroundStyle(model.hasValidGamePath ? .green : .orange)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background((model.hasValidGamePath ? Color.green : Color.orange).opacity(0.12))
            .clipShape(Capsule())
    }

    private var leftPane: some View {
        VStack(spacing: 12) {
            dropZone
            warnings
            modList
        }
        .padding(16)
    }

    private var dropZone: some View {
        VStack(spacing: 8) {
            Image(systemName: "archivebox")
                .font(.system(size: 34))
                .foregroundStyle(.secondary)
            Text("Drop PC .archive mods here")
                .font(.headline)
            Text("Only archive-only mods are supported. redscript, CET, REDmod, ArchiveXL, TweakXL, DLLs, and scripts are out of scope.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
        .background(isDropTargeted ? Color.accentColor.opacity(0.14) : Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [6]))
        )
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
    }

    private var warnings: some View {
        VStack(spacing: 8) {
            if model.mods.contains(where: { $0.strategy == .hybrid || $0.strategy == .officialOverride }) {
                WarningBanner(
                    title: "Some mods will override official game records",
                    message: "Loose archives cannot replace records that already exist in the native Mac game. Hybrid and Override methods write those records into official archives after creating backups. A bad mod can still make the game crash until you restore the backup."
                )
            }
            if model.mods.contains(where: { $0.strategy == .aggressive }) {
                WarningBanner(
                    title: "Aggressive mode",
                    message: "Aggressive mode rewrites more of an official archive and should only be used as a fallback."
                )
            }
        }
    }

    private var modList: some View {
        List {
            ForEach($model.mods) { $mod in
                ModRow(mod: $mod) {
                    model.removeMod(id: mod.id)
                }
            }
            .onDelete(perform: model.removeMods)
        }
        .listStyle(.inset)
    }

    private var rightPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Progress")
                .font(.headline)
            ProgressView(value: model.progress)
            Text(model.progressLabel)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Button("Backups") {
                    model.refreshBackups()
                    showBackupManager = true
                }
                    .disabled(!model.hasBackups)
                Spacer()
            }

            Divider()

            Text("Log")
                .font(.headline)
            ScrollView {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(Array(model.logLines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .background(Color.black.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .padding(16)
    }

    private var footer: some View {
        HStack {
            Text("\(model.enabledMods.count) enabled mod\(model.enabledMods.count == 1 ? "" : "s")")
                .foregroundStyle(.secondary)
            Spacer()
            Button("Clear All") { model.clearMods() }
                .disabled(model.mods.isEmpty || model.isWorking)
            Button("Re-scan") { model.rescanWithOverlay() }
                .disabled(!model.hasValidGamePath || model.isWorking || model.isScanning)
            Button {
                acknowledgedOfficialOverride = false
                showPatchConfirmation = true
            } label: {
                Label("Patch Enabled Mods", systemImage: "wrench.and.screwdriver")
                    .fontWeight(.semibold)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!model.canPatch)
        }
        .padding(16)
    }

    private var scanningOverlay: some View {
        ZStack {
            Color.black.opacity(0.18)
                .ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.large)
                Text("Scanning...")
                    .font(.headline)
                Text("Reading archive records and checking which resources already exist in the Mac game archives.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }
            .padding(24)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .shadow(radius: 18)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                Task { @MainActor in
                    model.addModURLs([url])
                }
            }
        }
        return true
    }
}

struct WarningBanner: View {
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.bold())
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(10)
        .background(Color.orange.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct ModRow: View {
    @Binding var mod: ModItem
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Toggle("", isOn: $mod.enabled)
                    .labelsHidden()
                VStack(alignment: .leading, spacing: 2) {
                    Text(mod.displayName)
                        .font(.headline)
                    Text(mod.url.deletingLastPathComponent().path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                strategyBadge
                Button(role: .destructive, action: onRemove) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Remove this mod from the list")
            }
            HStack(spacing: 14) {
                StatLabel(title: "Records", value: "\(mod.recordCount)")
                StatLabel(title: "Official", value: "\(mod.existingCount)")
                StatLabel(title: "Loose", value: "\(mod.missingCount)")
                Text(mod.status.rawValue)
                    .font(.caption.bold())
                    .foregroundStyle(mod.status == .failed ? .red : .secondary)
                Spacer()
            }
            if !mod.message.isEmpty {
                Text(mod.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if mod.requiresOfficialPatch {
                Text("Backups will be created for affected official archives.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 6)
    }

    private var strategyBadge: some View {
        Text(mod.strategyLabel)
            .font(.caption.bold())
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }

    private var color: Color {
        switch mod.strategy {
        case .plugin: .green
        case .hybrid: .blue
        case .officialOverride: .orange
        case .aggressive: .red
        case nil: .secondary
        }
    }
}

struct PatchConfirmationSheet: View {
    let enabledCount: Int
    let requiresOfficialPatch: Bool
    @Binding var acknowledgedOfficialOverride: Bool
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: requiresOfficialPatch ? "exclamationmark.triangle.fill" : "checkmark.seal.fill")
                    .font(.title2)
                    .foregroundStyle(requiresOfficialPatch ? .orange : .green)
                Text("Confirm Patch Run")
                    .font(.title3.bold())
            }

            Text("This will patch \(enabledCount) enabled mod\(enabledCount == 1 ? "" : "s").")
                .foregroundStyle(.secondary)

            if requiresOfficialPatch {
                WarningBanner(
                    title: "Official archive records will be overwritten",
                    message: "The app will create backups first, then replace matching records inside official Mac archives. If a mod is incompatible, the game can crash until you restore those backups."
                )
                Toggle("I'm aware that this overrides official game archive records, and the game can crash.", isOn: $acknowledgedOfficialOverride)
                    .toggleStyle(.checkbox)
            } else {
                Text("These enabled mods can be installed as loose plugin archives and removed later without restoring official game files.")
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                Button("Patch Enabled Mods", action: onConfirm)
                    .buttonStyle(.borderedProminent)
                    .disabled(requiresOfficialPatch && !acknowledgedOfficialOverride)
            }
        }
        .padding(20)
        .frame(width: 520)
    }
}

struct BackupManagerSheet: View {
    let backups: [BackupItem]
    let onRefresh: () -> Void
    let onRestore: (String) -> Void
    let onErase: (String) -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Backups")
                        .font(.title3.bold())
                    Text("Restore official game archives or delete backups you no longer need.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    onRefresh()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                Button("Close", action: onClose)
            }

            if backups.isEmpty {
                ContentUnavailableView(
                    "No Backups",
                    systemImage: "externaldrive.badge.xmark",
                    description: Text("Backups are created only when a mod changes official game archive records.")
                )
                .frame(maxWidth: .infinity, minHeight: 260)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(backups) { backup in
                            BackupRow(
                                backup: backup,
                                onRestore: { onRestore(backup.id) },
                                onErase: { onErase(backup.id) }
                            )
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(minHeight: 300)
            }
        }
        .padding(20)
        .frame(width: 760, height: 520)
        .onAppear(perform: onRefresh)
    }
}

struct BackupRow: View {
    let backup: BackupItem
    let onRestore: () -> Void
    let onErase: () -> Void

    @State private var confirmRestore = false
    @State private var confirmErase = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "archivebox.fill")
                    .foregroundStyle(.secondary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 5) {
                    Text(backup.fileName)
                        .font(.headline)
                    Text(backup.targetPath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    HStack(spacing: 14) {
                        StatLabel(title: "Size", value: Self.sizeFormatter.string(fromByteCount: Int64(backup.originalSize)))
                        StatLabel(title: "Date", value: formattedDate)
                        StatLabel(title: "From", value: backup.sourceName)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 8) {
                    Button {
                        confirmRestore = true
                    } label: {
                        Label("Restore Game File", systemImage: "arrow.uturn.backward")
                    }
                    .buttonStyle(.borderedProminent)

                    Button(role: .destructive) {
                        confirmErase = true
                    } label: {
                        Label("Erase Backup", systemImage: "trash")
                    }
                }
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .alert("Restore game file?", isPresented: $confirmRestore) {
            Button("Cancel", role: .cancel) {}
            Button("Restore", role: .destructive, action: onRestore)
        } message: {
            Text("This will replace the current \(backup.fileName) in the game folder with this backup.")
        }
        .alert("Erase backup?", isPresented: $confirmErase) {
            Button("Cancel", role: .cancel) {}
            Button("Erase Backup", role: .destructive, action: onErase)
        } message: {
            Text("This deletes only the backup copy. It does not change the current game file.")
        }
    }

    private var formattedDate: String {
        guard let createdAt = backup.createdAt else { return backup.id }
        return Self.dateFormatter.string(from: createdAt)
    }

    private static let sizeFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter
    }()

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

struct StatLabel: View {
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 3) {
            Text(title)
                .foregroundStyle(.secondary)
            Text(value)
                .fontWeight(.semibold)
        }
        .font(.caption)
    }
}
