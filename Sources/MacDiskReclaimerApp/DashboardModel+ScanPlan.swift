import Foundation
import ReclaimerCore

extension DashboardModel {
    func recordReviewSelection(_ queueID: ReviewQueueID, updatedAt: Date = Date()) {
        guard overview != nil || !findings.isEmpty else { return }
        reviewedQueueID = queueID
        currentScanSession = sessionForCurrentFindings(updatedAt: updatedAt)
            .recordReviewSelection(findingDigest: actionCenterFindingDigest, updatedAt: updatedAt)
    }

    private func recordScanSession(updatedAt: Date) throws {
        reviewedQueueID = nil
        let session = freshScanSession(updatedAt: updatedAt)
            .recordScan(findingDigest: actionCenterFindingDigest, updatedAt: updatedAt)
        currentScanSession = session
        try AuditStore().saveScanSession(session)
    }

    private func recordPlanSession(_ plan: ReclaimPlan, updatedAt: Date = Date()) {
        currentScanSession = sessionForCurrentFindings(updatedAt: updatedAt)
            .recordPlan(planDigest: plan.id, updatedAt: updatedAt)
    }

    private func recordDryRunSession(_ receipt: ExecutionReceipt, updatedAt: Date? = nil) {
        guard let plan else { return }
        let transitionDate = updatedAt ?? receipt.createdAt
        currentScanSession = sessionForCurrentFindings(updatedAt: transitionDate)
            .recordPlan(planDigest: plan.id, updatedAt: transitionDate)
            .recordDryRunReceipt(receipt, updatedAt: transitionDate)
    }

    private func recordExecutionSession(_ receipt: ExecutionReceipt, updatedAt: Date? = nil) {
        let transitionDate = updatedAt ?? receipt.createdAt
        currentScanSession = sessionForCurrentFindings(updatedAt: transitionDate)
            .recordExecutionReceipt(receipt, updatedAt: transitionDate)
    }

    private func sessionForCurrentFindings(updatedAt: Date) -> ScanSession {
        if let currentScanSession,
           currentScanSession.scopeDigest == actionCenterScopeDigest,
           currentScanSession.ruleVersion == actionCenterRuleVersion,
           currentScanSession.policyDigest == actionCenterPolicyDigest,
           currentScanSession.findingDigest == actionCenterFindingDigest,
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
        isWorking = true
        defer { isWorking = false }
        do {
            let scopePlan = selectedScopePlan
            let includeUserRules = includeUserRulesInScans
            let result = try await Task.detached {
                let scopes = scopePlan.scopes
                let policy = UserPathPolicyStore().load()
                let scanner = try FileScanner(
                    ruleEngine: try RuleEngine.bundled(includingUserRules: includeUserRules),
                    openFileChecker: NoOpenFilesChecker()
                )
                let findings = scanner.scan(
                    scopes: scopes,
                    options: ScanOptions(includeOpenFileStatus: false, userPathPolicy: policy)
                )
                let overview = FindingAnalytics.overview(findings: findings, scopes: scopes)
                let drillDown = DiskDrillDownBuilder.build(findings: findings, scopes: scopes, maxDepth: 3, childLimit: 8)
                return (scopePlan.label, scopes, findings, overview, drillDown, policy, PermissionAdvisor.report(scopeSummaries: overview.scopeSummaries))
            }.value
            lastScannedScopeLabel = result.0
            scanScopes = result.1
            findings = result.2
            overview = result.3
            diskDrillDown = result.4
            userPathPolicy = result.5
            permissionReport = result.6
            diskStatus = DiskStatusReader().snapshot()
            _ = try ScanHistoryStore().save(overview: result.3)
            loadHistory()
            plan = nil
            lastDryRunReceipt = nil
            lastExecutionReceipt = nil
            lastScanDate = Date()
            try recordScanSession(updatedAt: lastScanDate ?? Date())
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func buildPlan() async {
        isWorking = true
        defer { isWorking = false }
        await buildPlanWithoutChangingWorkingState()
    }

    private func buildPlanWithoutChangingWorkingState() async {
        let currentFindings = findings
        let builtPlan = await Task.detached {
            let builder = PlanBuilder(openFileChecker: LsofOpenFileChecker())
            return builder.buildPlan(from: currentFindings, mode: .autoSafeOnly)
        }.value
        plan = builtPlan
        lastDryRunReceipt = nil
        lastExecutionReceipt = nil
        recordPlanSession(builtPlan)
        error = nil
    }

    func runDryRun() async {
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
            recordDryRunSession(receipt)
            _ = try AuditStore().save(plan: plan)
            _ = try AuditStore().save(receipt: receipt)
            loadAudit()
            loadRecovery()
        } catch {
            self.error = error.localizedDescription
        }
    }

}
