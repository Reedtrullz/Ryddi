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
    var scanCoverage: ScanCoverage?
    var diskDrillDown: DiskDrillDownReport?
    var plan: ReclaimPlan?
    var lastDryRunReceipt: ExecutionReceipt?
    var lastExecutionReceipt: ExecutionReceipt?
    var pendingTrashConfirmation: TrashConfirmationRequest?
    var trashExecutionMessage: String?
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
    var lastDiagnosticExportURL: URL?
    var lastScopeSetImportResult: SavedScopeSetImportResult?
    var diskStatus: DiskStatusSnapshot = DiskStatusReader().snapshot()
    var permissionReport: PermissionAdvisorReport = {
        if DashboardLaunchOptions.isE2EModeRequested {
            guard let root = DashboardLaunchOptions.e2eScopeRoot else {
                return PermissionAdvisor.report(scopes: [])
            }
            return PermissionAdvisor.report(scopes: DashboardModel.e2eScopes(root: root))
        }
        return PermissionAdvisor.report(scopes: DefaultScopes.scopes(for: .developer, includeUnavailable: true))
    }()
    var scanSnapshots: [ScanSnapshot] = []
    var growthDeltas: [BucketGrowthDelta] = []
    var activities = DashboardActivityRegistry()
    var isWorking: Bool {
        activities.isRunning(.scan)
            || activities.isRunning(.cleanup)
            || activities.isRunning(.review)
    }
    var isScanRunning: Bool { activities.isRunning(.scan) }
    var isRemoteActivityRunning: Bool { activities.isRunning(.remote) }
    var lastScanDate: Date?
    var launchAgentInstalled = false
    var launchAgentStatus: LaunchAgentStatus = LaunchAgentManager().status()
    var runtimeReleaseTrustReport: RuntimeReleaseTrustReport?
    var error: String?
    var currentScanSession: ScanSession?
    var reviewedQueueID: ReviewQueueID?
    var reviewQueueReport: ReviewQueueReport = .empty()
    var presentationSnapshot: ScanPresentationSnapshot?
    var isUpdatingPresentation = false
    var presentationTopOffenderSort: TopOffenderSort = .allocated
    var presentationTopOffenderGroup: TopOffenderGroup = .none
    var presentationLargeOldMode: LargeOldReviewMode = .all
    var presentationLargeOldSort: TopOffenderSort = .allocated
    var auditHistoryState = AuditStoreScanSessionListResult(sessions: [], warnings: [])
    var hasAppliedStoredSettings = false
    var scanRequestCoordinator = ScanRequestCoordinator()
    @ObservationIgnored var scanTask: Task<Void, Never>?
    @ObservationIgnored var scanCancellation: ScanCancellationToken?
    @ObservationIgnored var scanActivityID: UUID?
    let trashExecutionAuthorizationRegistry = TrashExecutionAuthorizationRegistry()
    let diagnostics = RyddiDiagnosticRecorder()
    let dependencies: DashboardDependencies
    private var e2eScopeRoot: URL?
    var presentationRevision = 0

    init(dependencies: DashboardDependencies = .live) {
        self.dependencies = dependencies
        Task { [weak self] in
            let report = await Task.detached(priority: .utility) {
                RuntimeReleaseTrustProbe().inspect()
            }.value
            guard !Task.isCancelled else { return }
            self?.runtimeReleaseTrustReport = report
        }
    }

    var activeScanRequest: ScanRequestIdentity? {
        scanRequestCoordinator.activeRequest
    }

    func activity(for kind: DashboardActivityKind) -> DashboardActivityState {
        activities.state(for: kind)
    }

    var selectedScopePlan: ScanScopePlan {
        if let e2eScopeRoot {
            return DefaultScopes.customPlan(
                label: "E2E fixture",
                summary: "Disposable fixture scope supplied by the bounded app E2E launch contract.",
                scopes: Self.e2eScopes(root: e2eScopeRoot)
            )
        }
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

    func configureE2EScope(_ root: URL) {
        e2eScopeRoot = root.standardizedFileURL
        selectedScopeTemplateID = nil
        selectedSavedScopeSetID = nil
    }

    private static func e2eScopes(root: URL) -> [ScanScope] {
        [
            ScanScope(name: "E2E safe cache", root: root.appendingPathComponent("Library/Caches/Codex", isDirectory: true)),
            ScanScope(name: "E2E browser profile", root: root.appendingPathComponent("Library/Application Support/Google/Chrome/Default", isDirectory: true)),
            ScanScope(name: "E2E Codex history", root: root.appendingPathComponent(".codex/sessions", isDirectory: true)),
            ScanScope(name: "E2E app bundle", root: root.appendingPathComponent("Applications/Ryddi E2E Fixture.app", isDirectory: true)),
            ScanScope(name: "E2E large-file review", root: root.appendingPathComponent("Downloads", isDirectory: true))
        ]
    }

    func reviewQueueDetailReport(for queueID: ReviewQueueID, limit: Int = 40) -> ReviewQueueDetailReport {
        reviewQueueReport.detailReport(for: queueID, limit: limit)
    }

    func refreshReviewQueueReport() {
        Task { await refreshPresentationSnapshot() }
    }

    var currentEvidence: CurrentEvidenceSnapshot {
        CurrentEvidenceResolver.resolve(
            session: currentScanSession,
            plan: plan,
            dryRunReceipt: lastDryRunReceipt,
            executionReceipt: lastExecutionReceipt
        )
    }

    var trashExecutionReadiness: TrashExecutionReadiness {
        let evidence = currentEvidence
        return TrashExecutionReadiness.evaluate(
            session: evidence.session,
            plan: evidence.plan,
            dryRunReceipt: evidence.dryRunReceipt
        )
    }

    var trustReadinessReport: TrustReadinessReport {
        let evidence = currentEvidence
        return TrustReadinessBuilder.build(
            diskStatus: diskStatus,
            permissionSummary: permissionReport,
            findings: findings,
            latestPlan: evidence.plan,
            latestReceipt: evidence.executionReceipt ?? evidence.dryRunReceipt,
            automationInstalled: launchAgentStatus.installed,
            signingState: "App runtime; verify signed and notarized releases with the manifest",
            runtimeReleaseTrustReport: runtimeReleaseTrustReport,
            scanCoverage: scanCoverage
        )
    }

    var guidedWorkflowReport: GuidedWorkflowReport {
        let evidence = currentEvidence
        return GuidedWorkflowBuilder.build(
            input: GuidedWorkflowInput(
                diskStatus: diskStatus,
                permissionSummary: permissionReport,
                findings: findings,
                latestPlan: evidence.plan,
                latestReceipt: evidence.executionReceipt ?? evidence.dryRunReceipt,
                trustReadiness: trustReadinessReport
            )
        )
    }

    var actionCenterReport: ActionCenterReport {
        if let presentationSnapshot {
            return presentationSnapshot.actionCenter
        }
        let evidence = currentEvidence
        return ActionCenterBuilder.build(
            input: ActionCenterInput(
                permissionReport: permissionReport,
                latestScanSession: evidence.session,
                findings: findings,
                currentPlan: evidence.plan,
                latestExecutionReceipt: evidence.executionReceipt ?? evidence.dryRunReceipt,
                reviewQueueReport: reviewQueueReport,
                activeFileReviewReport: activeFileReview,
                browserCacheReport: browserCacheReview,
                packageCacheReport: packageCacheReview,
                latestNativeToolExecutionReceipt: recentNativeToolExecutionReceipts.first,
                sessionHistoryWarnings: auditHistoryState.warnings
            )
        )
    }

    var actionCenterScanSession: ScanSession? {
        currentEvidence.session
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
        cancelScan()
        presentationRevision += 1
        findings = []
        reviewQueueReport = .empty()
        presentationSnapshot = nil
        isUpdatingPresentation = false
        scanScopes = []
        overview = nil
        scanCoverage = nil
        diskDrillDown = nil
        plan = nil
        agentStorageReview = nil
        lastDryRunReceipt = nil
        lastExecutionReceipt = nil
        lastScannedScopeLabel = nil
        currentScanSession = nil
        reviewedQueueID = nil
    }

    func cancelScan() {
        guard scanTask != nil else { return }
        scanCancellation?.cancel()
        scanTask?.cancel()
        scanRequestCoordinator.invalidate()
        activities.markCancelling(.scan)
        isUpdatingPresentation = false
    }

    func currentScopes(includeUnavailable: Bool) -> [ScanScope] {
        if e2eScopeRoot != nil {
            return selectedScopePlan.scopes
        }
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

    func setTopOffenderPresentation(sort: TopOffenderSort, group: TopOffenderGroup) async {
        guard presentationTopOffenderSort != sort || presentationTopOffenderGroup != group else { return }
        presentationTopOffenderSort = sort
        presentationTopOffenderGroup = group
        await refreshPresentationSnapshot()
    }

    func setLargeOldPresentation(mode: LargeOldReviewMode, sort: TopOffenderSort) async {
        guard presentationLargeOldMode != mode || presentationLargeOldSort != sort else { return }
        presentationLargeOldMode = mode
        presentationLargeOldSort = sort
        await refreshPresentationSnapshot()
    }

    func nativePerformBlockReason(receipt: NativeToolReceipt, command: NativeToolCommand) -> String? {
        nativePerformBlockReason(selection: NativeToolCommandSelection(receipt: receipt, command: command))
    }

    private func nativePerformBlockReason(selection: NativeToolCommandSelection) -> String? {
        if let maintenanceAction = NativeMaintenanceAction(rawValue: selection.command.id) {
            guard selection.command.command == maintenanceAction.performInvocation.displayCommand else {
                return "This native maintenance command does not match Ryddi's exact allowlisted invocation."
            }
            return nil
        }
        if let reason = NativeToolExecutor.performBlockReason(for: selection.command) {
            return reason
        }
        if selection.command.id == "brew.cleanup" {
            return nil
        }
        return "Confirmed native execution requires an executor-minted same-process capability. This command remains guidance-only."
    }

    func planItem(for findingID: Finding.ID) -> ReclaimPlanItem? {
        plan?.items.first { $0.finding.id == findingID }
    }

}
