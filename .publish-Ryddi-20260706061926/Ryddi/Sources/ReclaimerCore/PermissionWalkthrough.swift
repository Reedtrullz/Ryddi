import Foundation

public enum PermissionWalkthroughStepStatus: String, Codable, Hashable, Sendable {
    case done
    case recommended
    case optional
    case blocked

    public var label: String {
        switch self {
        case .done: "Done"
        case .recommended: "Recommended"
        case .optional: "Optional"
        case .blocked: "Blocked"
        }
    }
}

public struct PermissionWalkthroughStep: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let status: PermissionWalkthroughStepStatus
    public let detail: String
    public let actionLabel: String?
    public let settingsURL: String?
    public let command: String?
    public let affectedScopes: [String]

    public init(
        id: String,
        title: String,
        status: PermissionWalkthroughStepStatus,
        detail: String,
        actionLabel: String? = nil,
        settingsURL: String? = nil,
        command: String? = nil,
        affectedScopes: [String] = []
    ) {
        self.id = id
        self.title = title
        self.status = status
        self.detail = detail
        self.actionLabel = actionLabel
        self.settingsURL = settingsURL
        self.command = command
        self.affectedScopes = affectedScopes
    }
}

public struct PermissionWalkthrough: Codable, Hashable, Sendable {
    public let id: String
    public let createdAt: Date
    public let appName: String
    public let coverageLevel: PermissionCoverageLevel
    public let readableCount: Int
    public let totalCount: Int
    public let deniedCount: Int
    public let missingCount: Int
    public let unknownCount: Int
    public let steps: [PermissionWalkthroughStep]
    public let nonClaims: [String]
    public let markdown: String

    public init(
        id: String,
        createdAt: Date,
        appName: String,
        coverageLevel: PermissionCoverageLevel,
        readableCount: Int,
        totalCount: Int,
        deniedCount: Int,
        missingCount: Int,
        unknownCount: Int,
        steps: [PermissionWalkthroughStep],
        nonClaims: [String],
        markdown: String
    ) {
        self.id = id
        self.createdAt = createdAt
        self.appName = appName
        self.coverageLevel = coverageLevel
        self.readableCount = readableCount
        self.totalCount = totalCount
        self.deniedCount = deniedCount
        self.missingCount = missingCount
        self.unknownCount = unknownCount
        self.steps = steps
        self.nonClaims = nonClaims
        self.markdown = markdown
    }
}

public enum PermissionWalkthroughBuilder {
    public static func build(
        report: PermissionAdvisorReport,
        appName: String = "Ryddi",
        cliCommand: String = "reclaimer",
        now: Date? = nil
    ) -> PermissionWalkthrough {
        let createdAt = now ?? report.createdAt
        let deniedScopes = report.scopeSummaries
            .filter { $0.permissionState == .denied }
            .map(\.name)
        let unavailableScopes = report.unavailableScopes.map(\.name)
        let coverageStatus: PermissionWalkthroughStepStatus = report.coverageLevel == .blocked ? .blocked : .done
        let settingsStatus: PermissionWalkthroughStepStatus = report.needsFullDiskAccessReview ? .recommended : .optional
        let rescanStatus: PermissionWalkthroughStepStatus = report.coverageLevel == .complete ? .optional : .recommended
        let degradedStatus: PermissionWalkthroughStepStatus = report.unavailableScopes.isEmpty
            ? .done
            : (report.coverageLevel == .blocked ? .blocked : .recommended)

        let steps = [
            PermissionWalkthroughStep(
                id: "review-coverage",
                title: "Review current scan coverage",
                status: coverageStatus,
                detail: "\(appName) can read \(report.readableCount) of \(report.totalCount) configured scopes. Current coverage is \(report.coverageLevel.label.lowercased())."
            ),
            PermissionWalkthroughStep(
                id: "open-full-disk-access",
                title: "Open Full Disk Access settings",
                status: settingsStatus,
                detail: report.needsFullDiskAccessReview
                    ? "Denied scopes usually need a user-granted Full Disk Access review before the scan can see their contents."
                    : "No denied scope was observed. Full Disk Access can still be reviewed if you expect broader coverage.",
                actionLabel: "Open Full Disk Access Settings",
                settingsURL: report.fullDiskAccessSettingsURL,
                affectedScopes: deniedScopes
            ),
            PermissionWalkthroughStep(
                id: "restart-or-rescan",
                title: "Restart or rescan after changing settings",
                status: rescanStatus,
                detail: "macOS privacy changes may require a fresh scan or app restart before coverage changes are visible.",
                command: "\(cliCommand) permissions guide"
            ),
            PermissionWalkthroughStep(
                id: "save-report-only-evidence",
                title: "Save report-only evidence",
                status: .optional,
                detail: "A permission guide and evidence report can be saved before any cleanup plan is built.",
                command: "\(cliCommand) permissions guide --output ryddi-permissions-guide.md"
            ),
            PermissionWalkthroughStep(
                id: "keep-degraded-mode-visible",
                title: "Keep degraded-mode labels visible",
                status: degradedStatus,
                detail: report.unavailableScopes.isEmpty
                    ? "No unavailable scope is currently listed in this report."
                    : "Unavailable scopes stay visible as denied, missing, or unknown instead of being silently treated as scanned.",
                affectedScopes: unavailableScopes
            )
        ]

        let nonClaims = combinedNonClaims(report: report)
        let id = "permission-walkthrough-\(Int(createdAt.timeIntervalSince1970))"
        let walkthrough = PermissionWalkthrough(
            id: id,
            createdAt: createdAt,
            appName: appName,
            coverageLevel: report.coverageLevel,
            readableCount: report.readableCount,
            totalCount: report.totalCount,
            deniedCount: report.deniedCount,
            missingCount: report.missingCount,
            unknownCount: report.unknownCount,
            steps: steps,
            nonClaims: nonClaims,
            markdown: ""
        )
        return PermissionWalkthrough(
            id: walkthrough.id,
            createdAt: walkthrough.createdAt,
            appName: walkthrough.appName,
            coverageLevel: walkthrough.coverageLevel,
            readableCount: walkthrough.readableCount,
            totalCount: walkthrough.totalCount,
            deniedCount: walkthrough.deniedCount,
            missingCount: walkthrough.missingCount,
            unknownCount: walkthrough.unknownCount,
            steps: walkthrough.steps,
            nonClaims: walkthrough.nonClaims,
            markdown: markdown(for: walkthrough)
        )
    }

    private static func combinedNonClaims(report: PermissionAdvisorReport) -> [String] {
        let walkthroughNonClaims = [
            "This walkthrough does not grant macOS permissions.",
            "Opening System Settings does not prove Full Disk Access is enabled.",
            "Readable scopes are scan coverage evidence, not cleanup approval.",
            "Permission changes do not execute cleanup, install a LaunchAgent, or verify real disk reclaim."
        ]
        return Array((walkthroughNonClaims + report.nonClaims).uniqued())
    }

    private static func markdown(for walkthrough: PermissionWalkthrough) -> String {
        var lines: [String] = [
            "# \(walkthrough.appName) Permission Walkthrough",
            "",
            "- Generated: \(ISO8601DateFormatter().string(from: walkthrough.createdAt))",
            "- Coverage: \(walkthrough.coverageLevel.label)",
            "- Readable scopes: \(walkthrough.readableCount)/\(walkthrough.totalCount)",
            "- Denied: \(walkthrough.deniedCount)",
            "- Missing: \(walkthrough.missingCount)",
            "- Unknown: \(walkthrough.unknownCount)",
            "",
            "## Walkthrough"
        ]

        for step in walkthrough.steps {
            lines.append("")
            lines.append("### \(step.title)")
            lines.append("")
            lines.append("- Status: \(step.status.label)")
            lines.append("- Detail: \(step.detail)")
            if let actionLabel = step.actionLabel {
                lines.append("- Action: \(actionLabel)")
            }
            if let settingsURL = step.settingsURL {
                lines.append("- Settings URL: `\(settingsURL)`")
            }
            if let command = step.command {
                lines.append("- Command: `\(command)`")
            }
            if !step.affectedScopes.isEmpty {
                lines.append("- Affected scopes: \(step.affectedScopes.joined(separator: ", "))")
            }
        }

        lines.append("")
        lines.append("## Explicit Non-Claims")
        lines.append("")
        for note in walkthrough.nonClaims {
            lines.append("- \(note)")
        }

        lines.append("")
        return lines.joined(separator: "\n")
    }
}

private extension Sequence where Element: Hashable {
    func uniqued() -> [Element] {
        var seen: Set<Element> = []
        var values: [Element] = []
        for element in self where seen.insert(element).inserted {
            values.append(element)
        }
        return values
    }
}
