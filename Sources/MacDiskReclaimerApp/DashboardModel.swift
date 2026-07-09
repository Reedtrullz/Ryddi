import Foundation
import SwiftUI
import ReclaimerCore

@MainActor
@Observable
final class DashboardModel {
    var findings: [Finding] = []
    var scanScopes: [ScanScope] = []
    var scanPreset: ScanScopePreset = .developer
    var selectedScopeTemplateID: String?
    var savedScopeSets: [SavedScopeSet] = []
    var selectedSavedScopeSetID: String?
    var includeUserRulesInScans = false
    var lastScannedScopeLabel: String?
    var overview: ScanOverview?
    var diskDrillDown: DiskDrillDownReport?
    var plan: ReclaimPlan?
    var lastDryRunReceipt: ExecutionReceipt?
    var lastExecutionReceipt: ExecutionReceipt?
    var recentPlans: [ReclaimPlan] = []
    var recentReceipts: [ExecutionReceipt] = []
    var auditStoreSummary: AuditStoreSummary?
    var auditPrunePlan: AuditPrunePlan?
    var auditPruneReceipt: AuditPruneReceipt?
    var recentNativeToolReports: [NativeToolReport] = []
    var recentNativeToolExecutionReceipts: [NativeToolExecutionReceipt] = []
    var recentContainerInventoryReports: [ContainerInventoryReport] = []
    var recentRemoteProbeReports: [RemoteProbeReport] = []
    var recentRemoteScanReports: [RemoteScanReport] = []
    var recentRemoteDogfoodReports: [RemoteDogfoodReport] = []
    var recentActiveFileReviewReports: [ActiveFileReviewReport] = []
    var recentTrashReviewReports: [TrashReviewReport] = []
    var recentDownloadsReviewReports: [DownloadsReviewReport] = []
    var recentBrowserCacheReviewReports: [BrowserCacheReviewReport] = []
    var recentPackageCacheReviewReports: [PackageCacheReviewReport] = []
    var recentProjectDependencyReviewReports: [ProjectDependencyReviewReport] = []
    var recentDeviceBackupReviewReports: [DeviceBackupReviewReport] = []
    var recentXcodeReviewReports: [XcodeReviewReport] = []
    var recentAppUninstallReceipts: [AppUninstallExecutionReceipt] = []
    var heldItems: [HeldItem] = []
    var recoveryReport: RecoveryCenterReport = RecoveryCenter.build(heldItems: [], receipts: [])
    var duplicateReview: DuplicateReview?
    var appReview: AppReviewReport?
    var appUninstallPreview: AppUninstallPreview?
    var lastAppUninstallDryRunReceipt: AppUninstallExecutionReceipt?
    var lastAppUninstallReceipt: AppUninstallExecutionReceipt?
    var agentStorageReview: AgentStorageReview?
    var agentRetentionReport: AgentRetentionReport?
    var containerInventory: ContainerInventoryReport?
    var remoteTargets: [RemoteTargetReference] = []
    var remoteTargetInput = ""
    var remoteProbeReport: RemoteProbeReport?
    var remoteScanReport: RemoteScanReport?
    var remoteGrowthReport: RemoteGrowthReport?
    var remoteDogfoodReport: RemoteDogfoodReport?
    var currentRemoteDogfoodReport: RemoteDogfoodReport? {
        guard let dogfood = remoteDogfoodReport else { return nil }
        guard let scan = remoteScanReport else { return dogfood }
        return dogfood.target.id == scan.target.id ? dogfood : nil
    }
    var activeFileReview: ActiveFileReviewReport?
    var trashReview: TrashReviewReport?
    var downloadsReview: DownloadsReviewReport?
    var browserCacheReview: BrowserCacheReviewReport?
    var packageCacheReview: PackageCacheReviewReport?
    var projectDependencyReview: ProjectDependencyReviewReport?
    var deviceBackupReview: DeviceBackupReviewReport?
    var xcodeReview: XcodeReviewReport?
    var userPathPolicy: UserPathPolicy = .empty
    var lastReportExportURL: URL?
    var lastPlanReportExportURL: URL?
    var lastReceiptReportExportURL: URL?
    var lastGrowthReportExportURL: URL?
    var lastArchiveReviewExportURL: URL?
    var lastRemoteReportExportURL: URL?
    var lastRemoteGrowthReportExportURL: URL?
    var lastRemoteDogfoodReportExportURL: URL?
    var lastPolicyExportURL: URL?
    var lastScopeSetExportURL: URL?
    var lastScopeSetImportResult: SavedScopeSetImportResult?
    var diskStatus: DiskStatusSnapshot = DiskStatusReader().snapshot()
    var permissionReport: PermissionAdvisorReport = PermissionAdvisor.report(scopes: DefaultScopes.scopes(for: .developer, includeUnavailable: true))
    var scanSnapshots: [ScanSnapshot] = []
    var growthDeltas: [BucketGrowthDelta] = []
    var isWorking = false
    var lastScanDate: Date?
    var launchAgentInstalled = false
    var launchAgentStatus: LaunchAgentStatus = LaunchAgentManager().status()
    var error: String?
    var currentScanSession: ScanSession?
    var reviewedQueueID: ReviewQueueID?
    var hasAppliedStoredSettings = false

    var selectedScopePlan: ScanScopePlan {
        if let selectedSavedScopeSet {
            return selectedSavedScopeSet.plan
        }
        if let selectedScopeTemplate {
            return selectedScopeTemplate.plan
        }
        return DefaultScopes.plan(for: scanPreset, includeUnavailable: true)
    }

    var currentAppUninstallReceipt: AppUninstallExecutionReceipt? {
        lastAppUninstallReceipt ?? lastAppUninstallDryRunReceipt
    }

    var canTrashPreviewedApp: Bool {
        guard let preview = appUninstallPreview,
              let receipt = lastAppUninstallDryRunReceipt,
              receipt.previewID == preview.id,
              receipt.authorizationDigest == preview.bundleAuthorizationDigest else {
            return false
        }
        let age = Date().timeIntervalSince(receipt.createdAt)
        return receipt.status == "dry-run"
            && receipt.errors.isEmpty
            && age >= 0
            && age <= AppUninstallExecutorConfiguration.maximumDryRunAuthorizationAge
            && preview.bundleCandidate.disposition == .trashPreview
    }

    var scopeTemplates: [ScopeTemplate] {
        ScopeTemplateCatalog.all(includeUnavailable: true)
    }

    var selectedScopeTemplate: ScopeTemplate? {
        guard let selectedScopeTemplateID else { return nil }
        return try? ScopeTemplateCatalog.find(selectedScopeTemplateID, includeUnavailable: true)
    }

    var selectedSavedScopeSet: SavedScopeSet? {
        guard let selectedSavedScopeSetID else { return nil }
        return savedScopeSets.first { $0.id == selectedSavedScopeSetID }
    }

    var reviewQueueReport: ReviewQueueReport {
        FindingAnalytics.reviewQueueReport(findings: findings, limitPerQueue: 12)
    }

    var trustReadinessReport: TrustReadinessReport {
        TrustReadinessBuilder.build(
            diskStatus: diskStatus,
            permissionSummary: permissionReport,
            findings: findings,
            latestPlan: plan ?? recentPlans.first,
            latestReceipt: lastExecutionReceipt ?? lastDryRunReceipt ?? recentReceipts.first,
            automationInstalled: launchAgentStatus.installed,
            signingState: "App runtime; verify signed and notarized releases with the manifest",
            releaseTrustEvidence: ReleaseTrustEvidenceLoader.load()
        )
    }

    var guidedWorkflowReport: GuidedWorkflowReport {
        GuidedWorkflowBuilder.build(
            input: GuidedWorkflowInput(
                diskStatus: diskStatus,
                permissionSummary: permissionReport,
                findings: findings,
                latestPlan: plan ?? recentPlans.first,
                latestReceipt: lastExecutionReceipt ?? lastDryRunReceipt ?? recentReceipts.first,
                trustReadiness: trustReadinessReport
            )
        )
    }

    var actionCenterReport: ActionCenterReport {
        let scanSessionHistory = actionCenterScanSessionHistory
        return ActionCenterBuilder.build(
            input: ActionCenterInput(
                permissionReport: permissionReport,
                latestScanSession: actionCenterScanSession,
                findings: findings,
                currentPlan: plan,
                latestExecutionReceipt: lastDryRunReceipt ?? lastExecutionReceipt,
                reviewQueueReport: reviewQueueReport,
                activeFileReviewReport: activeFileReview,
                browserCacheReport: browserCacheReview,
                packageCacheReport: packageCacheReview,
                latestNativeToolExecutionReceipt: recentNativeToolExecutionReceipts.first,
                sessionHistoryWarnings: scanSessionHistory.warnings
            )
        )
    }

    private var actionCenterScanSessionHistory: AuditStoreScanSessionListResult {
        (try? AuditStore().listScanSessionsResult(limit: 1)) ?? AuditStoreScanSessionListResult(sessions: [], warnings: [])
    }

    var actionCenterScanSession: ScanSession? {
        if let currentScanSession {
            return currentScanSession
        }
        return fallbackActionCenterScanSession
    }

    private var fallbackActionCenterScanSession: ScanSession? {
        guard overview != nil || !findings.isEmpty || plan != nil || lastDryRunReceipt != nil || lastExecutionReceipt != nil else {
            return nil
        }

        let updatedAt = lastExecutionReceipt?.createdAt
            ?? lastDryRunReceipt?.createdAt
            ?? plan?.createdAt
            ?? lastScanDate
            ?? Date()
        let hasFindingEvidence = overview != nil || !findings.isEmpty

        return ScanSession(
            id: "app-summary-\(actionCenterSessionStage.rawValue)",
            createdAt: lastScanDate ?? updatedAt,
            updatedAt: updatedAt,
            appVersion: actionCenterAppVersion,
            ruleVersion: actionCenterRuleVersion,
            preset: actionCenterPreset,
            scopeDigest: actionCenterScopeDigest,
            policyDigest: actionCenterPolicyDigest,
            findingDigest: hasFindingEvidence ? actionCenterFindingDigest : nil,
            planDigest: plan?.id,
            dryRunReceiptID: nil,
            executionReceiptID: lastExecutionReceipt?.id,
            stage: actionCenterSessionStage
        )
    }

    private var actionCenterSessionStage: ScanSessionStage {
        if lastExecutionReceipt != nil {
            return .executed
        }
        if lastDryRunReceipt != nil {
            return .dryRunReady
        }
        if plan != nil {
            return .planReady
        }
        if reviewedQueueID != nil {
            return .reviewed
        }
        return .scanned
    }

    var actionCenterScopeDigest: String {
        ScanSessionEvidenceBuilder.scopeDigest(
            appVersion: actionCenterAppVersion,
            ruleVersion: actionCenterRuleVersion,
            preset: actionCenterPreset,
            scopes: actionCenterScopes,
            userPathPolicy: userPathPolicy
        )
    }

    var actionCenterPolicyDigest: String {
        ScanSessionEvidenceBuilder.policyDigest(
            preset: actionCenterPreset,
            userPathPolicy: userPathPolicy
        )
    }

    var actionCenterFindingDigest: String {
        ScanSessionEvidenceBuilder.findingDigest(
            appVersion: actionCenterAppVersion,
            ruleVersion: actionCenterRuleVersion,
            preset: actionCenterPreset,
            scopes: actionCenterScopes,
            userPathPolicy: userPathPolicy,
            findings: findings
        )
    }

    private var actionCenterScopes: [ScanScope] {
        scanScopes.isEmpty ? selectedScopePlan.scopes : scanScopes
    }

    var actionCenterPreset: ScanScopePreset {
        selectedScopePlan.preset ?? scanPreset
    }

    var actionCenterAppVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "app-runtime"
    }

    var actionCenterRuleVersion: String {
        includeUserRulesInScans ? "app-runtime+user-rules" : "app-runtime"
    }

    var queueSummaries: [ReviewQueueSummary] {
        reviewQueueReport.queues
    }

    var totalReviewBytes: Int64 {
        findings
            .filter { [.safeAfterCondition, .reviewRequired, .preserveByDefault].contains($0.safetyClass) }
            .reduce(0) { $0 + $1.allocatedSize }
    }

    var selectedPlanCount: Int {
        plan?.items.filter(\.selected).count ?? 0
    }

    var canReclaimSelected: Bool {
        guard let plan, selectedPlanCount > 0 else { return false }
        guard let receipt = lastDryRunReceipt, receipt.mode == ExecutionMode.dryRun.rawValue else { return false }
        guard receipt.createdAt >= plan.createdAt else { return false }
        guard dryRunReceiptMatchesCurrentSession(plan: plan, receipt: receipt) else { return false }
        return receipt.actions.allSatisfy { $0.status == "dry-run" } && receipt.errors.isEmpty
    }

    private func dryRunReceiptMatchesCurrentSession(plan: ReclaimPlan, receipt: ExecutionReceipt) -> Bool {
        guard let currentScanSession else { return false }
        guard [.dryRunReady, .reclaimReady].contains(currentScanSession.stage) else { return false }
        return currentScanSession.planDigest == plan.id
            && currentScanSession.dryRunReceiptID == receipt.id
    }

    var reclaimConfirmationMessage: String {
        guard let plan else {
            return "No reclaim plan is available."
        }
        return "This will execute \(selectedPlanCount) selected auto-safe action(s), expected immediate reclaim \(ByteFormat.string(plan.expectedImmediateReclaim)). A receipt will be saved locally."
    }

    func applyStoredSettings(defaultScanPresetRaw: String, includeUserRulesByDefault: Bool) {
        guard !hasAppliedStoredSettings else { return }
        hasAppliedStoredSettings = true

        if let defaultPreset = ScanScopePreset(rawValue: defaultScanPresetRaw) {
            scanPreset = defaultPreset
        }
        includeUserRulesInScans = includeUserRulesByDefault
        permissionReport = PermissionAdvisor.report(scopes: currentScopes(includeUnavailable: true))
    }

    func setScanPreset(_ preset: ScanScopePreset) {
        guard scanPreset != preset || selectedSavedScopeSetID != nil || selectedScopeTemplateID != nil else { return }
        scanPreset = preset
        selectedScopeTemplateID = nil
        selectedSavedScopeSetID = nil
        resetScanState()
        permissionReport = PermissionAdvisor.report(scopes: currentScopes(includeUnavailable: true))
        error = nil
    }

    func setScopeTemplate(_ id: String?) {
        let normalizedID = id?.trimmingCharacters(in: .whitespacesAndNewlines)
        let nextID = normalizedID?.isEmpty == true ? nil : normalizedID
        guard selectedScopeTemplateID != nextID || selectedSavedScopeSetID != nil else { return }
        selectedScopeTemplateID = nextID
        selectedSavedScopeSetID = nil
        if nextID != nil, selectedScopeTemplate == nil {
            selectedScopeTemplateID = nil
            error = "Built-in scope template is no longer available."
        } else {
            error = nil
        }
        resetScanState()
        permissionReport = PermissionAdvisor.report(scopes: currentScopes(includeUnavailable: true))
    }

    func setSavedScopeSet(_ id: String?) {
        let normalizedID = id?.trimmingCharacters(in: .whitespacesAndNewlines)
        let nextID = normalizedID?.isEmpty == true ? nil : normalizedID
        guard selectedSavedScopeSetID != nextID || selectedScopeTemplateID != nil else { return }
        selectedSavedScopeSetID = nextID
        selectedScopeTemplateID = nil
        if nextID != nil, selectedSavedScopeSet == nil {
            selectedSavedScopeSetID = nil
            error = "Saved scope set is no longer available."
        } else {
            error = nil
        }
        resetScanState()
        permissionReport = PermissionAdvisor.report(scopes: currentScopes(includeUnavailable: true))
    }

    func setIncludeUserRulesInScans(_ include: Bool) {
        guard includeUserRulesInScans != include else { return }
        includeUserRulesInScans = include
        resetScanState()
        error = nil
    }

    func resetScanState() {
        findings = []
        scanScopes = []
        overview = nil
        diskDrillDown = nil
        plan = nil
        agentStorageReview = nil
        lastDryRunReceipt = nil
        lastExecutionReceipt = nil
        lastScannedScopeLabel = nil
        currentScanSession = nil
        reviewedQueueID = nil
    }

    func currentScopes(includeUnavailable: Bool) -> [ScanScope] {
        if let selectedSavedScopeSet {
            return selectedSavedScopeSet.plan.scopes
        }
        if let selectedScopeTemplateID,
           let plan = try? ScopeTemplateCatalog.plan(reference: selectedScopeTemplateID, includeUnavailable: includeUnavailable) {
            return plan.scopes
        }
        return DefaultScopes.scopes(for: scanPreset, includeUnavailable: includeUnavailable)
    }

    func totalBytes(for safetyClass: SafetyClass) -> Int64 {
        findings.filter { $0.safetyClass == safetyClass }.reduce(0) { $0 + $1.allocatedSize }
    }

    func findings(in queueID: ReviewQueueID) -> [Finding] {
        FindingAnalytics.reviewQueueRows(findings: findings, queueID: queueID)
            .map(\.finding)
    }

    func largeOldReviewReport(
        mode: LargeOldReviewMode = .all,
        sort: TopOffenderSort = .allocated,
        limit: Int = 80
    ) -> LargeOldReviewReport {
        FindingAnalytics.largeOldReviewReport(findings: findings, mode: mode, sort: sort, limit: limit)
    }

    func archiveReviewReport(
        mode: LargeOldReviewMode = .all,
        sort: TopOffenderSort = .allocated,
        limit: Int = 40,
        pathStyle: ReportPathStyle = .full
    ) -> ArchiveReviewReport {
        ArchiveReviewBuilder.build(
            findings: findings,
            mode: mode,
            sort: sort,
            limit: limit,
            privacy: ReportPrivacyOptions(pathStyle: pathStyle)
        )
    }

    func nativePerformBlockReason(receipt: NativeToolReceipt, command: NativeToolCommand) -> String? {
        nativePerformBlockReason(selection: NativeToolCommandSelection(receipt: receipt, command: command))
    }

    private func nativePerformBlockReason(selection: NativeToolCommandSelection) -> String? {
        if let reason = NativeToolExecutor.performBlockReason(for: selection.command) {
            return reason
        }
        guard let ruleVersion = try? RuleEngine.bundled(includingUserRules: includeUserRulesInScans).version else {
            return "Could not load the current rule version for native preview authorization."
        }
        if NativeToolExecutor.performAuthorization(
            authorizing: selection,
            in: recentNativeToolExecutionReceipts,
            ruleVersion: ruleVersion
        ) != nil {
            return nil
        }
        return "Run requires a fresh successful brew.preview authorization receipt for this finding. Use Dry Run first."
    }

    func planItem(for findingID: Finding.ID) -> ReclaimPlanItem? {
        plan?.items.first { $0.finding.id == findingID }
    }

}
