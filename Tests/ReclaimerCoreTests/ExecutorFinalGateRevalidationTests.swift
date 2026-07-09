import XCTest
@testable import ReclaimerCore

final class ExecutorFinalGateRevalidationTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ryddi-executor-final-gates-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let root {
            try? FileManager.default.removeItem(at: root)
        }
        root = nil
    }

    func testPerformSkipsWhenMinimumAgeGateBecameFreshAfterPlanning() throws {
        let cache = root.appendingPathComponent("stale-cache", isDirectory: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 16).write(to: cache.appendingPathComponent("cache.bin"))
        let oldDate = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: -45, to: Date()))
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: cache.path)

        let finding = finding(
            path: cache.path,
            ruleID: "fixture.stale-cache",
            modificationDate: oldDate,
            conditionGates: [.minimumAgeRequired, .finalClassificationRequired],
            gateEvidence: RuleGateEvidence(minimumAgeDays: 30, retentionPolicy: "fixture-30-day", retentionDays: 30)
        )
        let plan = selectedPlan(for: finding, conditions: [
            PlanCondition(kind: .minimumAgeRequired, message: "Minimum age was satisfied during planning.", isSatisfied: true),
            PlanCondition(kind: .finalClassificationRequired, message: "Classification was satisfied during planning.", isSatisfied: true)
        ])

        try FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: cache.path)

        let receipt = ReclaimerExecutor(
            openFileChecker: ExecutorClearOpenFileChecker(),
            ruleEngine: RuleEngine(version: "fixture", rules: [rule(id: "fixture.stale-cache", pathNeedle: cache.path)])
        )
        .execute(plan: plan, mode: .perform, ruleVersion: "fixture", userConfirmed: true)

        XCTAssertTrue(FileManager.default.fileExists(atPath: cache.path))
        XCTAssertEqual(receipt.actions.first?.status, "skipped")
        XCTAssertTrue(receipt.actions.first?.message.localizedCaseInsensitiveContains("minimum age") ?? false)
    }

    func testPerformSkipsWhenFinalClassificationRuleIdentityChangedAfterPlanning() throws {
        let cache = root.appendingPathComponent("same-action-cache", isDirectory: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        try Data(repeating: 2, count: 16).write(to: cache.appendingPathComponent("cache.bin"))

        let finding = finding(
            path: cache.path,
            ruleID: "fixture.planned-rule",
            conditionGates: [.finalClassificationRequired]
        )
        let plan = selectedPlan(for: finding, conditions: [
            PlanCondition(kind: .finalClassificationRequired, message: "Classification was satisfied during planning.", isSatisfied: true)
        ])

        let receipt = ReclaimerExecutor(
            openFileChecker: ExecutorClearOpenFileChecker(),
            ruleEngine: RuleEngine(version: "fixture", rules: [rule(id: "fixture.current-rule", pathNeedle: cache.path)])
        )
        .execute(plan: plan, mode: .perform, ruleVersion: "fixture", userConfirmed: true)

        XCTAssertTrue(FileManager.default.fileExists(atPath: cache.path))
        XCTAssertEqual(receipt.actions.first?.status, "skipped")
        XCTAssertTrue(receipt.actions.first?.message.localizedCaseInsensitiveContains("classification") ?? false)
    }

    private func finding(
        path: String,
        ruleID: String,
        modificationDate: Date? = nil,
        conditionGates: [PlanConditionKind],
        gateEvidence: RuleGateEvidence = RuleGateEvidence()
    ) -> Finding {
        let match = RuleMatch(
            ruleID: ruleID,
            title: "Fixture cache",
            category: "Fixture",
            safetyClass: .autoSafe,
            actionKind: .deleteCache,
            evidence: ["Fixture cache evidence."],
            conditions: [],
            conditionGates: conditionGates,
            gateEvidence: gateEvidence
        )
        return Finding(
            scopeName: "Fixture",
            path: path,
            displayName: URL(fileURLWithPath: path).lastPathComponent,
            logicalSize: 16,
            allocatedSize: 16,
            isDirectory: true,
            modificationDate: modificationDate,
            safetyClass: .autoSafe,
            actionKind: .deleteCache,
            ruleMatches: [match],
            evidence: [Evidence(kind: ruleID, message: "Fixture cache evidence.")],
            openFileStatus: OpenFileStatus(isOpen: false, checkedRecursively: true, checkedPath: path)
        )
    }

    private func selectedPlan(for finding: Finding, conditions: [PlanCondition]) -> ReclaimPlan {
        ReclaimPlan(
            mode: PlanMode.autoSafeOnly.rawValue,
            items: [
                ReclaimPlanItem(
                    finding: finding,
                    selected: true,
                    proposedAction: .deleteCache,
                    conditions: conditions,
                    estimatedImmediateReclaim: finding.allocatedSize
                )
            ],
            dryRunSummary: []
        )
    }

    private func rule(id: String, pathNeedle: String) -> ReclaimerRule {
        ReclaimerRule(
            id: id,
            title: "Current fixture cache",
            category: "Fixture",
            priority: 100,
            safetyClass: .autoSafe,
            actionKind: .deleteCache,
            match: RuleMatchSpec(containsAny: [pathNeedle]),
            evidence: ["Current fixture cache evidence."],
            conditionGates: [.minimumAgeRequired, .finalClassificationRequired],
            gateEvidence: RuleGateEvidence(minimumAgeDays: 30, retentionPolicy: "fixture-30-day", retentionDays: 30)
        )
    }
}

private struct ExecutorClearOpenFileChecker: OpenFileChecking {
    func status(for url: URL) -> OpenFileStatus {
        OpenFileStatus(isOpen: false, checkedRecursively: true, checkedPath: url.path)
    }
}
