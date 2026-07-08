import Foundation

public struct AgentRetentionPlanPreview: Codable, Hashable, Sendable {
    public let generatedAt: Date
    public let selectedBytes: Int64
    public let protectedBytes: Int64
    public let reviewBytes: Int64
    public let plan: ReclaimPlan
    public let protectedReasons: [String]
    public let nonClaims: [String]

    public init(
        generatedAt: Date = Date(),
        selectedBytes: Int64,
        protectedBytes: Int64,
        reviewBytes: Int64,
        plan: ReclaimPlan,
        protectedReasons: [String],
        nonClaims: [String]
    ) {
        self.generatedAt = generatedAt
        self.selectedBytes = selectedBytes
        self.protectedBytes = protectedBytes
        self.reviewBytes = reviewBytes
        self.plan = plan
        self.protectedReasons = protectedReasons
        self.nonClaims = nonClaims
    }
}

public enum AgentRetentionPlanBuilder {
    public static func build(
        report: AgentRetentionReport,
        matchingFindings: [Finding],
        generatedAt: Date = Date(),
        openFileChecker: OpenFileChecking = LsofOpenFileChecker()
    ) -> AgentRetentionPlanPreview {
        let eligiblePaths = Set(
            report.recommendations
                .filter(\.eligibleForCleanupPlan)
                .map { standardizedPath($0.path) }
        )
        let eligibleFindings = matchingFindings.filter { finding in
            eligiblePaths.contains(standardizedPath(finding.path))
                && finding.safetyClass == .autoSafe
                && [.deleteCache, .trash].contains(finding.actionKind)
        }
        let plan = PlanBuilder(openFileChecker: openFileChecker).buildPlan(from: eligibleFindings, mode: .autoSafeOnly)
        let selectedBytes = plan.items
            .filter(\.selected)
            .reduce(Int64(0)) { $0 + $1.estimatedImmediateReclaim }
        let protectedReasons = report.recommendations
            .filter { !$0.eligibleForCleanupPlan }
            .map { "\($0.displayName): \($0.reason)" }

        return AgentRetentionPlanPreview(
            generatedAt: generatedAt,
            selectedBytes: selectedBytes,
            protectedBytes: report.protectedBytes,
            reviewBytes: max(0, report.totalBytes - selectedBytes - report.protectedBytes),
            plan: plan,
            protectedReasons: protectedReasons,
            nonClaims: [
                "No AI-agent storage cleanup was executed.",
                "Sessions, memories, config, auth, model state, and unknown app state are protected by default.",
                "Only retention-eligible paths with matching auto-safe scan findings can enter the preview plan.",
                "Execution rechecks classification, symlinks, policy, age gates, and active file handles."
            ]
        )
    }

    private static func standardizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }
}
