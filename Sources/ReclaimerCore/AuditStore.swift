import Darwin
import Foundation

protocol AuditDirectoryReading: Sendable {
    func contentsOfDirectory(
        at url: URL,
        includingPropertiesForKeys keys: [URLResourceKey]?,
        options mask: FileManager.DirectoryEnumerationOptions
    ) throws -> [URL]
}

struct FileManagerAuditDirectoryReader: AuditDirectoryReading {
    func contentsOfDirectory(
        at url: URL,
        includingPropertiesForKeys keys: [URLResourceKey]?,
        options mask: FileManager.DirectoryEnumerationOptions
    ) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: keys,
            options: mask
        )
    }
}

protocol AuditDataReading: Sendable {
    func read(from url: URL) throws -> Data
}

struct FileAuditDataReader: AuditDataReading {
    func read(from url: URL) throws -> Data {
        try Data(contentsOf: url)
    }
}

protocol AuditDecoding: Sendable {
    func decode<Value: Decodable>(_ type: Value.Type, from data: Data) throws -> Value
}

final class JSONAuditDecoder: AuditDecoding, @unchecked Sendable {
    private let decoder: JSONDecoder

    init() {
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func decode<Value: Decodable>(_ type: Value.Type, from data: Data) throws -> Value {
        try decoder.decode(type, from: data)
    }
}

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
    private static let scanSessionLockFileName = ".scan-session.lock"
    private static let scanSessionMutationLock = NSLock()

    private enum AuditFileKind: String, CaseIterable {
        case scanSession = "scan-session-v1"
        case nativeToolExecution = "native-tool-execution"
        case projectDependencyReview = "project-dependency-review"
        case appUninstallPreview = "app-uninstall-preview"
        case appUninstallReceipt = "app-uninstall-receipt"
        case browserCacheReview = "browser-cache-review"
        case packageCacheReview = "package-cache-review"
        case containerInventory = "container-inventory"
        case deviceBackupReview = "device-backup-review"
        case downloadsReview = "downloads-review"
        case remoteDogfood = "remote-dogfood"
        case activeFiles = "active-files"
        case trashReview = "trash-review"
        case nativeTool = "native-tool"
        case remoteProbe = "remote-probe"
        case remoteScan = "remote-scan"
        case xcodeReview = "xcode-review"
        case receipt
        case plan
    }

    private struct AuditFileRecord {
        let url: URL
        let kind: AuditFileKind?
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

    private struct AuditIndex {
        let records: [AuditFileRecord]
        let recordsByKind: [AuditFileKind: [AuditFileRecord]]
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
    private let decoder: any AuditDecoding
    private let directoryReader: any AuditDirectoryReading
    private let dataReader: any AuditDataReading
    private let trasher: any Trashing

    public init(root: URL = AuditStore.defaultRoot(), trasher: any Trashing = FileManagerTrasher()) {
        self.root = root.standardizedFileURL
        self.trasher = trasher
        self.directoryReader = FileManagerAuditDirectoryReader()
        self.dataReader = FileAuditDataReader()
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder = JSONAuditDecoder()
    }

    init(
        root: URL,
        trasher: any Trashing = FileManagerTrasher(),
        directoryReader: any AuditDirectoryReading,
        dataReader: any AuditDataReading = FileAuditDataReader(),
        decoder: any AuditDecoding
    ) {
        self.root = root.standardizedFileURL
        self.trasher = trasher
        self.directoryReader = directoryReader
        self.dataReader = dataReader
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder = decoder
    }

    public static func defaultRoot() -> URL {
        if let override = ProcessInfo.processInfo.environment["RYDDI_AUDIT_ROOT"], !override.isEmpty {
            return URL(fileURLWithPath: override).standardizedFileURL
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Ryddi/Audit")
    }

    public func summary() -> AuditStoreSummary {
        summary(from: auditIndexOrEmpty())
    }

    private func summary(from index: AuditIndex) -> AuditStoreSummary {
        let records = index.records
        let knownRecords = records.filter { $0.isEligibleRegularFile && $0.kind != nil }
        let grouped = Dictionary(grouping: knownRecords, by: { $0.kind?.rawValue ?? "unknown" })
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
        let records = auditIndexOrEmpty().records
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
                kind: kind.rawValue,
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

        guard URL(fileURLWithPath: plan.rootPath, isDirectory: true).standardizedFileURL == root else {
            return AuditPruneReceipt(
                dryRun: false,
                planID: plan.id,
                deletedCount: 0,
                deletedBytes: 0,
                errors: ["Audit prune plan root does not match this audit store."]
            )
        }

        var trashedIDs: [String] = []
        var trashedBytes: Int64 = 0
        var errors: [String] = []
        for candidate in plan.candidates {
            let url = URL(fileURLWithPath: candidate.path).standardizedFileURL
            let filename = url.lastPathComponent
            guard url.deletingLastPathComponent() == root else {
                errors.append("Skipped \(filename): path is outside the audit root.")
                continue
            }
            guard knownAuditKind(for: filename)?.rawValue == candidate.kind else {
                errors.append("Skipped \(filename): audit kind no longer matches the reviewed plan.")
                continue
            }
            guard let plannedIdentity = candidate.filesystemIdentity else {
                errors.append("Skipped \(filename): legacy candidate has no filesystem identity.")
                continue
            }
            guard let currentIdentity = try? FilesystemIdentity.capture(at: url),
                  currentIdentity == plannedIdentity,
                  currentIdentity.isRegularFile,
                  !currentIdentity.isSymbolicLink,
                  !currentIdentity.isDirectory,
                  !currentIdentity.isPackage,
                  !currentIdentity.isVolume else {
                errors.append("Skipped \(filename): filesystem identity changed after review.")
                continue
            }
            do {
                _ = try trasher.trashItem(at: url)
                trashedIDs.append(filename)
                trashedBytes += candidate.bytes
            } catch {
                errors.append("Skipped \(filename): \(error.localizedDescription)")
            }
        }
        return AuditPruneReceipt(
            dryRun: false,
            planID: plan.id,
            deletedCount: trashedIDs.count,
            deletedBytes: trashedBytes,
            deletedFileIDs: trashedIDs,
            errors: errors
        )
    }

    public func save(plan: ReclaimPlan) throws -> URL {
        try prepareRoot()
        let url = root.appendingPathComponent("plan-\(plan.id).json")
        try writeSecurely(plan, to: url)
        return url
    }

    public func save(receipt: ExecutionReceipt) throws -> URL {
        try prepareRoot()
        let url = root.appendingPathComponent("receipt-\(receipt.id).json")
        try writeSecurely(receipt, to: url)
        return url
    }

    public func save(nativeToolReport: NativeToolReport) throws -> URL {
        try prepareRoot()
        let url = root.appendingPathComponent("native-tool-\(nativeToolReport.id).json")
        try writeSecurely(nativeToolReport, to: url)
        return url
    }

    public func save(nativeToolExecutionReceipt: NativeToolExecutionReceipt) throws -> URL {
        try prepareRoot()
        let url = root.appendingPathComponent("native-tool-execution-\(nativeToolExecutionReceipt.id).json")
        try writeSecurely(nativeToolExecutionReceipt, to: url)
        return url
    }

    public func save(containerInventoryReport: ContainerInventoryReport) throws -> URL {
        try prepareRoot()
        let url = root.appendingPathComponent("container-inventory-\(containerInventoryReport.id).json")
        try writeSecurely(containerInventoryReport, to: url)
        return url
    }

    public func save(remoteProbeReport: RemoteProbeReport) throws -> URL {
        try prepareRoot()
        let url = root.appendingPathComponent("remote-probe-\(remoteProbeReport.id).json")
        try writeSecurely(remoteProbeReport, to: url)
        return url
    }

    public func save(remoteScanReport: RemoteScanReport) throws -> URL {
        try prepareRoot()
        let url = root.appendingPathComponent("remote-scan-\(remoteScanReport.id).json")
        try writeSecurely(remoteScanReport, to: url)
        return url
    }

    public func save(remoteDogfoodReport report: RemoteDogfoodReport) throws -> URL {
        try prepareRoot()
        let url = root.appendingPathComponent("remote-dogfood-\(report.id).json")
        try writeSecurely(report, to: url)
        return url
    }

    public func save(activeFileReviewReport: ActiveFileReviewReport) throws -> URL {
        try prepareRoot()
        let url = root.appendingPathComponent("active-files-\(activeFileReviewReport.id).json")
        try writeSecurely(activeFileReviewReport, to: url)
        return url
    }

    public func save(trashReviewReport: TrashReviewReport) throws -> URL {
        try prepareRoot()
        let url = root.appendingPathComponent("trash-review-\(trashReviewReport.id).json")
        try writeSecurely(trashReviewReport, to: url)
        return url
    }

    public func save(downloadsReviewReport: DownloadsReviewReport) throws -> URL {
        try prepareRoot()
        let url = root.appendingPathComponent("downloads-review-\(downloadsReviewReport.id).json")
        try writeSecurely(downloadsReviewReport, to: url)
        return url
    }

    public func save(browserCacheReviewReport: BrowserCacheReviewReport) throws -> URL {
        try prepareRoot()
        let url = root.appendingPathComponent("browser-cache-review-\(browserCacheReviewReport.id).json")
        try writeSecurely(browserCacheReviewReport, to: url)
        return url
    }

    public func save(packageCacheReviewReport: PackageCacheReviewReport) throws -> URL {
        try prepareRoot()
        let url = root.appendingPathComponent("package-cache-review-\(packageCacheReviewReport.id).json")
        try writeSecurely(packageCacheReviewReport, to: url)
        return url
    }

    public func save(projectDependencyReviewReport: ProjectDependencyReviewReport) throws -> URL {
        try prepareRoot()
        let url = root.appendingPathComponent("project-dependency-review-\(projectDependencyReviewReport.id).json")
        try writeSecurely(projectDependencyReviewReport, to: url)
        return url
    }

    public func save(deviceBackupReviewReport: DeviceBackupReviewReport) throws -> URL {
        try prepareRoot()
        let url = root.appendingPathComponent("device-backup-review-\(deviceBackupReviewReport.id).json")
        try writeSecurely(deviceBackupReviewReport, to: url)
        return url
    }

    public func save(xcodeReviewReport: XcodeReviewReport) throws -> URL {
        try prepareRoot()
        let url = root.appendingPathComponent("xcode-review-\(xcodeReviewReport.id).json")
        try writeSecurely(xcodeReviewReport, to: url)
        return url
    }

    public func save(appUninstallPreview: AppUninstallPreview) throws -> URL {
        try prepareRoot()
        let url = root.appendingPathComponent("app-uninstall-preview-\(appUninstallPreview.id).json")
        try writeSecurely(appUninstallPreview, to: url)
        return url
    }

    public func save(appUninstallReceipt: AppUninstallExecutionReceipt) throws -> URL {
        try prepareRoot()
        let url = root.appendingPathComponent("app-uninstall-receipt-\(appUninstallReceipt.id).json")
        try writeSecurely(appUninstallReceipt, to: url)
        return url
    }

    public func saveScanSession(_ session: ScanSession) throws {
        try prepareRoot()
        let url = root.appendingPathComponent("\(Self.scanSessionPrefix)\(session.id).json")
        try withExclusiveScanSessionMutation {
            if FileManager.default.fileExists(atPath: url.path) {
                let data = try dataReader.read(from: url)
                let existing = try decoder.decode(ScanSession.self, from: data)
                guard existing.id == session.id else {
                    throw NSError(
                        domain: "Ryddi.AuditStore",
                        code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "The existing scan-session file does not match its requested session ID."]
                    )
                }
                guard session.updatedAt > existing.updatedAt else {
                    return
                }
            }
            try writeSecurely(session, to: url)
        }
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
        return scanSessions(from: try auditIndex(), limit: limit, capBeforeDecoding: false)
    }

    public func snapshot(limitPerKind: Int = 20) -> AuditStoreSnapshot {
        let index = auditIndexOrEmpty()
        return AuditStoreSnapshot(
            summary: summary(from: index),
            scanSessions: scanSessions(from: index, limit: limitPerKind, capBeforeDecoding: true),
            plans: decode(ReclaimPlan.self, kind: .plan, limit: limitPerKind, from: index),
            receipts: decode(ExecutionReceipt.self, kind: .receipt, limit: limitPerKind, from: index),
            nativeToolReports: decode(NativeToolReport.self, kind: .nativeTool, limit: limitPerKind, from: index),
            nativeToolExecutionReceipts: decode(
                NativeToolExecutionReceipt.self,
                kind: .nativeToolExecution,
                limit: limitPerKind,
                from: index
            ),
            containerInventoryReports: decode(
                ContainerInventoryReport.self,
                kind: .containerInventory,
                limit: limitPerKind,
                from: index
            ),
            remoteProbeReports: decode(RemoteProbeReport.self, kind: .remoteProbe, limit: limitPerKind, from: index),
            remoteScanReports: decode(RemoteScanReport.self, kind: .remoteScan, limit: limitPerKind, from: index),
            remoteDogfoodReports: decode(
                RemoteDogfoodReport.self,
                kind: .remoteDogfood,
                limit: limitPerKind,
                from: index
            ),
            activeFileReviewReports: decode(
                ActiveFileReviewReport.self,
                kind: .activeFiles,
                limit: limitPerKind,
                from: index
            ),
            trashReviewReports: decode(TrashReviewReport.self, kind: .trashReview, limit: limitPerKind, from: index),
            downloadsReviewReports: decode(
                DownloadsReviewReport.self,
                kind: .downloadsReview,
                limit: limitPerKind,
                from: index
            ),
            browserCacheReviewReports: decode(
                BrowserCacheReviewReport.self,
                kind: .browserCacheReview,
                limit: limitPerKind,
                from: index
            ),
            packageCacheReviewReports: decode(
                PackageCacheReviewReport.self,
                kind: .packageCacheReview,
                limit: limitPerKind,
                from: index
            ),
            projectDependencyReviewReports: decode(
                ProjectDependencyReviewReport.self,
                kind: .projectDependencyReview,
                limit: limitPerKind,
                from: index
            ),
            deviceBackupReviewReports: decode(
                DeviceBackupReviewReport.self,
                kind: .deviceBackupReview,
                limit: limitPerKind,
                from: index
            ),
            xcodeReviewReports: decode(XcodeReviewReport.self, kind: .xcodeReview, limit: limitPerKind, from: index),
            appUninstallReceipts: decode(
                AppUninstallExecutionReceipt.self,
                kind: .appUninstallReceipt,
                limit: limitPerKind,
                from: index
            )
        )
    }

    public func recentReceipts(limit: Int = 20) -> [ExecutionReceipt] {
        decode(ExecutionReceipt.self, kind: .receipt, limit: limit, from: auditIndexOrEmpty())
    }

    public func receipt(id: String) -> ExecutionReceipt? {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return recentReceipts(limit: 500)
            .first { $0.id == trimmed || $0.id.hasPrefix(trimmed) }
    }

    public func recentPlans(limit: Int = 20) -> [ReclaimPlan] {
        decode(ReclaimPlan.self, kind: .plan, limit: limit, from: auditIndexOrEmpty())
    }

    public func plan(id: String) -> ReclaimPlan? {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return recentPlans(limit: 500)
            .first { $0.id == trimmed || $0.id.hasPrefix(trimmed) }
    }

    public func recentNativeToolReports(limit: Int = 20) -> [NativeToolReport] {
        decode(NativeToolReport.self, kind: .nativeTool, limit: limit, from: auditIndexOrEmpty())
    }

    public func nativeToolReport(id: String) -> NativeToolReport? {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return recentNativeToolReports(limit: 500)
            .first { $0.id == trimmed || $0.id.hasPrefix(trimmed) }
    }

    public func recentNativeToolExecutionReceipts(limit: Int = 20) -> [NativeToolExecutionReceipt] {
        decode(NativeToolExecutionReceipt.self, kind: .nativeToolExecution, limit: limit, from: auditIndexOrEmpty())
    }

    public func nativeToolExecutionReceipt(id: String) -> NativeToolExecutionReceipt? {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return recentNativeToolExecutionReceipts(limit: 500)
            .first { $0.id == trimmed || $0.id.hasPrefix(trimmed) }
    }

    public func recentContainerInventoryReports(limit: Int = 20) -> [ContainerInventoryReport] {
        decode(ContainerInventoryReport.self, kind: .containerInventory, limit: limit, from: auditIndexOrEmpty())
    }

    public func recentRemoteProbeReports(limit: Int = 20) -> [RemoteProbeReport] {
        decode(RemoteProbeReport.self, kind: .remoteProbe, limit: limit, from: auditIndexOrEmpty())
    }

    public func recentRemoteScanReports(limit: Int = 20) -> [RemoteScanReport] {
        decode(RemoteScanReport.self, kind: .remoteScan, limit: limit, from: auditIndexOrEmpty())
    }

    public func recentRemoteDogfoodReports(limit: Int = 20) -> [RemoteDogfoodReport] {
        decode(RemoteDogfoodReport.self, kind: .remoteDogfood, limit: limit, from: auditIndexOrEmpty())
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
        decode(ActiveFileReviewReport.self, kind: .activeFiles, limit: limit, from: auditIndexOrEmpty())
    }

    public func recentTrashReviewReports(limit: Int = 20) -> [TrashReviewReport] {
        decode(TrashReviewReport.self, kind: .trashReview, limit: limit, from: auditIndexOrEmpty())
    }

    public func recentDownloadsReviewReports(limit: Int = 20) -> [DownloadsReviewReport] {
        decode(DownloadsReviewReport.self, kind: .downloadsReview, limit: limit, from: auditIndexOrEmpty())
    }

    public func recentBrowserCacheReviewReports(limit: Int = 20) -> [BrowserCacheReviewReport] {
        decode(BrowserCacheReviewReport.self, kind: .browserCacheReview, limit: limit, from: auditIndexOrEmpty())
    }

    public func recentPackageCacheReviewReports(limit: Int = 20) -> [PackageCacheReviewReport] {
        decode(PackageCacheReviewReport.self, kind: .packageCacheReview, limit: limit, from: auditIndexOrEmpty())
    }

    public func recentProjectDependencyReviewReports(limit: Int = 20) -> [ProjectDependencyReviewReport] {
        decode(ProjectDependencyReviewReport.self, kind: .projectDependencyReview, limit: limit, from: auditIndexOrEmpty())
    }

    public func recentDeviceBackupReviewReports(limit: Int = 20) -> [DeviceBackupReviewReport] {
        decode(DeviceBackupReviewReport.self, kind: .deviceBackupReview, limit: limit, from: auditIndexOrEmpty())
    }

    public func recentXcodeReviewReports(limit: Int = 20) -> [XcodeReviewReport] {
        decode(XcodeReviewReport.self, kind: .xcodeReview, limit: limit, from: auditIndexOrEmpty())
    }

    public func recentAppUninstallReceipts(limit: Int = 20) -> [AppUninstallExecutionReceipt] {
        decode(AppUninstallExecutionReceipt.self, kind: .appUninstallReceipt, limit: limit, from: auditIndexOrEmpty())
    }

    private func auditIndexOrEmpty() -> AuditIndex {
        (try? auditIndex()) ?? AuditIndex(records: [], recordsByKind: [:])
    }

    private func auditIndex() throws -> AuditIndex {
        let records = try auditFileRecords()
        var recordsByKind: [AuditFileKind: [AuditFileRecord]] = [:]

        for record in records {
            guard record.isEligibleRegularFile, let kind = record.kind else { continue }
            recordsByKind[kind, default: []].append(record)
        }

        for kind in Array(recordsByKind.keys) {
            recordsByKind[kind]?.sort(by: Self.isNewerAuditRecord)
        }

        return AuditIndex(records: records, recordsByKind: recordsByKind)
    }

    private static func isNewerAuditRecord(_ lhs: AuditFileRecord, _ rhs: AuditFileRecord) -> Bool {
        let left = lhs.modifiedAt ?? .distantPast
        let right = rhs.modifiedAt ?? .distantPast
        if left == right {
            return lhs.url.lastPathComponent > rhs.url.lastPathComponent
        }
        return left > right
    }

    private func decode<Value: Decodable>(
        _ type: Value.Type,
        kind: AuditFileKind,
        limit: Int,
        from index: AuditIndex
    ) -> [Value] {
        guard limit > 0 else { return [] }
        return index.recordsByKind[kind, default: []]
            .prefix(limit)
            .compactMap { record in
                guard let data = try? dataReader.read(from: record.url) else { return nil }
                return try? decoder.decode(type, from: data)
            }
    }

    private func scanSessions(
        from index: AuditIndex,
        limit: Int,
        capBeforeDecoding: Bool
    ) -> AuditStoreScanSessionListResult {
        guard limit > 0 else {
            return AuditStoreScanSessionListResult(sessions: [], warnings: [])
        }

        let indexedRecords = index.recordsByKind[.scanSession, default: []]
        let records = capBeforeDecoding
            ? Array(indexedRecords.prefix(limit))
            : indexedRecords.sorted { $0.url.lastPathComponent < $1.url.lastPathComponent }
        var decodedSessions: [(AuditFileRecord, ScanSession)] = []
        var warnings: [AuditStoreScanSessionWarning] = []

        for record in records {
            do {
                let data = try dataReader.read(from: record.url)
                let session = try decoder.decode(ScanSession.self, from: data)
                decodedSessions.append((record, session))
            } catch {
                warnings.append(AuditStoreScanSessionWarning(
                    path: record.url.path,
                    kind: .unreadableScanSession,
                    message: "Scan session file could not be read: \(error.localizedDescription)"
                ))
            }
        }

        let sessions: [ScanSession]
        if capBeforeDecoding {
            sessions = decodedSessions.map(\.1)
        } else {
            sessions = decodedSessions
                .sorted { lhs, rhs in
                    if lhs.1.updatedAt == rhs.1.updatedAt {
                        return lhs.0.url.lastPathComponent > rhs.0.url.lastPathComponent
                    }
                    return lhs.1.updatedAt > rhs.1.updatedAt
                }
                .prefix(limit)
                .map(\.1)
        }

        return AuditStoreScanSessionListResult(sessions: sessions, warnings: warnings)
    }

    private func prepareRoot() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
    }

    private func writeSecurely<Value: Encodable>(_ value: Value, to url: URL) throws {
        try encoder.encode(value).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private func withExclusiveScanSessionMutation<Result>(_ operation: () throws -> Result) throws -> Result {
        Self.scanSessionMutationLock.lock()
        defer { Self.scanSessionMutationLock.unlock() }

        let lockURL = root.appendingPathComponent(Self.scanSessionLockFileName)
        let descriptor = lockURL.path.withCString {
            Darwin.open($0, O_RDWR | O_CREAT | O_CLOEXEC | O_NOFOLLOW, mode_t(0o600))
        }
        guard descriptor >= 0 else {
            throw posixError("The scan-session mutation lock could not be opened.")
        }
        defer { Darwin.close(descriptor) }

        var metadata = Darwin.stat()
        guard Darwin.fstat(descriptor, &metadata) == 0,
              metadata.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
              Darwin.fchmod(descriptor, mode_t(0o600)) == 0 else {
            throw posixError("The scan-session mutation lock is not an ordinary file.")
        }

        while Self.setAdvisoryLock(descriptor, type: Int16(F_WRLCK), command: F_SETLKW) != 0 {
            guard errno == EINTR else {
                throw posixError("The scan-session mutation lock could not be acquired.")
            }
        }
        defer { _ = Self.setAdvisoryLock(descriptor, type: Int16(F_UNLCK), command: F_SETLK) }

        var currentMetadata = Darwin.stat()
        guard lockURL.path.withCString({ Darwin.lstat($0, &currentMetadata) }) == 0,
              currentMetadata.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
              currentMetadata.st_dev == metadata.st_dev,
              currentMetadata.st_ino == metadata.st_ino else {
            throw posixError("The scan-session mutation lock changed while it was being acquired.")
        }
        return try operation()
    }

    private static func setAdvisoryLock(_ descriptor: Int32, type: Int16, command: Int32) -> Int32 {
        var lock = Darwin.flock()
        lock.l_start = 0
        lock.l_len = 0
        lock.l_pid = 0
        lock.l_type = type
        lock.l_whence = Int16(SEEK_SET)
        return Darwin.fcntl(descriptor, command, &lock)
    }

    private func posixError(_ message: String) -> NSError {
        let code = errno
        return NSError(
            domain: NSPOSIXErrorDomain,
            code: Int(code),
            userInfo: [NSLocalizedDescriptionKey: "\(message) \(String(cString: strerror(code)))"]
        )
    }

    private func auditFileRecords() throws -> [AuditFileRecord] {
        let keys: Set<URLResourceKey> = [
            .contentModificationDateKey,
            .fileSizeKey,
            .isSymbolicLinkKey
        ]
        guard FileManager.default.fileExists(atPath: root.path) else {
            return []
        }
        let files = try directoryReader.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        )
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

    private func knownAuditKind(for filename: String) -> AuditFileKind? {
        guard filename.hasSuffix(".json") else {
            return nil
        }
        if isScanSessionFile(filename) {
            return .scanSession
        }
        for (prefix, kind) in Self.knownAuditPrefixes {
            if filename.hasPrefix(prefix) {
                return kind
            }
        }
        return nil
    }

    private static let knownAuditPrefixes: [(prefix: String, kind: AuditFileKind)] = [
        ("native-tool-execution-", .nativeToolExecution),
        ("project-dependency-review-", .projectDependencyReview),
        ("app-uninstall-preview-", .appUninstallPreview),
        ("app-uninstall-receipt-", .appUninstallReceipt),
        ("browser-cache-review-", .browserCacheReview),
        ("package-cache-review-", .packageCacheReview),
        ("container-inventory-", .containerInventory),
        ("device-backup-review-", .deviceBackupReview),
        ("downloads-review-", .downloadsReview),
        ("remote-dogfood-", .remoteDogfood),
        ("active-files-", .activeFiles),
        ("trash-review-", .trashReview),
        ("native-tool-", .nativeTool),
        ("remote-probe-", .remoteProbe),
        ("remote-scan-", .remoteScan),
        ("xcode-review-", .xcodeReview),
        ("receipt-", .receipt),
        ("plan-", .plan),
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
        RemoteAuditTargetMatcher.concreteTargetsMatch(lhs, rhs)
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
