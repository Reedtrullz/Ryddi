import Foundation

public final class ScanHistoryStore: @unchecked Sendable {
    private let root: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(root: URL? = nil) {
        self.root = root ?? Self.defaultRoot()
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
    }

    public static func defaultRoot() -> URL {
        if let override = ProcessInfo.processInfo.environment["RYDDI_SCAN_HISTORY_ROOT"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true).standardizedFileURL
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Ryddi/ScanHistory")
    }

    public func save(overview: ScanOverview) throws -> URL {
        try save(snapshot: FindingAnalytics.snapshot(from: overview))
    }

    @discardableResult
    public func save(snapshot: ScanSnapshot) throws -> URL {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
        let url = root.appendingPathComponent("scan-\(timestamp(snapshot.createdAt))-\(snapshot.id).json")
        try encoder.encode(snapshot).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return url
    }

    public func retentionPlan(keepRecent: Int, now: Date = Date()) -> AuditPrunePlan {
        let files = historyFiles()
        let sorted = files.sorted { lhs, rhs in
            if lhs.snapshot.createdAt == rhs.snapshot.createdAt {
                return lhs.url.lastPathComponent > rhs.url.lastPathComponent
            }
            return lhs.snapshot.createdAt > rhs.snapshot.createdAt
        }
        let candidates = sorted.dropFirst(max(0, keepRecent)).compactMap { item -> AuditPruneCandidate? in
            guard let identity = try? FilesystemIdentity.capture(at: item.url),
                  identity.isRegularFile,
                  !identity.isSymbolicLink,
                  !identity.isDirectory,
                  !identity.isPackage,
                  !identity.isVolume else { return nil }
            return AuditPruneCandidate(
                path: item.url.path,
                kind: "scan-history",
                bytes: identity.fileSize ?? 0,
                modifiedAt: identity.modificationDate,
                filesystemIdentity: identity
            )
        }
        return AuditPrunePlan(
            id: UUID().uuidString,
            createdAt: now,
            rootPath: root.path,
            policy: AuditRetentionPolicy(olderThanDays: 0, keepRecent: keepRecent),
            candidates: candidates,
            skippedUnknownPaths: [],
            skippedSymlinkPaths: historySymlinks().map(\.path).sorted()
        )
    }

    public func prune(
        plan: AuditPrunePlan,
        dryRun: Bool = true,
        trasher: any Trashing = FileManagerTrasher()
    ) -> AuditPruneReceipt {
        guard !dryRun else {
            return AuditPruneReceipt(dryRun: true, planID: plan.id, deletedCount: 0, deletedBytes: 0, errors: [])
        }
        guard URL(fileURLWithPath: plan.rootPath, isDirectory: true).standardizedFileURL == root.standardizedFileURL else {
            return AuditPruneReceipt(dryRun: false, planID: plan.id, deletedCount: 0, deletedBytes: 0, errors: ["Scan history plan root does not match this store."])
        }

        var trashed: [String] = []
        var bytes: Int64 = 0
        var errors: [String] = []
        for candidate in plan.candidates {
            let url = URL(fileURLWithPath: candidate.path).standardizedFileURL
            let filename = url.lastPathComponent
            guard url.deletingLastPathComponent() == root.standardizedFileURL,
                  filename.hasPrefix("scan-"),
                  filename.hasSuffix(".json"),
                  candidate.kind == "scan-history" else {
                errors.append("Skipped \(filename): path is not a known scan-history file.")
                continue
            }
            guard let planned = candidate.filesystemIdentity,
                  let current = try? FilesystemIdentity.capture(at: url),
                  current == planned,
                  current.isRegularFile,
                  !current.isSymbolicLink else {
                errors.append("Skipped \(filename): filesystem identity changed after review.")
                continue
            }
            do {
                _ = try trasher.trashItem(at: url)
                trashed.append(filename)
                bytes += candidate.bytes
            } catch {
                errors.append("Skipped \(filename): \(error.localizedDescription)")
            }
        }
        return AuditPruneReceipt(
            dryRun: false,
            planID: plan.id,
            deletedCount: trashed.count,
            deletedBytes: bytes,
            deletedFileIDs: trashed,
            errors: errors
        )
    }

    public func recent(limit: Int = 10) -> [ScanSnapshot] {
        historyFiles()
            .sorted { lhs, rhs in
                if lhs.snapshot.createdAt == rhs.snapshot.createdAt {
                    return lhs.url.lastPathComponent > rhs.url.lastPathComponent
                }
                return lhs.snapshot.createdAt > rhs.snapshot.createdAt
            }
            .prefix(limit)
            .map(\.snapshot)
    }

    public func snapshot(id: String) -> ScanSnapshot? {
        recent(limit: Int.max).first { $0.id == id }
    }

    public func latestGrowthDeltas(group: GrowthGroup = .category, limit: Int = 12) -> [BucketGrowthDelta] {
        let snapshots = recent(limit: 2)
        guard snapshots.count == 2 else { return [] }
        return Array(
            FindingAnalytics.growthDeltas(previous: snapshots[1], current: snapshots[0], group: group)
                .prefix(limit)
        )
    }

    private func timestamp(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
            .replacingOccurrences(of: ":", with: "-")
    }

    private func historyFiles() -> [(url: URL, snapshot: ScanSnapshot)] {
        guard let files = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isSymbolicLinkKey]) else {
            return []
        }
        return files.compactMap { url in
            guard url.lastPathComponent.hasPrefix("scan-"), url.pathExtension == "json",
                  (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true,
                  let data = try? Data(contentsOf: url),
                  let snapshot = try? decoder.decode(ScanSnapshot.self, from: data) else { return nil }
            return (url.standardizedFileURL, snapshot)
        }
    }

    private func historySymlinks() -> [URL] {
        guard let files = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isSymbolicLinkKey]) else {
            return []
        }
        return files.filter { url in
            url.lastPathComponent.hasPrefix("scan-")
                && url.pathExtension == "json"
                && (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
        }
    }
}
