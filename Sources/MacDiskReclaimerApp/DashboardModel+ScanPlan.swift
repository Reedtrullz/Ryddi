import Foundation
import ReclaimerCore

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
    func scan() async {
        let diagnosticSpan = diagnostics.begin(.scan)
        defer { diagnostics.end(diagnosticSpan) }
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
        isWorking = true
        isUpdatingPresentation = true
        let historyWarnings = auditHistoryState.warnings
        let topOffenderSort = presentationTopOffenderSort
        let topOffenderGroup = presentationTopOffenderGroup
        let largeOldMode = presentationLargeOldMode
        let largeOldSort = presentationLargeOldSort
        defer {
            if scanRequestCoordinator.finish(request) {
                isWorking = false
                isUpdatingPresentation = false
            }
        }
        do {
            let result = try await Task.detached {
                let scopes = scopePlan.scopes
                let scanner = try FileScanner(
                    ruleEngine: try RuleEngine.bundled(includingUserRules: includeUserRules),
                    openFileChecker: NoOpenFilesChecker()
                )
                let scanResult = scanner.scanWithCoverage(
                    scopes: scopes,
                    options: ScanOptions(includeOpenFileStatus: false, userPathPolicy: policy)
                )
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
                return (scopePlan.label, scopes, findings, presentation, drillDown, policy, permissions, scanResult.coverage, session, generatedAt)
            }.value
            guard scanRequestCoordinator.accepts(request) else {
                diagnostics.record(.staleScanRejected)
                return
            }
            lastScannedScopeLabel = result.0
            scanScopes = result.1
            findings = result.2
            presentationSnapshot = result.3
            overview = result.3.overview
            diskDrillDown = result.4
            userPathPolicy = result.5
            if permissionReport.coverageLevel != result.6.coverageLevel {
                diagnostics.record(.permissionCoverageChanged)
            }
            permissionReport = result.6
            scanCoverage = result.7
            reviewQueueReport = result.3.reviewQueues
            currentScanSession = result.8
            isUpdatingPresentation = false
            diskStatus = DiskStatusReader().snapshot()
            _ = try ScanHistoryStore().save(overview: result.3.overview)
            loadHistory()
            plan = nil
            lastDryRunReceipt = nil
            lastExecutionReceipt = nil
            lastScanDate = result.9
            try AuditStore().saveScanSession(result.8)
            error = nil
        } catch {
            guard scanRequestCoordinator.accepts(request) else {
                diagnostics.record(.staleScanRejected)
                return
            }
            diagnostics.record(error: .scanFailed)
            self.error = error.localizedDescription
        }
    }

    func buildPlan() async {
        isWorking = true
        defer { isWorking = false }
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
        isWorking = true
        defer { isWorking = false }
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

        isWorking = true
        let diagnosticSpan = diagnostics.begin(.trashExecution)
        defer { isWorking = false }
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
