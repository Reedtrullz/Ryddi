import Foundation

public final class AuditStore: @unchecked Sendable {
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
            .filter { $0.lastPathComponent.hasPrefix("native-tool-") }
            .sorted { lhs, rhs in
                let left = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let right = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return left > right
            }
            .prefix(limit)
            .compactMap { try? decoder.decode(NativeToolReport.self, from: Data(contentsOf: $0)) }
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

    private func localTargetMatches(_ lhs: RemoteTargetReference, _ rhs: RemoteTargetReference) -> Bool {
        !localTargetIdentifiers(lhs).isDisjoint(with: localTargetIdentifiers(rhs))
    }

    private func localTargetIdentifiers(_ target: RemoteTargetReference) -> Set<String> {
        Set([target.id, target.input, target.alias].compactMap(normalizedIdentity))
    }

    private func normalizedIdentity(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}
