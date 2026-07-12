import Foundation
import XCTest
@testable import ReclaimerCore

final class TrashExecutionAuthorizationTests: XCTestCase {
    private var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("RyddiTrashAuthorizationTests-\(UUID().uuidString)", isDirectory: true)
            .standardizedFileURL
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempRoot, FileManager.default.fileExists(atPath: tempRoot.path) {
            try FileManager.default.removeItem(at: tempRoot)
        }
    }

    func testIssuesAuthorizationForOnlySelectedAutoSafeTrashItemsFromCurrentCleanDryRun() async throws {
        let selectedURL = try makeFile(named: "selected.cache")
        let unselectedURL = try makeFile(named: "unselected.cache")
        let selected = makeItem(id: "selected", path: selectedURL.path)
        let unselected = makeItem(
            id: "unselected",
            path: unselectedURL.path,
            selected: false,
            safetyClass: .neverTouch,
            action: .deleteCache
        )
        let plan = makePlan(items: [selected, unselected])
        let receipt = makeReceipt(for: plan)
        let session = makeSession(plan: plan, receipt: receipt)
        let now = Date(timeIntervalSince1970: 10_000)
        let registry = TrashExecutionAuthorizationRegistry()

        let authorization = try await registry.issue(
            session: session,
            plan: plan,
            dryRunReceipt: receipt,
            now: now
        )

        XCTAssertEqual(authorization.sessionID, session.id)
        XCTAssertEqual(authorization.planID, plan.id)
        XCTAssertEqual(authorization.dryRunReceiptID, receipt.id)
        XCTAssertEqual(authorization.findingIDs, [selected.id])
        XCTAssertEqual(authorization.identities.keys.sorted(), [selected.id])
        XCTAssertEqual(authorization.identities[selected.id]?.standardizedPath, selectedURL.standardizedFileURL.path)
        XCTAssertEqual(authorization.issuedAt, now)
        XCTAssertEqual(authorization.expiresAt, now.addingTimeInterval(15 * 60))
    }

    func testRejectsSessionThatIsNotCurrentReclaimReady() async throws {
        let item = makeItem(path: try makeFile(named: "stage.cache").path)
        let plan = makePlan(items: [item])
        let receipt = makeReceipt(for: plan)
        let registry = TrashExecutionAuthorizationRegistry()

        for stage in [ScanSessionStage.dryRunReady, .executed, .invalidated] {
            let session = makeSession(plan: plan, receipt: receipt, stage: stage)
            await assertAuthorizationError(.sessionNotReclaimReady) {
                _ = try await registry.issue(session: session, plan: plan, dryRunReceipt: receipt)
            }
        }
    }

    func testRejectsMismatchedPlanAndDryRunReceiptBindings() async throws {
        let item = makeItem(path: try makeFile(named: "binding.cache").path)
        let plan = makePlan(items: [item])
        let receipt = makeReceipt(for: plan)
        let registry = TrashExecutionAuthorizationRegistry()

        let wrongPlanSession = makeSession(plan: plan, receipt: receipt, planDigest: "different-plan")
        await assertAuthorizationError(.planMismatch) {
            _ = try await registry.issue(session: wrongPlanSession, plan: plan, dryRunReceipt: receipt)
        }

        let wrongReceiptSession = makeSession(plan: plan, receipt: receipt, receiptID: "different-receipt")
        await assertAuthorizationError(.dryRunReceiptMismatch) {
            _ = try await registry.issue(session: wrongReceiptSession, plan: plan, dryRunReceipt: receipt)
        }
    }

    func testRejectsDirtyOrNonMatchingDryRunReceipt() async throws {
        let item = makeItem(path: try makeFile(named: "receipt.cache").path)
        let plan = makePlan(items: [item])
        let cleanReceipt = makeReceipt(for: plan)
        let session = makeSession(plan: plan, receipt: cleanReceipt)
        let registry = TrashExecutionAuthorizationRegistry()

        let dirtyReceipt = makeReceipt(for: plan, id: cleanReceipt.id, errors: ["preflight failed"])
        await assertAuthorizationError(.uncleanDryRunReceipt) {
            _ = try await registry.issue(session: session, plan: plan, dryRunReceipt: dirtyReceipt)
        }

        let mismatchedActions = ExecutionReceipt(
            id: cleanReceipt.id,
            ruleVersion: "rules-v1",
            mode: ExecutionMode.dryRun.rawValue,
            beforeFreeBytes: nil,
            afterFreeBytes: nil,
            actions: [],
            userConfirmed: false
        )
        await assertAuthorizationError(.dryRunActionsMismatch) {
            _ = try await registry.issue(session: session, plan: plan, dryRunReceipt: mismatchedActions)
        }
    }

    func testRejectsNonAutoSafeAndUnsatisfiedSelectedTrashItems() async throws {
        let path = try makeFile(named: "eligibility.cache").path
        let registry = TrashExecutionAuthorizationRegistry()

        let reviewItem = makeItem(path: path, safetyClass: .reviewRequired)
        await assertRejectedPlan(item: reviewItem, expected: .ineligibleFinding(reviewItem.id), registry: registry)

        let blockedItem = makeItem(path: path, conditionsSatisfied: false)
        await assertRejectedPlan(item: blockedItem, expected: .unsatisfiedConditions(blockedItem.id), registry: registry)
    }

    func testRejectsEveryNonTrashMutationKind() async throws {
        let path = try makeFile(named: "actions.cache").path
        let registry = TrashExecutionAuthorizationRegistry()

        for action in [ActionKind.deleteCache, .compress, .quarantineHold] {
            let item = makeItem(path: path, action: action)
            await assertRejectedPlan(item: item, expected: .ineligibleFinding(item.id), registry: registry)
        }
    }

    func testRejectsProtectedRuleEvidence() async throws {
        let path = try makeFile(named: "protected.cache").path
        let registry = TrashExecutionAuthorizationRegistry()

        for safetyClass in [SafetyClass.preserveByDefault, .neverTouch] {
            let item = makeItem(path: path, protectedRuleSafetyClass: safetyClass)
            await assertRejectedPlan(item: item, expected: .protectedRuleEvidence(item.id), registry: registry)
        }
    }

    func testRejectsCodexSessionsAndMemoriesPaths() async throws {
        let registry = TrashExecutionAuthorizationRegistry()
        let paths = [
            tempRoot.appendingPathComponent(".codex/sessions/session.json").path,
            tempRoot.appendingPathComponent(".codex/memories/MEMORY.md").path
        ]

        for (index, path) in paths.enumerated() {
            try FileManager.default.createDirectory(
                at: URL(fileURLWithPath: path).deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            XCTAssertTrue(FileManager.default.createFile(atPath: path, contents: Data("fixture".utf8)))
            let item = makeItem(id: "protected-directory-\(index)", path: path)
            await assertRejectedPlan(item: item, expected: .protectedPath(item.id), registry: registry)
        }
    }

    func testRejectsActualCodexAuthJSONAndConfigTOMLFileForms() async throws {
        let registry = TrashExecutionAuthorizationRegistry()
        let paths = [
            tempRoot.appendingPathComponent(".codex/auth.json").path,
            tempRoot.appendingPathComponent(".codex/config.toml").path
        ]

        for (index, path) in paths.enumerated() {
            try FileManager.default.createDirectory(
                at: URL(fileURLWithPath: path).deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            XCTAssertTrue(FileManager.default.createFile(atPath: path, contents: Data("fixture".utf8)))
            let item = makeItem(id: "protected-file-\(index)", path: path)
            await assertRejectedPlan(item: item, expected: .protectedPath(item.id), registry: registry)
        }
    }

    func testFileIdentityReaderUsesLstatAndRejectsSymbolicLinks() throws {
        let target = try makeFile(named: "target.cache")
        let link = tempRoot.appendingPathComponent("link.cache")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        let reader = FileIdentityReader()

        let identity = try reader.read(at: target)

        XCTAssertEqual(identity.kind, .regularFile)
        XCTAssertEqual(identity.standardizedPath, target.standardizedFileURL.path)
        XCTAssertGreaterThan(identity.fileID, 0)
        XCTAssertThrowsError(try reader.read(at: link)) { error in
            XCTAssertEqual(error as? FileIdentityReaderError, .symbolicLink(link.standardizedFileURL.path))
        }
    }

    func testAuthorizationExpiresAfterFifteenMinutesAndIsConsumedOnlyOnce() async throws {
        let item = makeItem(path: try makeFile(named: "one-use.cache").path)
        let plan = makePlan(items: [item])
        let receipt = makeReceipt(for: plan)
        let session = makeSession(plan: plan, receipt: receipt)
        let issuedAt = Date(timeIntervalSince1970: 20_000)

        let oneUseRegistry = TrashExecutionAuthorizationRegistry()
        let oneUse = try await oneUseRegistry.issue(
            session: session,
            plan: plan,
            dryRunReceipt: receipt,
            now: issuedAt
        )
        let consumed = try await oneUseRegistry.consume(id: oneUse.id, now: issuedAt.addingTimeInterval(899))
        XCTAssertEqual(consumed, oneUse)
        await assertAuthorizationError(.authorizationUnavailable) {
            _ = try await oneUseRegistry.consume(id: oneUse.id, now: issuedAt.addingTimeInterval(899))
        }

        let expiryRegistry = TrashExecutionAuthorizationRegistry()
        let expiring = try await expiryRegistry.issue(
            session: session,
            plan: plan,
            dryRunReceipt: receipt,
            now: issuedAt
        )
        await assertAuthorizationError(.authorizationExpired) {
            _ = try await expiryRegistry.consume(id: expiring.id, now: issuedAt.addingTimeInterval(900))
        }
        await assertAuthorizationError(.authorizationUnavailable) {
            _ = try await expiryRegistry.consume(id: expiring.id, now: issuedAt.addingTimeInterval(901))
        }
    }

    func testCapabilityIsNotAvailableFromANewRegistry() async throws {
        let item = makeItem(path: try makeFile(named: "memory-only.cache").path)
        let plan = makePlan(items: [item])
        let receipt = makeReceipt(for: plan)
        let session = makeSession(plan: plan, receipt: receipt)
        let firstRegistry = TrashExecutionAuthorizationRegistry()
        let authorization = try await firstRegistry.issue(session: session, plan: plan, dryRunReceipt: receipt)

        let restartedRegistry = TrashExecutionAuthorizationRegistry()

        await assertAuthorizationError(.authorizationUnavailable) {
            _ = try await restartedRegistry.consume(id: authorization.id)
        }
    }

    private func makeFile(named name: String) throws -> URL {
        let url = tempRoot.appendingPathComponent(name).standardizedFileURL
        XCTAssertTrue(FileManager.default.createFile(atPath: url.path, contents: Data("fixture".utf8)))
        return url
    }

    private func makeItem(
        id: String = UUID().uuidString,
        path: String,
        selected: Bool = true,
        safetyClass: SafetyClass = .autoSafe,
        action: ActionKind = .trash,
        conditionsSatisfied: Bool = true,
        protectedRuleSafetyClass: SafetyClass? = nil
    ) -> ReclaimPlanItem {
        let primaryMatch = RuleMatch(
            ruleID: "fixture.auto-trash",
            title: "Fixture trash",
            category: "Fixture",
            safetyClass: .autoSafe,
            actionKind: .trash,
            evidence: ["Disposable fixture"],
            conditionGates: [.openFileClear],
            recovery: "Restore from Trash."
        )
        let protectedMatch = protectedRuleSafetyClass.map {
            RuleMatch(
                ruleID: "fixture.protected",
                title: "Protected fixture",
                category: "Fixture",
                safetyClass: $0,
                actionKind: .reportOnly,
                evidence: ["Protected by fixture rule"]
            )
        }
        let finding = Finding(
            id: id,
            scopeName: "Fixture",
            path: path,
            displayName: URL(fileURLWithPath: path).lastPathComponent,
            logicalSize: 7,
            allocatedSize: 7,
            isDirectory: false,
            safetyClass: safetyClass,
            actionKind: action,
            ruleMatches: [primaryMatch] + [protectedMatch].compactMap { $0 },
            evidence: [Evidence(kind: "fixture", message: "Disposable fixture")]
        )
        return ReclaimPlanItem(
            finding: finding,
            selected: selected,
            proposedAction: action,
            conditions: [
                PlanCondition(
                    kind: .openFileClear,
                    message: "No open file handles",
                    isSatisfied: conditionsSatisfied
                )
            ],
            estimatedImmediateReclaim: selected ? 7 : 0
        )
    }

    private func makePlan(items: [ReclaimPlanItem]) -> ReclaimPlan {
        ReclaimPlan(id: "plan-\(UUID().uuidString)", mode: PlanMode.autoSafeOnly.rawValue, items: items, dryRunSummary: [])
    }

    private func makeReceipt(
        for plan: ReclaimPlan,
        id: String = "receipt-\(UUID().uuidString)",
        errors: [String] = []
    ) -> ExecutionReceipt {
        ExecutionReceipt(
            id: id,
            ruleVersion: "rules-v1",
            mode: ExecutionMode.dryRun.rawValue,
            beforeFreeBytes: nil,
            afterFreeBytes: nil,
            actions: plan.items.filter(\.selected).map {
                ExecutionActionReceipt(
                    path: $0.finding.path,
                    action: $0.proposedAction,
                    status: "dry-run",
                    message: "Would perform \($0.proposedAction.label).",
                    reclaimedBytes: $0.estimatedImmediateReclaim
                )
            },
            userConfirmed: false,
            errors: errors
        )
    }

    private func makeSession(
        plan: ReclaimPlan,
        receipt: ExecutionReceipt,
        stage: ScanSessionStage = .reclaimReady,
        planDigest: String? = nil,
        receiptID: String? = nil
    ) -> ScanSession {
        ScanSession(
            id: "session-\(UUID().uuidString)",
            appVersion: "0.3.0",
            ruleVersion: "rules-v1",
            preset: .developer,
            scopeDigest: "scope-v1",
            policyDigest: "policy-v1",
            findingDigest: "findings-v1",
            planDigest: planDigest ?? plan.id,
            dryRunReceiptID: receiptID ?? receipt.id,
            stage: stage,
            invalidationReasons: stage == .invalidated ? [.planSelectionChanged] : []
        )
    }

    private func assertRejectedPlan(
        item: ReclaimPlanItem,
        expected: TrashExecutionAuthorizationError,
        registry: TrashExecutionAuthorizationRegistry
    ) async {
        let plan = makePlan(items: [item])
        let receipt = makeReceipt(for: plan)
        let session = makeSession(plan: plan, receipt: receipt)
        await assertAuthorizationError(expected) {
            _ = try await registry.issue(session: session, plan: plan, dryRunReceipt: receipt)
        }
    }

    private func assertAuthorizationError(
        _ expected: TrashExecutionAuthorizationError,
        operation: () async throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            try await operation()
            XCTFail("Expected \(expected)", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? TrashExecutionAuthorizationError, expected, file: file, line: line)
        }
    }
}
