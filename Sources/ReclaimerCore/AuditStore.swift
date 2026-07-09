import Darwin
import Foundation

public enum AuditStoreScanSessionWarningKind: String, Codable, Hashable, Sendable {
    case unreadableScanSession
}

public struct AuditStoreScanSessionWarning: Codable, Hashable, Sendable {
    public let path: String
    public let kind: AuditStoreScanSessionWarningKind
    public let message: String

    public init(path: String, kind: AuditStoreScanSessionWarningKind, message: String) {
        self.path = path
        self.kind = kind
        self.message = message
    }
}

public struct AuditStoreScanSessionListResult: Codable, Hashable, Sendable {
    public let sessions: [ScanSession]
    public let warnings: [AuditStoreScanSessionWarning]

    public init(sessions: [ScanSession], warnings: [AuditStoreScanSessionWarning]) {
        self.sessions = sessions
        self.warnings = warnings
    }
}

public final class AuditStore: @unchecked Sendable {
    private static let scanSessionPrefix = "scan-session-v1-"
    private static let legacyScanSessionPrefix = "scan-session-"

    private struct AuditFileRecord {
        let url: URL
        let kind: String?
        let bytes: Int64
        let modifiedAt: Date?
        let isSymlink: Bool
        let filesystemIdentity: FilesystemIdentity?

        var isEligibleRegularFile: Bool {
            guard let filesystemIdentity else { return false }
            return filesystemIdentity.isRegularFile
                && !filesystemIdentity.isDirectory
                && !filesystemIdentity.isSymbolicLink
                && !filesystemIdentity.isPackage
                && !filesystemIdentity.isVolume
        }
    }

    public enum RemoteAuditQueryError: Error, LocalizedError, Equatable {
        case ambiguousSavedTargetQuery(String)

        public var errorDescription: String? {
            switch self {
            case let .ambiguousSavedTargetQuery(query):
                return "saved remote target query is ambiguous for \(query)"
            }
        }
    }

    private let root: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(root: URL = AuditStore.defaultRoot()) {
        self.root = root
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
    }

    public static func defaultRoot() -> URL {
        if let override = ProcessInfo.processInfo.environment["RYDDI_AUDIT_ROOT"], !override.isEmpty {
            return URL(fileURLWithPath: override).standardizedFileURL
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Ryddi/Audit")
    }

    public func summary() -> AuditStoreSummary {
        let records = auditFileRecords()
        let knownRecords = records.filter { $0.isEligibleRegularFile && $0.kind != nil }
        let grouped = Dictionary(grouping: knownRecords, by: { $0.kind ?? "unknown" })
        let items = grouped.map { kind, values in
            AuditStoreSummaryItem(
                kind: kind,
                fileCount: values.count,
                totalBytes: values.reduce(0) { $0 + $1.bytes },
                latestModifiedAt: values.compactMap(\.modifiedAt).max()
            )
        }
        .sorted { lhs, rhs in
            if lhs.totalBytes == rhs.totalBytes {
                return lhs.kind < rhs.kind
            }
            return lhs.totalBytes > rhs.totalBytes
        }
        return AuditStoreSummary(
            rootPath: root.path,
            totalKnownFileCount: knownRecords.count,
            totalKnownBytes: knownRecords.reduce(0) { $0 + $1.bytes },
            unknownFileCount: records.filter { $0.isEligibleRegularFile && $0.kind == nil }.count,
            symlinkCount: records.filter(\.isSymlink).count,
            items: items
        )
    }

    public func prunePlan(policy: AuditRetentionPolicy, now: Date = Date()) -> AuditPrunePlan {
        let records = auditFileRecords()
        let knownRecords = records
            .filter { $0.isEligibleRegularFile && $0.kind != nil }
            .sorted { lhs, rhs in
                (lhs.modifiedAt ?? .distantPast) > (rhs.modifiedAt ?? .distantPast)
            }
        let protectedRecent = Set(knownRecords.prefix(policy.keepRecent).map { $0.url.path })
        let cutoff = now.addingTimeInterval(-TimeInterval(policy.olderThanDays) * 24 * 60 * 60)
        let candidates = knownRecords.compactMap { record -> AuditPruneCandidate? in
            guard !protectedRecent.contains(record.url.path) else { return nil }
            guard let modifiedAt = record.modifiedAt, modifiedAt < cutoff else { return nil }
            guard let kind = record.kind else { return nil }
            return AuditPruneCandidate(
                path: record.url.path,
                kind: kind,
                bytes: record.bytes,
                modifiedAt: modifiedAt,
                filesystemIdentity: record.filesystemIdentity
            )
        }
        return AuditPrunePlan(
            id: UUID().uuidString,
            createdAt: now,
            rootPath: root.path,
            policy: policy,
            candidates: candidates,
            skippedUnknownPaths: records.filter { $0.isEligibleRegularFile && $0.kind == nil }.map { $0.url.path }.sorted(),
            skippedSymlinkPaths: records.filter(\.isSymlink).map { $0.url.path }.sorted()
        )
    }

    public func prune(plan: AuditPrunePlan, dryRun: Bool = true) throws -> AuditPruneReceipt {
        guard !dryRun else {
            return AuditPruneReceipt(
                id: UUID().uuidString,
                createdAt: Date(),
                dryRun: true,
                planID: plan.id,
                deletedCount: 0,
                deletedBytes: 0,
                errors: []
            )
        }

        var deletedCount = 0
        var deletedBytes: Int64 = 0
        var deletedFileIDs: [String] = []
        var errors: [String] = []
        for candidate in plan.candidates {
            let url = URL(fileURLWithPath: candidate.path).standardizedFileURL
            guard url.path.hasPrefix(root.path + "/") else {
                errors.append("skipped outside audit root: \(candidate.path)")
                continue
            }
            guard knownAuditKind(for: url.lastPathComponent) != nil else {
                errors.append("skipped unknown audit file: \(candidate.path)")
                continue
            }
            guard let plannedIdentity = candidate.filesystemIdentity else {
                errors.append("skipped audit plan without filesystem identity: \(candidate.path)")
                continue
            }
            let currentIdentity: FilesystemIdentity
            do {
                currentIdentity = try FilesystemIdentity.capture(at: url)
            } catch {
                errors.append("skipped changed or unreadable audit file: \(candidate.path): \(error.localizedDescription)")
                continue
            }
            guard currentIdentity.isRegularFile,
                  !currentIdentity.isDirectory,
                  !currentIdentity.isSymbolicLink,
                  !currentIdentity.isPackage,
                  !currentIdentity.isVolume else {
                errors.append("skipped non-regular audit file: \(candidate.path)")
                continue
            }
            guard currentIdentity.fileResourceIdentifier == plannedIdentity.fileResourceIdentifier,
                  currentIdentity.volumeIdentifier == plannedIdentity.volumeIdentifier else {
                errors.append("skipped because audit file identity changed: \(candidate.path)")
                continue
            }
            guard currentIdentity.fileSize == plannedIdentity.fileSize,
                  currentIdentity.fileSize == candidate.bytes,
                  currentIdentity.modificationDate == plannedIdentity.modificationDate,
                  currentIdentity.modificationDate == candidate.modifiedAt,
                  currentIdentity.allocatedSize == plannedIdentity.allocatedSize else {
                errors.append("skipped because audit file metadata changed: \(candidate.path)")
                continue
            }
            let result = url.withUnsafeFileSystemRepresentation { path in
                guard let path else { return Int32(-1) }
                return unlink(path)
            }
            if result == 0 {
                deletedCount += 1
                deletedBytes += candidate.bytes
                deletedFileIDs.append(url.lastPathComponent)
            } else {
                errors.append("\(candidate.path): \(String(cString: strerror(errno)))")
            }
        }
        return AuditPruneReceipt(
            id: UUID().uuidString,
            createdAt: Date(),
            dryRun: false,
            planID: plan.id,
            deletedCount: deletedCount,
            deletedBytes: deletedBytes,
            deletedFileIDs: deletedFileIDs.sorted(),
            errors: errors
        )
    }

    public func save(plan: ReclaimPlan) throws -> URL {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("plan-\(plan.id).json")
        try encoder.encode(plan).write(to: url, options: .atomic)
        return url
    }

    public func save(receipt: ExecutionReceipt) throws -> URL {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("receipt-\(receipt.id).json")
        try encoder.encode(receipt).write(to: url, options: .atomic)
        return url
    }

    public func save(nativeToolReport: NativeToolReport) throws -> URL {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("native-tool-\(nativeToolReport.id).json")
        try encoder.encode(nativeToolReport).write(to: url, options: .atomic)
        return url
    }

    public func save(nativeToolExecutionReceipt: NativeToolExecutionReceipt) throws -> URL {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("native-tool-execution-\(nativeToolExecutionReceipt.id).json")
        try encoder.encode(nativeToolExecutionReceipt).write(to: url, options: .atomic)
        return url
    }

    public func save(containerInventoryReport: ContainerInventoryReport) throws -> URL {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("container-inventory-\(containerInventoryReport.id).json")
        try encoder.encode(containerInventoryReport).write(to: url, options: .atomic)
        return url
    }

    public func save(remoteProbeReport: RemoteProbeReport) throws -> URL {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("remote-probe-\(remoteProbeReport.id).json")
        try encoder.encode(remoteProbeReport).write(to: url, options: .atomic)
        return url
    }

    public func save(remoteScanReport: RemoteScanReport) throws -> URL {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("remote-scan-\(remoteScanReport.id).json")
        try encoder.encode(remoteScanReport).write(to: url, options: .atomic)
        return url
    }

    public func save(remoteDogfoodReport report: RemoteDogfoodReport) throws -> URL {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("remote-dogfood-\(report.id).json")
        try encoder.encode(report).write(to: url, options: .atomic)
        return url
    }

    public func save(activeFileReviewReport: ActiveFileReviewReport) throws -> URL {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("active-files-\(activeFileReviewReport.id).json")
        try encoder.encode(activeFileReviewReport).write(to: url, options: .atomic)
        return url
    }

    public func save(trashReviewReport: TrashReviewReport) throws -> URL {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("trash-review-\(trashReviewReport.id).json")
        try encoder.encode(trashReviewReport).write(to: url, options: .atomic)
        return url
    }

    public func save(downloadsReviewReport: DownloadsReviewReport) throws -> URL {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("downloads-review-\(downloadsReviewReport.id).json")
        try encoder.encode(downloadsReviewReport).write(to: url, options: .atomic)
        return url
    }

    public func save(browserCacheReviewReport: BrowserCacheReviewReport) throws -> URL {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("browser-cache-review-\(browserCacheReviewReport.id).json")
        try encoder.encode(browserCacheReviewReport).write(to: url, options: .atomic)
        return url
    }

    public func save(packageCacheReviewReport: PackageCacheReviewReport) throws -> URL {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("package-cache-review-\(packageCacheReviewReport.id).json")
        try encoder.encode(packageCacheReviewReport).write(to: url, options: .atomic)
        return url
    }

    public func save(projectDependencyReviewReport: ProjectDependencyReviewReport) throws -> URL {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("project-dependency-review-\(projectDependencyReviewReport.id).json")
        try encoder.encode(projectDependencyReviewReport).write(to: url, options: .atomic)
        return url
    }

    public func save(deviceBackupReviewReport: DeviceBackupReviewReport) throws -> URL {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("device-backup-review-\(deviceBackupReviewReport.id).json")
        try encoder.encode(deviceBackupReviewReport).write(to: url, options: .atomic)
        return url
    }

    public func save(xcodeReviewReport: XcodeReviewReport) throws -> URL {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("xcode-review-\(xcodeReviewReport.id).json")
        try encoder.encode(xcodeReviewReport).write(to: url, options: .atomic)
        return url
    }

    public func save(appUninstallPreview: AppUninstallPreview) throws -> URL {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("app-uninstall-preview-\(appUninstallPreview.id).json")
        try encoder.encode(appUninstallPreview).write(to: url, options: .atomic)
        return url
    }

    public func save(appUninstallReceipt: AppUninstallExecutionReceipt) throws -> URL {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("app-uninstall-receipt-\(appUninstallReceipt.id).json")
        try encoder.encode(appUninstallReceipt).write(to: url, options: .atomic)
        return url
    }

    public func saveScanSession(_ session: ScanSession) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("\(Self.scanSessionPrefix)\(session.id).json")
        try encoder.encode(session).write(to: url, options: .atomic)
    }

    public func latestScanSession() throws -> ScanSession? {
        try listScanSessions(limit: 1).first
    }

    public func listScanSessions(limit: Int) throws -> [ScanSession] {
        try listScanSessionsResult(limit: limit).sessions
    }

    public func listScanSessionsResult(limit: Int) throws -> AuditStoreScanSessionListResult {
        guard limit > 0 else {
            return AuditStoreScanSessionListResult(sessions: [], warnings: [])
        }
        guard FileManager.default.fileExists(atPath: root.path) else {
            return AuditStoreScanSessionListResult(sessions: [], warnings: [])
        }
        let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        var decodedSessions: [(URL, ScanSession)] = []
        var warnings: [AuditStoreScanSessionWarning] = []
        let scanSessionFiles = files
            .filter { isScanSessionFile($0.lastPathComponent) && $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        for url in scanSessionFiles {
            do {
                let data = try Data(contentsOf: url)
                let session = try decoder.decode(ScanSession.self, from: data)
                decodedSessions.append((url, session))
            } catch {
                warnings.append(AuditStoreScanSessionWarning(
                    path: url.standardizedFileURL.path,
                    kind: .unreadableScanSession,
                    message: "Scan session file could not be read: \(error.localizedDescription)"
                ))
            }
        }

        let sessions = decodedSessions
            .sorted { lhs, rhs in
                if lhs.1.updatedAt == rhs.1.updatedAt {
                    return lhs.0.lastPathComponent > rhs.0.lastPathComponent
                }
                return lhs.1.updatedAt > rhs.1.updatedAt
            }
            .prefix(limit)
            .map(\.1)

        return AuditStoreScanSessionListResult(sessions: Array(sessions), warnings: warnings)
    }

    public func recentReceipts(limit: Int = 20) -> [ExecutionReceipt] {
        guard let files = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.contentModificationDateKey]) else {
            return []
        }
        return files
            .filter { $0.lastPathComponent.hasPrefix("receipt-") }
            .sorted { lhs, rhs in
                let left = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let right = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return left > right
            }
            .prefix(limit)
            .compactMap { try? decoder.decode(ExecutionReceipt.self, from: Data(contentsOf: $0)) }
    }

    public func receipt(id: String) -> ExecutionReceipt? {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return recentReceipts(limit: 500)
            .first { $0.id == trimmed || $0.id.hasPrefix(trimmed) }
    }

    public func recentPlans(limit: Int = 20) -> [ReclaimPlan] {
        guard let files = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.contentModificationDateKey]) else {
            return []
        }
        return files
            .filter { $0.lastPathComponent.hasPrefix("plan-") }
            .sorted { lhs, rhs in
                let left = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let right = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return left > right
            }
            .prefix(limit)
            .compactMap { try? decoder.decode(ReclaimPlan.self, from: Data(contentsOf: $0)) }
    }

    public func plan(id: String) -> ReclaimPlan? {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return recentPlans(limit: 500)
            .first { $0.id == trimmed || $0.id.hasPrefix(trimmed) }
    }

    public func recentNativeToolReports(limit: Int = 20) -> [NativeToolReport] {
        guard let files = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.contentModificationDateKey]) else {
            return []
        }
        return files
            .filter {
                $0.lastPathComponent.hasPrefix("native-tool-")
                    && !$0.lastPathComponent.hasPrefix("native-tool-execution-")
            }
            .sorted { lhs, rhs in
                let left = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let right = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return left > right
            }
            .prefix(limit)
            .compactMap { try? decoder.decode(NativeToolReport.self, from: Data(contentsOf: $0)) }
    }

    public func nativeToolReport(id: String) -> NativeToolReport? {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return recentNativeToolReports(limit: 500)
            .first { $0.id == trimmed || $0.id.hasPrefix(trimmed) }
    }

    public func recentNativeToolExecutionReceipts(limit: Int = 20) -> [NativeToolExecutionReceipt] {
        guard let files = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.contentModificationDateKey]) else {
            return []
        }
        return files
            .filter { $0.lastPathComponent.hasPrefix("native-tool-execution-") }
            .sorted { lhs, rhs in
                let left = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let right = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return left > right
            }
            .prefix(limit)
            .compactMap { try? decoder.decode(NativeToolExecutionReceipt.self, from: Data(contentsOf: $0)) }
    }

    public func nativeToolExecutionReceipt(id: String) -> NativeToolExecutionReceipt? {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return recentNativeToolExecutionReceipts(limit: 500)
            .first { $0.id == trimmed || $0.id.hasPrefix(trimmed) }
    }

    public func recentContainerInventoryReports(limit: Int = 20) -> [ContainerInventoryReport] {
        guard let files = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.contentModificationDateKey]) else {
            return []
        }
        return files
            .filter { $0.lastPathComponent.hasPrefix("container-inventory-") }
            .sorted { lhs, rhs in
                let left = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let right = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return left > right
            }
            .prefix(limit)
            .compactMap { try? decoder.decode(ContainerInventoryReport.self, from: Data(contentsOf: $0)) }
    }

    public func recentRemoteProbeReports(limit: Int = 20) -> [RemoteProbeReport] {
        guard let files = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.contentModificationDateKey]) else {
            return []
        }
        return files
            .filter { $0.lastPathComponent.hasPrefix("remote-probe-") }
            .sorted { lhs, rhs in
                let left = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let right = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return left > right
            }
            .prefix(limit)
            .compactMap { try? decoder.decode(RemoteProbeReport.self, from: Data(contentsOf: $0)) }
    }

    public func recentRemoteScanReports(limit: Int = 20) -> [RemoteScanReport] {
        guard let files = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.contentModificationDateKey]) else {
            return []
        }
        return files
            .filter { $0.lastPathComponent.hasPrefix("remote-scan-") }
            .sorted { lhs, rhs in
                let left = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let right = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return left > right
            }
            .prefix(limit)
            .compactMap { try? decoder.decode(RemoteScanReport.self, from: Data(contentsOf: $0)) }
    }

    public func recentRemoteDogfoodReports(limit: Int = 20) -> [RemoteDogfoodReport] {
        guard let files = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.contentModificationDateKey]) else {
            return []
        }
        return files
            .filter { $0.lastPathComponent.hasPrefix("remote-dogfood-") }
            .sorted { lhs, rhs in
                let left = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let right = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return left > right
            }
            .prefix(limit)
            .compactMap { try? decoder.decode(RemoteDogfoodReport.self, from: Data(contentsOf: $0)) }
    }

    public func latestRemoteScanReport(matching target: RemoteTargetReference) -> RemoteScanReport? {
        recentRemoteScanReports(limit: Int.max).first { localTargetMatches($0.target, target) }
    }

    public func latestRemoteProbeReport(matching target: RemoteTargetReference) -> RemoteProbeReport? {
        recentRemoteProbeReports(limit: Int.max).first { localTargetMatches($0.target, target) }
    }

    public func latestRemoteProbeReport(forConcreteTarget target: RemoteTargetReference) -> RemoteProbeReport? {
        recentRemoteProbeReports(limit: Int.max).first { concreteTargetMatches($0.target, target) }
    }

    public func selectedRemoteScanReport(forAuditQuery target: RemoteTargetReference) throws -> RemoteScanReport? {
        try uniquelySelectedSavedRemoteReport(from: recentRemoteScanReports(limit: Int.max), query: target, target: \.target)
    }

    public func latestRemoteDogfoodReport(forConcreteTarget target: RemoteTargetReference) -> RemoteDogfoodReport? {
        recentRemoteDogfoodReports(limit: Int.max).first { concreteTargetMatches($0.target, target) }
    }

    public func latestPreviousRemoteScanReport(
        forConcreteTarget target: RemoteTargetReference,
        excludingReportID excludedID: String
    ) -> RemoteScanReport? {
        recentRemoteScanReports(limit: Int.max).first {
            $0.id != excludedID && $0.coverage.level != .unreachable && concreteTargetMatches($0.target, target)
        }
    }

    public func remoteScanReport(id: String) -> RemoteScanReport? {
        recentRemoteScanReports(limit: Int.max).first { $0.id == id }
    }

    public func recentActiveFileReviewReports(limit: Int = 20) -> [ActiveFileReviewReport] {
        guard let files = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.contentModificationDateKey]) else {
            return []
        }
        return files
            .filter { $0.lastPathComponent.hasPrefix("active-files-") }
            .sorted { lhs, rhs in
                let left = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let right = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return left > right
            }
            .prefix(limit)
            .compactMap { try? decoder.decode(ActiveFileReviewReport.self, from: Data(contentsOf: $0)) }
    }

    public func recentTrashReviewReports(limit: Int = 20) -> [TrashReviewReport] {
        guard let files = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.contentModificationDateKey]) else {
            return []
        }
        return files
            .filter { $0.lastPathComponent.hasPrefix("trash-review-") }
            .sorted { lhs, rhs in
                let left = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let right = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return left > right
            }
            .prefix(limit)
            .compactMap { try? decoder.decode(TrashReviewReport.self, from: Data(contentsOf: $0)) }
    }

    public func recentDownloadsReviewReports(limit: Int = 20) -> [DownloadsReviewReport] {
        guard let files = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.contentModificationDateKey]) else {
            return []
        }
        return files
            .filter { $0.lastPathComponent.hasPrefix("downloads-review-") }
            .sorted { lhs, rhs in
                let left = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let right = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return left > right
            }
            .prefix(limit)
            .compactMap { try? decoder.decode(DownloadsReviewReport.self, from: Data(contentsOf: $0)) }
    }

    public func recentBrowserCacheReviewReports(limit: Int = 20) -> [BrowserCacheReviewReport] {
        guard let files = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.contentModificationDateKey]) else {
            return []
        }
        return files
            .filter { $0.lastPathComponent.hasPrefix("browser-cache-review-") }
            .sorted { lhs, rhs in
                let left = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let right = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return left > right
            }
            .prefix(limit)
            .compactMap { try? decoder.decode(BrowserCacheReviewReport.self, from: Data(contentsOf: $0)) }
    }

    public func recentPackageCacheReviewReports(limit: Int = 20) -> [PackageCacheReviewReport] {
        guard let files = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.contentModificationDateKey]) else {
            return []
        }
        return files
            .filter { $0.lastPathComponent.hasPrefix("package-cache-review-") }
            .sorted { lhs, rhs in
                let left = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let right = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return left > right
            }
            .prefix(limit)
            .compactMap { try? decoder.decode(PackageCacheReviewReport.self, from: Data(contentsOf: $0)) }
    }

    public func recentProjectDependencyReviewReports(limit: Int = 20) -> [ProjectDependencyReviewReport] {
        guard let files = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.contentModificationDateKey]) else {
            return []
        }
        return files
            .filter { $0.lastPathComponent.hasPrefix("project-dependency-review-") }
            .sorted { lhs, rhs in
                let left = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let right = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return left > right
            }
            .prefix(limit)
            .compactMap { try? decoder.decode(ProjectDependencyReviewReport.self, from: Data(contentsOf: $0)) }
    }

    public func recentDeviceBackupReviewReports(limit: Int = 20) -> [DeviceBackupReviewReport] {
        guard let files = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.contentModificationDateKey]) else {
            return []
        }
        return files
            .filter { $0.lastPathComponent.hasPrefix("device-backup-review-") }
            .sorted { lhs, rhs in
                let left = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let right = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return left > right
            }
            .prefix(limit)
            .compactMap { try? decoder.decode(DeviceBackupReviewReport.self, from: Data(contentsOf: $0)) }
    }

    public func recentXcodeReviewReports(limit: Int = 20) -> [XcodeReviewReport] {
        guard let files = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.contentModificationDateKey]) else {
            return []
        }
        return files
            .filter { $0.lastPathComponent.hasPrefix("xcode-review-") }
            .sorted { lhs, rhs in
                let left = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let right = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return left > right
            }
            .prefix(limit)
            .compactMap { try? decoder.decode(XcodeReviewReport.self, from: Data(contentsOf: $0)) }
    }

    public func recentAppUninstallReceipts(limit: Int = 20) -> [AppUninstallExecutionReceipt] {
        guard let files = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.contentModificationDateKey]) else {
            return []
        }
        return files
            .filter { $0.lastPathComponent.hasPrefix("app-uninstall-receipt-") }
            .sorted { lhs, rhs in
                let left = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let right = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return left > right
            }
            .prefix(limit)
            .compactMap { try? decoder.decode(AppUninstallExecutionReceipt.self, from: Data(contentsOf: $0)) }
    }

    private func auditFileRecords() -> [AuditFileRecord] {
        let keys: Set<URLResourceKey> = [
            .contentModificationDateKey,
            .fileSizeKey,
            .isSymbolicLinkKey
        ]
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        return files.map { url in
            let values = try? url.resourceValues(forKeys: keys)
            let filesystemIdentity = try? FilesystemIdentity.capture(at: url)
            let bytes = filesystemIdentity?.fileSize ?? Int64(values?.fileSize ?? 0)
            return AuditFileRecord(
                url: url.standardizedFileURL,
                kind: knownAuditKind(for: url.lastPathComponent),
                bytes: bytes,
                modifiedAt: filesystemIdentity?.modificationDate ?? values?.contentModificationDate,
                isSymlink: filesystemIdentity?.isSymbolicLink == true || values?.isSymbolicLink == true,
                filesystemIdentity: filesystemIdentity
            )
        }
    }

    private func knownAuditKind(for filename: String) -> String? {
        guard filename.hasSuffix(".json") else {
            return nil
        }
        if isScanSessionFile(filename) {
            return "scan-session-v1"
        }
        for (prefix, kind) in Self.knownAuditPrefixes {
            if filename.hasPrefix(prefix) {
                return kind
            }
        }
        return nil
    }

    private static let knownAuditPrefixes: [(prefix: String, kind: String)] = [
        ("native-tool-execution-", "native-tool-execution"),
        ("project-dependency-review-", "project-dependency-review"),
        ("app-uninstall-preview-", "app-uninstall-preview"),
        ("app-uninstall-receipt-", "app-uninstall-receipt"),
        ("browser-cache-review-", "browser-cache-review"),
        ("package-cache-review-", "package-cache-review"),
        ("container-inventory-", "container-inventory"),
        ("device-backup-review-", "device-backup-review"),
        ("downloads-review-", "downloads-review"),
        ("remote-dogfood-", "remote-dogfood"),
        ("active-files-", "active-files"),
        ("trash-review-", "trash-review"),
        ("native-tool-", "native-tool"),
        ("remote-probe-", "remote-probe"),
        ("remote-scan-", "remote-scan"),
        ("xcode-review-", "xcode-review"),
        ("receipt-", "receipt"),
        ("plan-", "plan"),
    ]

    private func isScanSessionFile(_ filename: String) -> Bool {
        filename.hasPrefix(Self.scanSessionPrefix) || filename.hasPrefix(Self.legacyScanSessionPrefix)
    }

    private func localTargetMatches(_ lhs: RemoteTargetReference, _ rhs: RemoteTargetReference) -> Bool {
        if resolvedTargetMatches(lhs, rhs) {
            return true
        }
        if resolvedTargetConflicts(lhs, rhs) {
            return false
        }
        return !localTargetIdentifiers(lhs).isDisjoint(with: localTargetIdentifiers(rhs))
    }

    private func concreteTargetMatches(_ lhs: RemoteTargetReference, _ rhs: RemoteTargetReference) -> Bool {
        if resolvedTargetMatches(lhs, rhs) {
            return true
        }
        if resolvedTargetConflicts(lhs, rhs) {
            return false
        }
        guard
            let leftID = normalizedIdentity(lhs.id),
            let rightID = normalizedIdentity(rhs.id)
        else {
            return false
        }
        return leftID == rightID
    }

    private func localTargetIdentifiers(_ target: RemoteTargetReference) -> Set<String> {
        Set([target.id, target.input, target.alias].compactMap(normalizedIdentity))
    }

    private func uniquelySelectedSavedRemoteReport<Report>(
        from reports: [Report],
        query: RemoteTargetReference,
        target targetKeyPath: KeyPath<Report, RemoteTargetReference>
    ) throws -> Report? {
        let matches = reports.filter { localTargetMatches($0[keyPath: targetKeyPath], query) }
        guard !matches.isEmpty else {
            return nil
        }
        let groups = Set(matches.map { targetGroupKey(for: $0[keyPath: targetKeyPath]) })
        guard groups.count == 1 else {
            throw RemoteAuditQueryError.ambiguousSavedTargetQuery(auditQueryLabel(for: query))
        }
        return matches.first
    }

    private func resolvedTargetMatches(_ lhs: RemoteTargetReference, _ rhs: RemoteTargetReference) -> Bool {
        guard
            let leftUser = normalizedIdentity(lhs.resolvedUser),
            let rightUser = normalizedIdentity(rhs.resolvedUser),
            let leftHost = normalizedIdentity(lhs.resolvedHost),
            let rightHost = normalizedIdentity(rhs.resolvedHost),
            let leftPort = lhs.resolvedPort,
            let rightPort = rhs.resolvedPort
        else {
            return false
        }
        return leftUser == rightUser && leftHost == rightHost && leftPort == rightPort
    }

    private func resolvedTargetConflicts(_ lhs: RemoteTargetReference, _ rhs: RemoteTargetReference) -> Bool {
        hasCompleteResolvedIdentity(lhs) && hasCompleteResolvedIdentity(rhs) && !resolvedTargetMatches(lhs, rhs)
    }

    private func hasCompleteResolvedIdentity(_ target: RemoteTargetReference) -> Bool {
        normalizedIdentity(target.resolvedUser) != nil &&
            normalizedIdentity(target.resolvedHost) != nil &&
            target.resolvedPort != nil
    }

    private func targetGroupKey(for target: RemoteTargetReference) -> String {
        if let concrete = concreteIdentityKey(for: target) {
            return "concrete:\(concrete)"
        }
        if let id = normalizedIdentity(target.id) {
            return "unresolved-id:\(id)"
        }
        if let alias = normalizedIdentity(target.alias) {
            return "unresolved-alias:\(alias)"
        }
        return "unresolved-input:\(normalizedIdentity(target.input) ?? "<empty>")"
    }

    private func concreteIdentityKey(for target: RemoteTargetReference) -> String? {
        guard
            let user = normalizedIdentity(target.resolvedUser),
            let host = normalizedIdentity(target.resolvedHost),
            let port = target.resolvedPort
        else {
            return nil
        }
        return "\(user)@\(host):\(port)"
    }

    private func auditQueryLabel(for target: RemoteTargetReference) -> String {
        normalizedIdentity(target.input) ??
            normalizedIdentity(target.alias) ??
            normalizedIdentity(target.id) ??
            "<unknown>"
    }

    private func normalizedIdentity(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}
