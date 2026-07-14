import Foundation
import ReclaimerCore

private struct DashboardScanOutput: Sendable {
    let scopeLabel: String
    let scopes: [ScanScope]
    let findings: [Finding]
    let presentation: ScanPresentationSnapshot
    let drillDown: DiskDrillDownReport
    let policy: UserPathPolicy
    let permissions: PermissionAdvisorReport
    let coverage: ScanCoverage
    let session: ScanSession
    let generatedAt: Date
}

extension DashboardModel {
    func loadActionCenterAuditHistory() async {
        let state = await Task.detached {
            (try? AuditStore().listScanSessionsResult(limit: 1))
                ?? AuditStoreScanSessionListResult(sessions: [], warnings: [])
        }.value
        auditHistoryState = state
        if presentationSnapshot != nil {
            await refreshPresentationSnapshot()
        }
    }

    func refreshPresentationSnapshot(now: Date = Date()) async {
        guard !findings.isEmpty else { return }
        let diagnosticSpan = diagnostics.begin(.presentation)
        defer { diagnostics.end(diagnosticSpan) }
        presentationRevision += 1
        let revision = presentationRevision
        isUpdatingPresentation = true
        let currentFindings = findings
        let currentScopes = scanScopes.isEmpty ? selectedScopePlan.scopes : scanScopes
        let currentCoverage = scanCoverage
        let currentPermissionReport = permissionReport
        let evidence = currentEvidence
        let activeFileReview = activeFileReview
        let browserCacheReview = browserCacheReview
        let packageCacheReview = packageCacheReview
        let latestNativeReceipt = recentNativeToolExecutionReceipts.first
        let historyWarnings = auditHistoryState.warnings
        let topSort = presentationTopOffenderSort
        let topGroup = presentationTopOffenderGroup
        let largeOldMode = presentationLargeOldMode
        let largeOldSort = presentationLargeOldSort
        let snapshot = await Task.detached {
            ScanPresentationSnapshot.build(
                findings: currentFindings,
                scopes: currentScopes,
                scanCoverage: currentCoverage,
                permissionReport: currentPermissionReport,
                latestScanSession: evidence.session,
                currentPlan: evidence.plan,
                latestExecutionReceipt: evidence.executionReceipt ?? evidence.dryRunReceipt,
                activeFileReviewReport: activeFileReview,
                browserCacheReport: browserCacheReview,
                packageCacheReport: packageCacheReview,
                latestNativeToolExecutionReceipt: latestNativeReceipt,
                sessionHistoryWarnings: historyWarnings,
                topOffenderSort: topSort,
                topOffenderGroup: topGroup,
                largeOldMode: largeOldMode,
                largeOldSort: largeOldSort,
                now: now
            )
        }.value
        guard revision == presentationRevision else { return }
        presentationSnapshot = snapshot
        overview = snapshot.overview
        reviewQueueReport = snapshot.reviewQueues
        isUpdatingPresentation = false
    }

    func recordReviewSelection(_ queueID: ReviewQueueID, updatedAt: Date = Date()) {
        guard overview != nil || !findings.isEmpty else { return }
        reviewedQueueID = queueID
        currentScanSession = sessionForCurrentFindings(updatedAt: updatedAt)
            .recordReviewSelection(updatedAt: updatedAt)
        Task { await refreshPresentationSnapshot(now: updatedAt) }
    }

    private func recordScanSession(updatedAt: Date) throws {
        reviewedQueueID = nil
        let session = freshScanSession(updatedAt: updatedAt)
            .recordScan(findingDigest: actionCenterFindingDigest, updatedAt: updatedAt)
        currentScanSession = session
        try AuditStore().saveScanSession(session)
    }

    private func recordPlanSession(_ plan: ReclaimPlan, updatedAt: Date = Date()) throws {
        currentScanSession = sessionForCurrentFindings(updatedAt: updatedAt)
            .recordPlan(planDigest: plan.id, updatedAt: updatedAt)
        if let currentScanSession {
            try AuditStore().saveScanSession(currentScanSession)
        }
    }

    private func recordDryRunSession(_ receipt: ExecutionReceipt, updatedAt: Date? = nil) throws {
        guard let plan else { return }
        let transitionDate = updatedAt ?? receipt.createdAt
        currentScanSession = sessionForCurrentFindings(updatedAt: transitionDate)
            .recordPlan(planDigest: plan.id, updatedAt: transitionDate)
            .recordDryRunReceipt(receipt, updatedAt: transitionDate)
        if let currentScanSession {
            try AuditStore().saveScanSession(currentScanSession)
        }
    }

    private func recordExecutionSession(_ receipt: ExecutionReceipt, updatedAt: Date? = nil) {
        let transitionDate = updatedAt ?? receipt.createdAt
        currentScanSession = sessionForCurrentFindings(updatedAt: transitionDate)
            .recordExecutionReceipt(receipt, updatedAt: transitionDate)
    }

    private func sessionForCurrentFindings(updatedAt: Date) -> ScanSession {
        let scopeDigest = actionCenterScopeDigest
        let policyDigest = actionCenterPolicyDigest
        if let currentScanSession,
           currentScanSession.scopeDigest == scopeDigest,
           currentScanSession.ruleVersion == actionCenterRuleVersion,
           currentScanSession.policyDigest == policyDigest,
           currentScanSession.findingDigest != nil,
           currentScanSession.stage != .invalidated {
            return currentScanSession
        }
        return freshScanSession(updatedAt: updatedAt)
            .recordScan(findingDigest: actionCenterFindingDigest, updatedAt: updatedAt)
    }

    private func freshScanSession(updatedAt: Date) -> ScanSession {
        ScanSession(
            id: currentScanSession?.id ?? "app-session-\(UUID().uuidString)",
            createdAt: currentScanSession?.createdAt ?? lastScanDate ?? updatedAt,
            updatedAt: updatedAt,
            appVersion: actionCenterAppVersion,
            ruleVersion: actionCenterRuleVersion,
            preset: actionCenterPreset,
            scopeDigest: actionCenterScopeDigest,
            policyDigest: actionCenterPolicyDigest,
            stage: .notStarted
        )
    }
    func startScan() {
        guard scanTask == nil else { return }
        let token = ScanCancellationToken()
        let activityID = activities.begin(.scan, message: "Preparing scan")
        scanCancellation = token
        scanActivityID = activityID
        let progressHandler = scanProgressHandler(activityID: activityID)
        scanTask = Task { [weak self] in
            guard let self else { return }
            await self.performScan(
                control: ScanControl(cancellation: token, progress: progressHandler),
                activityID: activityID
            )
            self.completeScanOperation(activityID: activityID)
        }
    }

    func scan() async {
        startScan()
        let currentTask = scanTask
        await currentTask?.value
    }

    private func performScan(control: ScanControl, activityID: UUID) async {
        let diagnosticSpan = diagnostics.begin(.scan)
        defer { diagnostics.end(diagnosticSpan) }
        guard !control.cancellation.isCancelled else { return }
        let scopePlan = selectedScopePlan
        let includeUserRules = includeUserRulesInScans
        let policy = UserPathPolicyStore().load()
        let appVersion = actionCenterAppVersion
        let ruleVersion = actionCenterRuleVersion
        let preset = scopePlan.preset ?? scanPreset
        let request = ScanRequestIdentity(
            preset: preset,
            scopeDigest: ScanSessionEvidenceBuilder.scopeDigest(
                appVersion: appVersion,
                ruleVersion: ruleVersion,
                preset: preset,
                scopes: scopePlan.scopes,
                userPathPolicy: policy
            ),
            ruleVersion: ruleVersion,
            policyDigest: ScanSessionEvidenceBuilder.policyDigest(
                preset: preset,
                userPathPolicy: policy
            )
        )
        scanRequestCoordinator.begin(request)
        isUpdatingPresentation = true
        let historyWarnings = auditHistoryState.warnings
        let topOffenderSort = presentationTopOffenderSort
        let topOffenderGroup = presentationTopOffenderGroup
        let largeOldMode = presentationLargeOldMode
        let largeOldSort = presentationLargeOldSort
        defer { _ = scanRequestCoordinator.finish(request) }
        do {
            let scanService = try dependencies.makeScanService(includingUserRules: includeUserRules)
            let result = await Task.detached { () -> DashboardScanOutput? in
                let scopes = scopePlan.scopes
                let scanResult = scanService.scanWithCoverage(
                    scopes: scopes,
                    options: ScanOptions(includeOpenFileStatus: false, userPathPolicy: policy),
                    control: control
                )
                guard !control.cancellation.isCancelled else { return nil }
                let findings = scanResult.findings
                let generatedAt = Date()
                let drillDown = DiskDrillDownBuilder.build(findings: findings, scopes: scopes, maxDepth: 3, childLimit: 8)
                let findingDigest = ScanSessionEvidenceBuilder.findingDigest(
                    appVersion: appVersion,
                    ruleVersion: ruleVersion,
                    preset: preset,
                    scopes: scopes,
                    userPathPolicy: policy,
                    findings: findings
                )
                let session = ScanSession(
                    id: "app-session-\(UUID().uuidString)",
                    createdAt: generatedAt,
                    updatedAt: generatedAt,
                    appVersion: appVersion,
                    ruleVersion: ruleVersion,
                    preset: preset,
                    scopeDigest: request.scopeDigest,
                    policyDigest: request.policyDigest,
                    stage: .notStarted
                )
                .recordScan(findingDigest: findingDigest, updatedAt: generatedAt)
                let presentation = ScanPresentationSnapshot.build(
                    findings: findings,
                    scopes: scopes,
                    scanCoverage: scanResult.coverage,
                    latestScanSession: session,
                    sessionHistoryWarnings: historyWarnings,
                    topOffenderSort: topOffenderSort,
                    topOffenderGroup: topOffenderGroup,
                    largeOldMode: largeOldMode,
                    largeOldSort: largeOldSort,
                    now: generatedAt
                )
                let permissions = PermissionAdvisor.report(
                    scopeSummaries: presentation.overview.scopeSummaries,
                    now: generatedAt
                )
                guard !control.cancellation.isCancelled else { return nil }
                return DashboardScanOutput(
                    scopeLabel: scopePlan.label,
                    scopes: scopes,
                    findings: findings,
                    presentation: presentation,
                    drillDown: drillDown,
                    policy: policy,
                    permissions: permissions,
                    coverage: scanResult.coverage,
                    session: session,
                    generatedAt: generatedAt
                )
            }.value
            guard !control.cancellation.isCancelled,
                  !Task.isCancelled,
                  activities.isCurrent(.scan, id: activityID),
                  scanRequestCoordinator.accepts(request),
                  let result else {
                diagnostics.record(.staleScanRejected)
                return
            }
            lastScannedScopeLabel = result.scopeLabel
            scanScopes = result.scopes
            findings = result.findings
            presentationSnapshot = result.presentation
            overview = result.presentation.overview
            diskDrillDown = result.drillDown
            userPathPolicy = result.policy
            if permissionReport.coverageLevel != result.permissions.coverageLevel {
                diagnostics.record(.permissionCoverageChanged)
            }
            permissionReport = result.permissions
            scanCoverage = result.coverage
            reviewQueueReport = result.presentation.reviewQueues
            currentScanSession = result.session
            isUpdatingPresentation = false
            diskStatus = DiskStatusReader().snapshot()
            _ = try ScanHistoryStore().save(overview: result.presentation.overview)
            loadHistory()
            plan = nil
            lastDryRunReceipt = nil
            lastExecutionReceipt = nil
            lastScanDate = result.generatedAt
            try AuditStore().saveScanSession(result.session)
            error = nil
        } catch {
            guard !control.cancellation.isCancelled,
                  !Task.isCancelled,
                  activities.isCurrent(.scan, id: activityID),
                  scanRequestCoordinator.accepts(request) else {
                diagnostics.record(.staleScanRejected)
                return
            }
            diagnostics.record(error: .scanFailed)
            self.error = error.localizedDescription
            activities.fail(.scan, id: activityID, message: "Scan failed")
        }
    }

    private func completeScanOperation(activityID: UUID) {
        guard scanActivityID == activityID else { return }
        activities.finish(.scan, id: activityID)
        scanActivityID = nil
        scanCancellation = nil
        scanTask = nil
        isUpdatingPresentation = false
    }

    private func scanProgressHandler(activityID: UUID) -> @Sendable (ScanProgress) -> Void {
        { [weak self] progress in
            guard progress.phase != .measuring
                    || progress.measuredItemCount == 0
                    || progress.measuredItemCount.isMultiple(of: 100) else { return }
            Task { @MainActor [weak self] in
                self?.recordScanProgress(progress, activityID: activityID)
            }
        }
    }

    private func recordScanProgress(_ progress: ScanProgress, activityID: UUID) {
        let fraction: Double? = progress.requestedItemBudget > 0
            ? min(1, Double(progress.measuredItemCount) / Double(progress.requestedItemBudget))
            : nil
        let message: String
        switch progress.phase {
        case .preparing:
            message = "Preparing scan"
        case .measuring:
            let count = progress.measuredItemCount.formatted()
            if let scopeName = safeProgressScopeName(progress.scopeName) {
                message = "Measuring \(scopeName): \(count) items"
            } else {
                message = "Measured \(count) items"
            }
        case .classifying:
            message = "Classifying \(progress.measuredItemCount.formatted()) items"
        case .finished:
            message = "Scan finished"
        }
        activities.update(.scan, id: activityID, progress: fraction, message: message)
    }

    private func safeProgressScopeName(_ scopeName: String?) -> String? {
        guard let scopeName,
              !scopeName.contains("/"),
              !scopeName.contains("\\"),
              !scopeName.contains("~") else { return nil }
        return String(scopeName.prefix(80))
    }

    func buildPlan() async {
        let activityID = activities.begin(.review, message: "Building plan")
        defer { activities.finish(.review, id: activityID) }
        await buildPlanWithoutChangingWorkingState()
    }

    private func buildPlanWithoutChangingWorkingState() async {
        let diagnosticSpan = diagnostics.begin(.plan)
        defer { diagnostics.end(diagnosticSpan) }
        let currentFindings = findings
        let builtPlan = await Task.detached {
            let builder = PlanBuilder(openFileChecker: LsofOpenFileChecker())
            return builder.buildPlan(from: currentFindings, mode: .autoSafeOnly)
        }.value
        plan = builtPlan
        lastDryRunReceipt = nil
        lastExecutionReceipt = nil
        do {
            try recordPlanSession(builtPlan)
        } catch {
            diagnostics.record(error: .planAuditFailed)
            self.error = "The plan was built, but its audit state could not be saved: \(error.localizedDescription)"
            return
        }
        await refreshPresentationSnapshot()
        error = nil
    }

    func runDryRun() async {
        let diagnosticSpan = diagnostics.begin(.dryRun)
        defer { diagnostics.end(diagnosticSpan) }
        let activityID = activities.begin(.cleanup, message: "Preparing dry run")
        defer { activities.finish(.cleanup, id: activityID) }
        do {
            if plan == nil {
                await buildPlanWithoutChangingWorkingState()
            }
            guard let plan else { return }
            let includeUserRules = includeUserRulesInScans
            let session = currentScanSession
            let receipt = try await Task.detached {
                let ruleVersion = try RuleEngine.bundled(includingUserRules: includeUserRules).version
                let policy = UserPathPolicyStore().load()
                return ReclaimerExecutor(
                    openFileChecker: LsofOpenFileChecker(),
                    configuration: ExecutorConfiguration(userPathPolicy: policy, currentScanSession: session)
                )
                    .execute(
                    plan: plan,
                    mode: .dryRun,
                    ruleVersion: ruleVersion,
                    userConfirmed: false
                )
            }.value
            lastDryRunReceipt = receipt
            lastExecutionReceipt = nil
            try recordDryRunSession(receipt)
            _ = try AuditStore().save(plan: plan)
            _ = try AuditStore().save(receipt: receipt)
            loadAudit()
            loadRecovery()
            await refreshPresentationSnapshot()
        } catch {
            diagnostics.record(error: .dryRunFailed)
            self.error = error.localizedDescription
        }
    }

    func prepareTrashExecution() async {
        let evidence = currentEvidence
        let readiness = TrashExecutionReadiness.evaluate(
            session: evidence.session,
            plan: evidence.plan,
            dryRunReceipt: evidence.dryRunReceipt
        )
        guard readiness.isReady,
              let session = evidence.session,
              let plan = evidence.plan,
              let receipt = evidence.dryRunReceipt else {
            error = readiness.reason
            return
        }

        do {
            let readySession = session.markReclaimReady()
            let authorization = try await trashExecutionAuthorizationRegistry.issue(
                session: readySession,
                plan: plan,
                dryRunReceipt: receipt
            )
            currentScanSession = readySession
            pendingTrashConfirmation = TrashConfirmationRequest(
                authorization: authorization,
                plan: plan
            )
            try AuditStore().saveScanSession(readySession)
            await refreshPresentationSnapshot()
            error = nil
        } catch {
            self.error = "Trash authorization failed: \(error.localizedDescription)"
        }
    }

    func cancelPendingTrashExecution() async {
        guard let pendingTrashConfirmation else { return }
        await trashExecutionAuthorizationRegistry.revoke(id: pendingTrashConfirmation.authorizationID)
        self.pendingTrashConfirmation = nil
    }

    func executeConfirmedTrash() async {
        guard let request = pendingTrashConfirmation,
              let plan,
              let session = currentScanSession else {
            error = "The Trash confirmation is no longer current. Run a new dry run."
            return
        }

        let activityID = activities.begin(.cleanup, message: "Moving approved items to Trash")
        let diagnosticSpan = diagnostics.begin(.trashExecution)
        defer { activities.finish(.cleanup, id: activityID) }
        defer { diagnostics.end(diagnosticSpan) }
        let includeUserRules = includeUserRulesInScans
        let policy = UserPathPolicyStore().load()
        let registry = trashExecutionAuthorizationRegistry
        do {
            let ruleVersion = try RuleEngine.bundled(includingUserRules: includeUserRules).version
            let receipt = await Task.detached(priority: .userInitiated) {
                await ReclaimerExecutor(
                    openFileChecker: LsofOpenFileChecker(),
                    configuration: ExecutorConfiguration(
                        userPathPolicy: policy,
                        currentScanSession: session
                    )
                ).executeAuthorizedTrash(
                    plan: plan,
                    authorizationID: request.authorizationID,
                    authorizationRegistry: registry,
                    ruleVersion: ruleVersion,
                    userConfirmed: true
                )
            }.value

            lastExecutionReceipt = receipt
            recordExecutionSession(receipt)
            pendingTrashConfirmation = nil
            _ = try AuditStore().save(receipt: receipt)
            if let currentScanSession {
                try AuditStore().saveScanSession(currentScanSession)
            }
            loadAudit()
            loadRecovery()
            diskStatus = DiskStatusReader().snapshot()
            let moved = receipt.actions.filter { $0.status == "done" }.count
            let blocked = receipt.actions.count - moved
            trashExecutionMessage = "Moved \(moved) item\(moved == 1 ? "" : "s") to Trash. \(blocked) skipped."
            await refreshPresentationSnapshot()
            error = receipt.errors.isEmpty ? nil : receipt.errors.joined(separator: "\n")
        } catch {
            diagnostics.record(error: .trashExecutionFailed)
            self.error = error.localizedDescription
        }
    }

}
