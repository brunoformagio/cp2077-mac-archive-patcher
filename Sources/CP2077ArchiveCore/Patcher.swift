import Foundation

public struct PatchSummary: Sendable {
    public let backupDirectory: URL
    public let patchedCount: Int
    public let insertedCount: Int
    public let replacedCount: Int
    public let targetArchive: URL
}

public struct HybridPatchSummary: Sendable {
    public let sourceArchive: URL
    public let officialPatches: [PatchSummary]
    public let looseArchive: URL?
    public let missingRecordCount: Int

    public var patchedExistingRecordCount: Int {
        officialPatches.reduce(0) { $0 + $1.patchedCount }
    }
}

public enum PatchStrategyKind: String, Sendable {
    case plugin
    case hybrid
    case officialOverride
    case aggressive
}

public struct HybridPatchPlan: Sendable {
    public let sourceArchive: URL
    public let totalRecordCount: Int
    public let existingRecordCount: Int
    public let missingRecordCount: Int
    public let affectedOfficialArchives: [URL]

    public var strategyKind: PatchStrategyKind {
        if existingRecordCount == 0 { return .plugin }
        if missingRecordCount == 0 { return .officialOverride }
        return .hybrid
    }
}

public struct RDARPatcher: Sendable {
    public let game: GameInstall

    public init(game: GameInstall) {
        self.game = game
    }

    public func patchAll(sourceArchive sourceURL: URL, targetArchive targetURL: URL) throws -> PatchSummary {
        let source = try RDARArchive.read(sourceURL)
        return try patch(source: source, targetURL: targetURL, requests: source.records.map {
            PatchRequest(label: "hash:\(String($0.nameHash, radix: 16).leftPadded(to: 16, with: "0"))", hash: $0.nameHash, sourceRecord: $0)
        })
    }

    public func patchPaths(sourceArchive sourceURL: URL, targetArchive targetURL: URL, paths: [String]) throws -> PatchSummary {
        let source = try RDARArchive.read(sourceURL)
        let requests = try paths.map { path in
            let hash = Hashes.fnv1a64Path(path)
            guard let record = source.record(hash: hash) else {
                throw RDARArchiveError.noTargetArchive(sourceURL)
            }
            return PatchRequest(label: path, hash: hash, sourceRecord: record)
        }
        return try patch(source: source, targetURL: targetURL, requests: requests)
    }

    public func patchHashes(sourceArchive sourceURL: URL, targetArchive targetURL: URL, hashes: [UInt64]) throws -> PatchSummary {
        let source = try RDARArchive.read(sourceURL)
        let requests = try hashes.map { hash in
            guard let record = source.record(hash: hash) else {
                throw RDARArchiveError.noTargetArchive(sourceURL)
            }
            return PatchRequest(label: "hash:\(String(hash, radix: 16).leftPadded(to: 16, with: "0"))", hash: hash, sourceRecord: record)
        }
        return try patch(source: source, targetURL: targetURL, requests: requests)
    }

    public func patchHybrid(sourceArchive sourceURL: URL) throws -> HybridPatchSummary {
        let (source, ownerByHash) = try resolveOwners(sourceArchive: sourceURL)
        let existing = source.records.filter { ownerByHash[$0.nameHash] != nil }
        let missing = source.records.filter { ownerByHash[$0.nameHash] == nil }

        var grouped: [URL: [UInt64]] = [:]
        for record in existing {
            if let owner = ownerByHash[record.nameHash] {
                grouped[owner, default: []].append(record.nameHash)
            }
        }

        var officialPatches: [PatchSummary] = []
        for (targetURL, hashes) in grouped.sorted(by: { $0.key.path < $1.key.path }) {
            officialPatches.append(try patchHashes(sourceArchive: sourceURL, targetArchive: targetURL, hashes: hashes))
        }

        let looseArchive = missing.isEmpty ? nil : try installLooseArchive(sourceURL)

        return HybridPatchSummary(
            sourceArchive: sourceURL,
            officialPatches: officialPatches,
            looseArchive: looseArchive,
            missingRecordCount: missing.count
        )
    }

    public func planHybrid(sourceArchive sourceURL: URL) throws -> HybridPatchPlan {
        let (source, ownerByHash) = try resolveOwners(sourceArchive: sourceURL)
        let affected = Set(ownerByHash.values)
        return HybridPatchPlan(
            sourceArchive: sourceURL,
            totalRecordCount: source.records.count,
            existingRecordCount: source.records.filter { ownerByHash[$0.nameHash] != nil }.count,
            missingRecordCount: source.records.filter { ownerByHash[$0.nameHash] == nil }.count,
            affectedOfficialArchives: affected.sorted { $0.path < $1.path }
        )
    }

    public func chooseTarget(sourceArchive: URL, explicitTarget: URL?) throws -> URL {
        if let explicitTarget { return explicitTarget }
        let source = try RDARArchive.read(sourceArchive)
        let sourceHashes = Set(source.records.map(\.nameHash))
        var best: (url: URL, count: Int)?
        for archiveURL in try game.officialMacArchives() {
            let archive = try RDARArchive.read(archiveURL)
            let count = archive.records.filter { sourceHashes.contains($0.nameHash) }.count
            if count > (best?.count ?? 0) {
                best = (archiveURL, count)
            }
        }
        guard let best, best.count > 0 else {
            throw RDARArchiveError.noTargetArchive(sourceArchive)
        }
        return best.url
    }

    private func installLooseArchive(_ sourceURL: URL) throws -> URL {
        let manager = FileManager.default
        try manager.createDirectory(at: game.managedLooseArchiveDirectory, withIntermediateDirectories: true)

        let baseName = sourceURL.deletingPathExtension().lastPathComponent
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9_-]+"#, with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_-"))
        let safeName = baseName.isEmpty ? "mod" : baseName
        var candidate = game.managedLooseArchiveDirectory.appending(path: "basegame_99_\(safeName).archive")
        var suffix = 2
        while manager.fileExists(atPath: candidate.path) {
            candidate = game.managedLooseArchiveDirectory.appending(path: "basegame_99_\(safeName)_\(suffix).archive")
            suffix += 1
        }
        try manager.copyItem(at: sourceURL, to: candidate)
        return candidate
    }

    private func resolveOwners(sourceArchive sourceURL: URL) throws -> (RDARArchive, [UInt64: URL]) {
        let source = try RDARArchive.read(sourceURL)
        let sourceHashes = Set(source.records.map(\.nameHash))
        var ownerByHash: [UInt64: URL] = [:]

        for archiveURL in try game.officialMacArchives() {
            let archive = try RDARArchive.read(archiveURL)
            let matches = archive.records.filter { sourceHashes.contains($0.nameHash) }
            for match in matches where ownerByHash[match.nameHash] == nil {
                ownerByHash[match.nameHash] = archiveURL
            }
        }

        return (source, ownerByHash)
    }

    private func patch(source: RDARArchive, targetURL: URL, requests: [PatchRequest]) throws -> PatchSummary {
        let target = try RDARArchive.read(targetURL)
        let targetByHash = Dictionary(uniqueKeysWithValues: target.records.map { ($0.nameHash, $0) })
        let backup = try BackupStore(game: game).createBackup(
            targetArchive: targetURL,
            sourceArchive: source.url,
            note: "before patching \(source.url.lastPathComponent)"
        )

        var seen = Set<UInt64>()
        let patches = try requests.map { request -> Patch in
            guard seen.insert(request.hash).inserted else {
                throw RDARArchiveError.duplicatePatch(request.hash)
            }
            let targetRecord = targetByHash[request.hash]
            if targetRecord == nil && request.sourceRecord.dependenciesStart != request.sourceRecord.dependenciesEnd {
                throw RDARArchiveError.unsupportedDependencyInsert(request.label)
            }
            return Patch(request: request, targetRecord: targetRecord)
        }

        let added = patches.filter { $0.targetRecord == nil }
        let newRecordBytes = added.count * 56
        let newSegmentBytes = patches.reduce(0) { $0 + $1.request.sourceRecord.segmentCount * 16 }
        var patchedIndex = Data(count: target.indexData.count + newRecordBytes + newSegmentBytes)

        var indexHeader = target.indexData[0..<target.recordsOffset]
        try indexHeader.writeUInt32LE(try target.indexData.uint32LE(at: 4) + UInt32(newRecordBytes + newSegmentBytes), at: 4)
        try indexHeader.writeUInt32LE(target.fileEntryCount + UInt32(added.count), at: 16)
        try indexHeader.writeUInt32LE(target.fileSegmentCount + UInt32(newSegmentBytes / 16), at: 20)
        patchedIndex.replaceSubrange(0..<target.recordsOffset, with: indexHeader)

        var recordMap = Dictionary(uniqueKeysWithValues: target.records.map { ($0.nameHash, $0.bytes) })
        for patch in added {
            recordMap[patch.request.hash] = patch.request.sourceRecord.bytes
        }

        let sortedRecords = recordMap.sorted { $0.key < $1.key }
        var recordOffsets: [UInt64: Int] = [:]
        var recordTableOffset = target.recordsOffset
        for (hash, bytes) in sortedRecords {
            patchedIndex.replaceSubrange(recordTableOffset..<recordTableOffset + 56, with: bytes)
            recordOffsets[hash] = recordTableOffset
            recordTableOffset += 56
        }

        let patchedSegmentsOffset = target.recordsOffset + sortedRecords.count * 56
        patchedIndex.replaceSubrange(
            patchedSegmentsOffset..<patchedSegmentsOffset + Int(target.fileSegmentCount) * 16,
            with: target.indexData[target.segmentsOffset..<target.dependenciesOffset]
        )
        let dependenciesStart = patchedSegmentsOffset + Int(target.fileSegmentCount) * 16 + newSegmentBytes
        patchedIndex.replaceSubrange(
            dependenciesStart..<dependenciesStart + (target.indexData.count - target.dependenciesOffset),
            with: target.indexData[target.dependenciesOffset..<target.indexData.count]
        )

        let targetHandle = try FileHandle(forUpdating: targetURL)
        let sourceHandle = try FileHandle(forReadingFrom: source.url)
        defer {
            try? targetHandle.close()
            try? sourceHandle.close()
        }

        let currentSize = try FileManager.default.attributesOfItem(atPath: targetURL.path)[.size] as? NSNumber
        var appendOffset = currentSize?.uint64Value ?? target.fileSize
        var appendedSegmentIndex = target.fileSegmentCount
        var appendedSegmentTableOffset = patchedSegmentsOffset + Int(target.fileSegmentCount) * 16

        for patch in patches {
            let newSegmentsStart = appendedSegmentIndex
            for i in 0..<patch.request.sourceRecord.segmentCount {
                let sourceSegment = source.segments[Int(patch.request.sourceRecord.segmentsStart) + i]
                try sourceHandle.seek(toOffset: sourceSegment.offset)
                let compressedData = try sourceHandle.read(upToCount: Int(sourceSegment.compressedSize)) ?? Data()
                guard compressedData.count == Int(sourceSegment.compressedSize) else {
                    throw BinaryError.shortRead(source.url, Int(sourceSegment.compressedSize))
                }

                try targetHandle.seek(toOffset: appendOffset)
                try targetHandle.write(contentsOf: compressedData)

                try patchedIndex.writeUInt64LE(appendOffset, at: appendedSegmentTableOffset)
                try patchedIndex.writeUInt32LE(sourceSegment.compressedSize, at: appendedSegmentTableOffset + 8)
                try patchedIndex.writeUInt32LE(sourceSegment.size, at: appendedSegmentTableOffset + 12)

                appendOffset += UInt64(sourceSegment.compressedSize)
                appendedSegmentIndex += 1
                appendedSegmentTableOffset += 16
            }

            guard let recordOffset = recordOffsets[patch.request.hash] else {
                fatalError("missing patched record offset")
            }
            try patchedIndex.writeUInt32LE(newSegmentsStart, at: recordOffset + 20)
            try patchedIndex.writeUInt32LE(appendedSegmentIndex, at: recordOffset + 24)
            patchedIndex.replaceSubrange(recordOffset + 36..<recordOffset + 56, with: patch.request.sourceRecord.sha1)
        }

        try patchedIndex.writeUInt64LE(Hashes.crc64(patchedIndex.subdata(in: 16..<patchedIndex.count)), at: 8)

        let newIndexPosition = alignUp(appendOffset, to: 4096)
        if newIndexPosition > appendOffset {
            try targetHandle.seek(toOffset: appendOffset)
            try targetHandle.write(contentsOf: Data(count: Int(newIndexPosition - appendOffset)))
        }
        try targetHandle.seek(toOffset: newIndexPosition)
        try targetHandle.write(contentsOf: patchedIndex)

        let indexEnd = newIndexPosition + UInt64(patchedIndex.count)
        let newFileSize = alignUp(indexEnd, to: 4096)
        if newFileSize > indexEnd {
            try targetHandle.seek(toOffset: indexEnd)
            try targetHandle.write(contentsOf: Data(count: Int(newFileSize - indexEnd)))
        }
        try targetHandle.truncate(atOffset: newFileSize)

        var header = target.header
        try header.writeUInt64LE(newIndexPosition, at: 8)
        try header.writeUInt32LE(UInt32(patchedIndex.count), at: 16)
        try header.writeUInt64LE(newFileSize, at: 32)
        try targetHandle.seek(toOffset: 0)
        try targetHandle.write(contentsOf: header)

        return PatchSummary(
            backupDirectory: backup,
            patchedCount: patches.count,
            insertedCount: added.count,
            replacedCount: patches.count - added.count,
            targetArchive: targetURL
        )
    }
}

private struct PatchRequest {
    let label: String
    let hash: UInt64
    let sourceRecord: RDARRecord
}

private struct Patch {
    let request: PatchRequest
    let targetRecord: RDARRecord?
}
