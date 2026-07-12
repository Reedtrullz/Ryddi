import XCTest
@testable import ReclaimerCore

final class PlanGateEvidenceTests: XCTestCase {
    func testEquivalentPlansUseStableContentID() throws {
        let first = PlanGateFixtures.finding(
            id: "stable-cache",
            path: "/tmp/ryddi-stable-cache",
            conditionGates: [.openFileClear],
            gateEvidence: RuleGateEvidence(),
            modificationAgeDays: nil
        )
        let second = PlanGateFixtures.finding(
            id: "stable-cache",
            path: "/tmp/ryddi-stable-cache",
            conditionGates: [.openFileClear],
            gateEvidence: RuleGateEvidence(),
            modificationAgeDays: nil
        )

        let firstPlan = PlanBuilder(openFileChecker: AlwaysClearOpenFileChecker()).buildPlan(from: [first], mode: .autoSafeOnly)
        let secondPlan = PlanBuilder(openFileChecker: AlwaysClearOpenFileChecker()).buildPlan(from: [second], mode: .autoSafeOnly)

        XCTAssertEqual(firstPlan.id, secondPlan.id)
        XCTAssertTrue(firstPlan.id.hasPrefix("plan-"))
    }

    func testPlanIDChangesWhenReclaimRelevantContentChanges() throws {
        let base = PlanGateFixtures.finding(
            id: "stable-cache",
            path: "/tmp/ryddi-stable-cache",
            conditionGates: [.openFileClear],
            gateEvidence: RuleGateEvidence(),
            modificationAgeDays: nil
        )
        let larger = PlanGateFixtures.finding(
            id: "stable-cache",
            path: "/tmp/ryddi-stable-cache",
            logicalSize: 2_000_000,
            allocatedSize: 2_000_000,
            conditionGates: [.openFileClear],
            gateEvidence: RuleGateEvidence(),
            modificationAgeDays: nil
        )

        let basePlan = PlanBuilder(openFileChecker: AlwaysClearOpenFileChecker()).buildPlan(from: [base], mode: .autoSafeOnly)
        let largerPlan = PlanBuilder(openFileChecker: AlwaysClearOpenFileChecker()).buildPlan(from: [larger], mode: .autoSafeOnly)

        XCTAssertNotEqual(basePlan.id, largerPlan.id)
    }

    func testMinimumAgeGateWithoutNumericEvidenceDoesNotAutoSelect() throws {
        let finding = PlanGateFixtures.finding(
            conditionGates: [.minimumAgeRequired],
            gateEvidence: RuleGateEvidence(),
            modificationAgeDays: 90
        )

        let plan = PlanBuilder(openFileChecker: AlwaysClearOpenFileChecker()).buildPlan(from: [finding], mode: .autoSafeOnly)

        XCTAssertEqual(plan.items.count, 1)
        XCTAssertFalse(plan.items[0].selected)
        XCTAssertTrue(plan.items[0].conditions.contains { $0.kind == .minimumAgeRequired && !$0.isSatisfied })
    }

    func testMinimumAgeGateWithoutModificationDateDoesNotAutoSelect() throws {
        let finding = PlanGateFixtures.finding(
            conditionGates: [.minimumAgeRequired],
            gateEvidence: RuleGateEvidence(minimumAgeDays: 30),
            modificationAgeDays: nil
        )

        let plan = PlanBuilder(openFileChecker: AlwaysClearOpenFileChecker()).buildPlan(from: [finding], mode: .autoSafeOnly)

        XCTAssertEqual(plan.items.count, 1)
        XCTAssertFalse(plan.items[0].selected)
        XCTAssertTrue(plan.items[0].conditions.contains { $0.kind == .minimumAgeRequired && !$0.isSatisfied })
    }

    func testMinimumAgeGateBlocksTooRecentCache() throws {
        let finding = PlanGateFixtures.finding(
            conditionGates: [.openFileClear, .minimumAgeRequired, .finalClassificationRequired],
            gateEvidence: RuleGateEvidence(
                minimumAgeDays: 30,
                retentionPolicy: "cache-30-day",
                retentionDays: 30
            ),
            modificationAgeDays: 7
        )

        let plan = PlanBuilder(openFileChecker: AlwaysClearOpenFileChecker()).buildPlan(from: [finding], mode: .autoSafeOnly)

        XCTAssertEqual(plan.items.count, 1)
        XCTAssertFalse(plan.items[0].selected)
        XCTAssertTrue(plan.items[0].conditions.contains { $0.kind == .minimumAgeRequired && !$0.isSatisfied })
    }

    func testMinimumAgeGateWithEvidenceSelectsOldEnoughCache() throws {
        let finding = PlanGateFixtures.finding(
            conditionGates: [.openFileClear, .minimumAgeRequired, .finalClassificationRequired],
            gateEvidence: RuleGateEvidence(
                minimumAgeDays: 30,
                retentionPolicy: "cache-30-day",
                retentionDays: 30
            ),
            modificationAgeDays: 45
        )

        let plan = PlanBuilder(openFileChecker: AlwaysClearOpenFileChecker()).buildPlan(from: [finding], mode: .autoSafeOnly)

        XCTAssertEqual(plan.items.count, 1)
        XCTAssertTrue(plan.items[0].selected)
        XCTAssertTrue(plan.items[0].conditions.contains { $0.kind == .minimumAgeRequired && $0.isSatisfied })
        XCTAssertTrue(plan.items[0].conditions.contains { $0.kind == .finalClassificationRequired && $0.isSatisfied })
    }

    func testNativeToolGateUsesTypedPreviewEvidence() throws {
        let blocked = PlanGateFixtures.finding(
            actionKind: .trash,
            conditionGates: [.nativeToolRequired],
            gateEvidence: RuleGateEvidence(nativeToolName: "npm", nativePreviewAvailable: false),
            modificationAgeDays: 45
        )
        let allowed = PlanGateFixtures.finding(
            actionKind: .trash,
            conditionGates: [.nativeToolRequired],
            gateEvidence: RuleGateEvidence(nativeToolName: "npm", nativePreviewAvailable: true),
            modificationAgeDays: 45
        )

        let plan = PlanBuilder(openFileChecker: AlwaysClearOpenFileChecker()).buildPlan(from: [blocked, allowed], mode: .autoSafeOnly)

        XCTAssertFalse(plan.items.first { $0.finding.id == blocked.id }?.selected ?? true)
        XCTAssertTrue(plan.items.first { $0.finding.id == allowed.id }?.selected ?? false)
    }

    func testRuleMatchDecodesLegacyJSONWithoutGateEvidence() throws {
        let data = Data("""
        {
          "ruleID": "legacy.rule",
          "title": "Legacy rule",
          "category": "Legacy",
          "safetyClass": "autoSafe",
          "actionKind": "deleteCache",
          "evidence": ["legacy evidence"],
          "conditions": ["legacy condition"],
          "conditionGates": ["openFileClear"]
        }
        """.utf8)

        let match = try JSONDecoder().decode(RuleMatch.self, from: data)

        XCTAssertEqual(match.gateEvidence, RuleGateEvidence())
        XCTAssertEqual(match.conditionGates, [.openFileClear])
    }

    func testReclaimerRuleDecodesGateEvidenceFromJSON() throws {
        let data = Data("""
        {
          "id": "tmp.fixture",
          "title": "Fixture stale scratch",
          "category": "Temporary files",
          "priority": 10,
          "safetyClass": "autoSafe",
          "actionKind": "deleteCache",
          "match": {
            "containsAny": ["/private/tmp/fixture"],
            "suffixAny": [],
            "basenameAny": [],
            "pathExtensionAny": []
          },
          "evidence": ["fixture evidence"],
          "conditionGates": ["openFileClear", "minimumAgeRequired"],
          "gateEvidence": {
            "minimumAgeDays": 14,
            "retentionPolicy": "scratch-14-day",
            "retentionDays": 14
          }
        }
        """.utf8)

        let rule = try JSONDecoder().decode(ReclaimerRule.self, from: data)

        XCTAssertEqual(rule.gateEvidence.minimumAgeDays, 14)
        XCTAssertEqual(rule.gateEvidence.retentionPolicy, "scratch-14-day")
        XCTAssertEqual(rule.conditionGates, [.openFileClear, .minimumAgeRequired])
    }
}

private struct AlwaysClearOpenFileChecker: OpenFileChecking {
    func status(for url: URL) -> OpenFileStatus {
        OpenFileStatus(
            isOpen: false,
            checkedRecursively: true,
            checkedPath: url.path
        )
    }
}

private enum PlanGateFixtures {
    static func finding(
        id: String = UUID().uuidString,
        path: String? = nil,
        logicalSize: Int64 = 1_000_000,
        allocatedSize: Int64 = 1_000_000,
        actionKind: ActionKind = .deleteCache,
        conditionGates: [PlanConditionKind],
        gateEvidence: RuleGateEvidence,
        modificationAgeDays: Int?
    ) -> Finding {
        let modificationDate = modificationAgeDays.map {
            Date(timeIntervalSinceNow: -Double($0) * 86_400)
        }
        let match = RuleMatch(
            ruleID: "fixture.age-gate",
            title: "Fixture cache",
            category: "Developer cache",
            safetyClass: .autoSafe,
            actionKind: actionKind,
            evidence: ["Fixture cache evidence"],
            conditions: [],
            conditionGates: conditionGates,
            gateEvidence: gateEvidence,
            recovery: nil
        )
        return Finding(
            id: id,
            scopeName: "Fixture",
            path: path ?? "/tmp/ryddi-fixture-cache-\(id)",
            displayName: "ryddi-fixture-cache",
            logicalSize: logicalSize,
            allocatedSize: allocatedSize,
            isDirectory: true,
            modificationDate: modificationDate,
            safetyClass: .autoSafe,
            actionKind: actionKind,
            ruleMatches: [match],
            evidence: [Evidence(kind: "fixture", message: "Fixture cache evidence")],
            openFileStatus: OpenFileStatus(isOpen: false, checkedRecursively: true)
        )
    }
}
