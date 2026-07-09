import XCTest
@testable import ReclaimerCore

final class AgentRetentionPlanTests: XCTestCase {
    func testCodexSessionsRemainProtectedByDefault() throws {
        let report = AgentRetentionFixtures.report(
            category: "sessions",
            bytes: 8_000_000_000,
            eligible: false,
            recommendation: .protect,
            bucket: .valuableHistory
        )
        let findings = [
            AgentRetentionFixtures.finding(pathSuffix: "sessions", safetyClass: .preserveByDefault)
        ]

        let preview = AgentRetentionPlanBuilder.build(
            report: report,
            matchingFindings: findings,
            generatedAt: Date(timeIntervalSince1970: 10),
            openFileChecker: AgentPlanClearOpenFileChecker()
        )

        XCTAssertTrue(preview.plan.items.isEmpty)
        XCTAssertEqual(preview.selectedBytes, 0)
        XCTAssertEqual(preview.protectedBytes, 8_000_000_000)
        XCTAssertTrue(preview.protectedReasons.contains { $0.localizedCaseInsensitiveContains("sessions") })
        XCTAssertTrue(preview.nonClaims.contains("No AI-agent storage cleanup was executed."))
    }

    func testEligibleAgentCacheBuildsTrashPreviewPlan() throws {
        let report = AgentRetentionFixtures.report(
            category: "logs",
            bytes: 750_000_000,
            eligible: true,
            recommendation: .cleanupPlan,
            bucket: .reclaimableCache
        )
        let finding = AgentRetentionFixtures.finding(
            pathSuffix: "logs",
            safetyClass: .autoSafe,
            actionKind: .trash,
            conditionGates: [.openFileClear, .minimumAgeRequired, .finalClassificationRequired],
            minimumAgeDays: 30,
            modificationAgeDays: 60
        )

        let preview = AgentRetentionPlanBuilder.build(
            report: report,
            matchingFindings: [finding],
            generatedAt: Date(timeIntervalSince1970: 10),
            openFileChecker: AgentPlanClearOpenFileChecker()
        )

        XCTAssertEqual(preview.plan.items.count, 1)
        XCTAssertEqual(preview.selectedBytes, 750_000_000)
        XCTAssertEqual(preview.plan.items.first?.selected, true)
        XCTAssertTrue(preview.nonClaims.contains("Only retention-eligible paths with matching auto-safe scan findings can enter the preview plan."))
    }

    func testEligibleRecommendationWithoutMatchingFindingDoesNotCreatePlanItem() throws {
        let report = AgentRetentionFixtures.report(
            category: "logs",
            bytes: 750_000_000,
            eligible: true,
            recommendation: .cleanupPlan,
            bucket: .reclaimableCache
        )
        let unrelated = AgentRetentionFixtures.finding(
            pathSuffix: "cache",
            safetyClass: .autoSafe,
            actionKind: .trash,
            modificationAgeDays: 60
        )

        let preview = AgentRetentionPlanBuilder.build(
            report: report,
            matchingFindings: [unrelated],
            openFileChecker: AgentPlanClearOpenFileChecker()
        )

        XCTAssertTrue(preview.plan.items.isEmpty)
        XCTAssertEqual(preview.selectedBytes, 0)
        XCTAssertEqual(preview.reviewBytes, 750_000_000)
    }
}

private struct AgentPlanClearOpenFileChecker: OpenFileChecking {
    func status(for url: URL) -> OpenFileStatus {
        OpenFileStatus(isOpen: false, checkedRecursively: true, checkedPath: url.path)
    }
}

private enum AgentRetentionFixtures {
    static func report(
        category: String,
        bytes: Int64,
        eligible: Bool,
        recommendation: AgentRetentionRecommendationKind,
        bucket: AgentStorageBucket
    ) -> AgentRetentionReport {
        let row = AgentRetentionRecommendation(
            id: "fixture-\(category)",
            owner: "Codex",
            bucket: bucket,
            path: "/Users/reidar/.codex/\(category)",
            displayName: category,
            allocatedSize: bytes,
            ageDays: eligible ? 60 : 1,
            recommendation: recommendation,
            actionKind: eligible ? .trash : .reportOnly,
            eligibleForCleanupPlan: eligible,
            reason: eligible ? "Fixture stale cache/log data." : "Fixture protected history.",
            nextSteps: []
        )
        return AgentRetentionReport(
            profile: .balanced,
            profileSummary: AgentRetentionProfile.balanced.summary,
            reviewedItemCount: 1,
            totalBytes: bytes,
            cleanupCandidateBytes: eligible ? bytes : 0,
            compressionCandidateBytes: 0,
            protectedBytes: eligible ? 0 : bytes,
            summaries: [],
            recommendations: [row],
            nonClaims: []
        )
    }

    static func finding(
        pathSuffix: String,
        safetyClass: SafetyClass,
        actionKind: ActionKind = .reportOnly,
        conditionGates: [PlanConditionKind] = [],
        minimumAgeDays: Int? = nil,
        modificationAgeDays: Int = 0
    ) -> Finding {
        let modifiedAt = Date(timeIntervalSinceNow: -Double(modificationAgeDays) * 86_400)
        let match = RuleMatch(
            ruleID: "fixture.agent.\(pathSuffix)",
            title: "Agent fixture",
            category: "Codex",
            safetyClass: safetyClass,
            actionKind: actionKind,
            evidence: ["Fixture agent evidence"],
            conditions: [],
            conditionGates: conditionGates,
            gateEvidence: RuleGateEvidence(minimumAgeDays: minimumAgeDays),
            recovery: nil
        )
        return Finding(
            scopeName: "AI Agent Storage",
            path: "/Users/reidar/.codex/\(pathSuffix)",
            displayName: pathSuffix,
            logicalSize: 750_000_000,
            allocatedSize: 750_000_000,
            isDirectory: true,
            modificationDate: modifiedAt,
            ownerHint: "Codex",
            safetyClass: safetyClass,
            actionKind: actionKind,
            ruleMatches: [match],
            evidence: [Evidence(kind: "fixture", message: "Fixture agent evidence")],
            openFileStatus: OpenFileStatus(isOpen: false, checkedRecursively: true)
        )
    }
}
