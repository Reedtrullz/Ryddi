import Foundation

public struct AuditStoreSnapshot: Sendable {
    public let summary: AuditStoreSummary
    public let scanSessions: AuditStoreScanSessionListResult
    public let plans: [ReclaimPlan]
    public let receipts: [ExecutionReceipt]
    public let nativeToolReports: [NativeToolReport]
    public let nativeToolExecutionReceipts: [NativeToolExecutionReceipt]
    public let containerInventoryReports: [ContainerInventoryReport]
    public let remoteProbeReports: [RemoteProbeReport]
    public let remoteScanReports: [RemoteScanReport]
    public let remoteDogfoodReports: [RemoteDogfoodReport]
    public let activeFileReviewReports: [ActiveFileReviewReport]
    public let trashReviewReports: [TrashReviewReport]
    public let downloadsReviewReports: [DownloadsReviewReport]
    public let browserCacheReviewReports: [BrowserCacheReviewReport]
    public let packageCacheReviewReports: [PackageCacheReviewReport]
    public let projectDependencyReviewReports: [ProjectDependencyReviewReport]
    public let deviceBackupReviewReports: [DeviceBackupReviewReport]
    public let xcodeReviewReports: [XcodeReviewReport]
    public let appUninstallReceipts: [AppUninstallExecutionReceipt]

    public init(
        summary: AuditStoreSummary,
        scanSessions: AuditStoreScanSessionListResult,
        plans: [ReclaimPlan],
        receipts: [ExecutionReceipt],
        nativeToolReports: [NativeToolReport],
        nativeToolExecutionReceipts: [NativeToolExecutionReceipt],
        containerInventoryReports: [ContainerInventoryReport],
        remoteProbeReports: [RemoteProbeReport],
        remoteScanReports: [RemoteScanReport],
        remoteDogfoodReports: [RemoteDogfoodReport],
        activeFileReviewReports: [ActiveFileReviewReport],
        trashReviewReports: [TrashReviewReport],
        downloadsReviewReports: [DownloadsReviewReport],
        browserCacheReviewReports: [BrowserCacheReviewReport],
        packageCacheReviewReports: [PackageCacheReviewReport],
        projectDependencyReviewReports: [ProjectDependencyReviewReport],
        deviceBackupReviewReports: [DeviceBackupReviewReport],
        xcodeReviewReports: [XcodeReviewReport],
        appUninstallReceipts: [AppUninstallExecutionReceipt]
    ) {
        self.summary = summary
        self.scanSessions = scanSessions
        self.plans = plans
        self.receipts = receipts
        self.nativeToolReports = nativeToolReports
        self.nativeToolExecutionReceipts = nativeToolExecutionReceipts
        self.containerInventoryReports = containerInventoryReports
        self.remoteProbeReports = remoteProbeReports
        self.remoteScanReports = remoteScanReports
        self.remoteDogfoodReports = remoteDogfoodReports
        self.activeFileReviewReports = activeFileReviewReports
        self.trashReviewReports = trashReviewReports
        self.downloadsReviewReports = downloadsReviewReports
        self.browserCacheReviewReports = browserCacheReviewReports
        self.packageCacheReviewReports = packageCacheReviewReports
        self.projectDependencyReviewReports = projectDependencyReviewReports
        self.deviceBackupReviewReports = deviceBackupReviewReports
        self.xcodeReviewReports = xcodeReviewReports
        self.appUninstallReceipts = appUninstallReceipts
    }
}

extension AuditStoreSnapshot {
    public func latestPreviousRemoteScanReport(
        forConcreteTarget target: RemoteTargetReference,
        excludingReportID excludedID: String
    ) -> RemoteScanReport? {
        remoteScanReports.first {
            $0.id != excludedID
                && $0.coverage.level != .unreachable
                && RemoteAuditTargetMatcher.concreteTargetsMatch($0.target, target)
        }
    }

    public func latestRemoteDogfoodReport(
        forConcreteTarget target: RemoteTargetReference
    ) -> RemoteDogfoodReport? {
        remoteDogfoodReports.first {
            RemoteAuditTargetMatcher.concreteTargetsMatch($0.target, target)
        }
    }
}

enum RemoteAuditTargetMatcher {
    static func concreteTargetsMatch(_ lhs: RemoteTargetReference, _ rhs: RemoteTargetReference) -> Bool {
        if resolvedTargetsMatch(lhs, rhs) {
            return true
        }
        if hasCompleteResolvedIdentity(lhs), hasCompleteResolvedIdentity(rhs) {
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

    private static func resolvedTargetsMatch(_ lhs: RemoteTargetReference, _ rhs: RemoteTargetReference) -> Bool {
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

    private static func hasCompleteResolvedIdentity(_ target: RemoteTargetReference) -> Bool {
        normalizedIdentity(target.resolvedUser) != nil
            && normalizedIdentity(target.resolvedHost) != nil
            && target.resolvedPort != nil
    }

    private static func normalizedIdentity(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}
