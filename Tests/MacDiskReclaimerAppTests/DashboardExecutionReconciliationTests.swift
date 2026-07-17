import Foundation
import XCTest
@testable import MacDiskReclaimerApp
import ReclaimerCore

@MainActor
final class DashboardExecutionReconciliationTests: XCTestCase {
    func testSuccessfulTrashClearsPlanAndDryRunAndRemovesCompletedRow() async throws {
        let scratchRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("RyddiTask3Tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: scratchRoot, withIntermediateDirectories: true)
        defer {
            if FileManager.default.fileExists(atPath: scratchRoot.path) {
                try? FileManager.default.removeItem(at: scratchRoot)
            }
        }
        let previousAuditRoot = ProcessInfo.processInfo.environment["RYDDI_AUDIT_ROOT"]
        let previousConfigRoot = ProcessInfo.processInfo.environment["RYDDI_CONFIG_ROOT"]
        setenv("RYDDI_AUDIT_ROOT", scratchRoot.appendingPathComponent("audit").path, 1)
        setenv("RYDDI_CONFIG_ROOT", scratchRoot.appendingPathComponent("config").path, 1)
        defer {
            restoreEnvironment("RYDDI_AUDIT_ROOT", to: previousAuditRoot)
            restoreEnvironment("RYDDI_CONFIG_ROOT", to: previousConfigRoot)
        }
        let candidate = scratchRoot
            .appendingPathComponent("fixture/Library/Caches/Codex/cache.bin")
            .standardizedFileURL
        try FileManager.default.createDirectory(
            at: candidate.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("disposable fixture".utf8).write(to: candidate)

        let engine = try RuleEngine.bundled()
        let classification = engine.classify(
            path: candidate.path,
            isDirectory: false,
            isSymbolicLink: false
        )
        XCTAssertEqual(classification.safetyClass, .autoSafe)
        XCTAssertEqual(classification.actionKind, .trash)

        let finding = Finding(
            id: "fixture-candidate",
            scopeName: "Fixture",
            path: candidate.path,
            displayName: candidate.lastPathComponent,
            logicalSize: 18,
            allocatedSize: 18,
            isDirectory: false,
            safetyClass: classification.safetyClass,
            actionKind: classification.actionKind,
            ruleMatches: classification.matches,
            evidence: classification.evidence
        )
        let conditions = Set(classification.matches.flatMap(\.conditionGates)).map {
            PlanCondition(kind: $0, message: $0.label, isSatisfied: true)
        }
        let plan = ReclaimPlan(
            id: "fixture-plan",
            mode: PlanMode.autoSafeOnly.rawValue,
            items: [
                ReclaimPlanItem(
                    finding: finding,
                    selected: true,
                    proposedAction: .trash,
                    conditions: conditions,
                    estimatedImmediateReclaim: finding.allocatedSize
                )
            ],
            dryRunSummary: []
        )
        let dryRun = ExecutionReceipt(
            id: "fixture-dry-run",
            ruleVersion: engine.version,
            mode: ExecutionMode.dryRun.rawValue,
            beforeFreeBytes: nil,
            afterFreeBytes: nil,
            actions: [
                ExecutionActionReceipt(
                    path: candidate.path,
                    action: .trash,
                    status: "dry-run",
                    message: "Would move to Trash."
                )
            ],
            userConfirmed: false
        )
        let session = ScanSession(
            id: "fixture-session-\(UUID().uuidString)",
            appVersion: "0.3.1-test",
            ruleVersion: engine.version,
            preset: .developer,
            scopeDigest: "fixture-scope",
            policyDigest: ScanSessionEvidenceBuilder.policyDigest(
                preset: .developer,
                userPathPolicy: .empty
            ),
            findingDigest: "fixture-findings",
            planDigest: plan.id,
            dryRunReceiptID: dryRun.id,
            stage: .reclaimReady
        )

        let model = DashboardModel(dependencies: .testing(scanService: NoopScanService()))
        model.findings = [finding]
        model.scanScopes = [ScanScope(name: "Fixture", root: scratchRoot)]
        model.plan = plan
        model.lastDryRunReceipt = dryRun
        model.currentScanSession = session
        let authorization = try await model.trashExecutionAuthorizationRegistry.issue(
            session: session,
            plan: plan,
            dryRunReceipt: dryRun
        )
        model.pendingTrashConfirmation = TrashConfirmationRequest(
            authorization: authorization,
            plan: plan
        )

        await model.executeConfirmedTrash()
        defer {
            if let path = model.lastExecutionReceipt?.actions.first?.resultingPath {
                try? FileManager.default.removeItem(atPath: path)
            }
        }

        XCTAssertNil(model.plan)
        XCTAssertNil(model.lastDryRunReceipt)
        XCTAssertFalse(model.findings.contains { $0.path == candidate.path })
        XCTAssertEqual(model.lastExecutionReceipt?.actions.first?.status, "done")
        XCTAssertEqual(model.actionCenterReport.primaryAction?.kind, .verifyCleanup)
    }

    private func restoreEnvironment(_ name: String, to value: String?) {
        if let value {
            setenv(name, value, 1)
        } else {
            unsetenv(name)
        }
    }
}

private struct NoopScanService: ScanServicing {
    func scanWithCoverage(
        scopes: [ScanScope],
        options: ScanOptions,
        control: ScanControl
    ) -> ScanResult {
        ScanResult(
            findings: [],
            coverage: ScanCoverage(
                state: .complete,
                requestedItemBudget: options.measurementItemBudget,
                measuredItemCount: 0,
                skippedItemCount: 0,
                rootsVisited: scopes.count,
                rootsDenied: 0,
                maximumMeasurementDepth: options.measurementDepth,
                evidence: []
            )
        )
    }
}
