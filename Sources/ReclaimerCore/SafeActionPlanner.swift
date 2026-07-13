import Foundation

public enum SafeActionKind: String, Codable, Hashable, Sendable {
    case homebrewCleanup
    case dockerBuilderPrune
    case npmCacheClean
    case auditPrune
    // Retained for decoding historical candidates; the planner now emits Finder review instead.
    case trashAppBundle
    case packageCacheGuidance
    case openFinderReview
}

public enum SafeActionExecutionMode: String, Codable, Hashable, Sendable {
    case dryRun
    case perform
}

public struct SafeActionCandidate: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let kind: SafeActionKind
    public let title: String
    public let detail: String
    public let estimatedBytes: Int64?
    public let requiredConditions: [PlanConditionKind]
    public let commandPreview: [String]
    public let destructive: Bool
    public let reviewRequired: Bool

    public init(
        id: String,
        kind: SafeActionKind,
        title: String,
        detail: String,
        estimatedBytes: Int64?,
        requiredConditions: [PlanConditionKind],
        commandPreview: [String],
        destructive: Bool,
        reviewRequired: Bool
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.detail = detail
        self.estimatedBytes = estimatedBytes
        self.requiredConditions = requiredConditions
        self.commandPreview = commandPreview
        self.destructive = destructive
        self.reviewRequired = reviewRequired
    }
}

public struct SafeActionPlanner: Sendable {
    public static let auditCountThreshold = 500
    public static let auditByteThreshold: Int64 = 512 * 1_024 * 1_024
    public static let defaultAuditRetention = AuditRetentionPolicy(olderThanDays: 30, keepRecent: 100)

    public init() {}

    public func build(
        findings: [Finding],
        auditSummary: AuditStoreSummary? = nil
    ) -> [SafeActionCandidate] {
        var candidates = findings.compactMap(candidate(for:))

        if let auditSummary, shouldSuggestAuditPrune(auditSummary) {
            let policy = Self.defaultAuditRetention
            candidates.append(
                SafeActionCandidate(
                    id: "audit-review:\(auditSummary.rootPath)",
                    kind: .auditPrune,
                    title: "Review old Ryddi audit receipts",
                    detail: "Preview an audit-retention plan, then explicitly move still-matching known audit JSON candidates to Finder Trash.",
                    estimatedBytes: auditSummary.totalKnownBytes,
                    requiredConditions: [.manualReviewRequired, .finalClassificationRequired],
                    commandPreview: [
                        "reclaimer",
                        "audit",
                        "prune",
                        "--dry-run",
                        "--older-than-days",
                        "\(policy.olderThanDays)",
                        "--keep-recent",
                        "\(policy.keepRecent)"
                    ],
                    destructive: false,
                    reviewRequired: true
                )
            )
        }

        return candidates
    }

    private func candidate(for finding: Finding) -> SafeActionCandidate? {
        guard isActionEligible(finding) else { return nil }

        if isHomebrewCache(finding) {
            return SafeActionCandidate(
                id: "homebrew-cleanup:\(finding.path)",
                kind: .homebrewCleanup,
                title: "Preview Homebrew cleanup",
                detail: "Use Homebrew's native cleanup preview before allowing Homebrew to remove old downloads and versions.",
                estimatedBytes: finding.allocatedSize,
                requiredConditions: [.nativeToolRequired, .finalClassificationRequired],
                commandPreview: ["brew", "cleanup", "--dry-run"],
                destructive: false,
                reviewRequired: false
            )
        }

        if isPackageCache(finding), let preview = packagePreviewCommand(for: finding) {
            return SafeActionCandidate(
                id: "package-cache-guidance:\(finding.path)",
                kind: .packageCacheGuidance,
                title: "Review package cache guidance",
                detail: "Use package-manager commands to inspect cache state; Ryddi will not run these automatically.",
                estimatedBytes: finding.allocatedSize,
                requiredConditions: [.nativeToolRequired, .manualReviewRequired, .finalClassificationRequired],
                commandPreview: preview,
                destructive: false,
                reviewRequired: true
            )
        }

        if isAppBundleReviewCandidate(finding) {
            return SafeActionCandidate(
                id: "app-bundle-review:\(finding.path)",
                kind: .openFinderReview,
                title: "Review app bundle in Finder",
                detail: "Review the selected app bundle in Finder; Ryddi does not move it to Trash. Related support data stays review-only.",
                estimatedBytes: finding.allocatedSize,
                requiredConditions: [.manualReviewRequired, .appQuitRequired, .notSymbolicLink, .finalClassificationRequired],
                commandPreview: ["open", finding.path],
                destructive: false,
                reviewRequired: true
            )
        }

        return nil
    }

    private func shouldSuggestAuditPrune(_ summary: AuditStoreSummary) -> Bool {
        summary.totalKnownFileCount > Self.auditCountThreshold
            || summary.totalKnownBytes > Self.auditByteThreshold
    }

    private func isActionEligible(_ finding: Finding) -> Bool {
        guard finding.safetyClass != .preserveByDefault,
              finding.safetyClass != .neverTouch,
              !finding.isSymbolicLink else {
            return false
        }
        return !isProtectedStorage(finding.path, category: finding.ruleMatches.first?.category ?? finding.ownerHint ?? finding.displayName)
    }

    private func isHomebrewCache(_ finding: Finding) -> Bool {
        normalizedPath(finding.path).contains("/library/caches/homebrew")
    }

    private func isPackageCache(_ finding: Finding) -> Bool {
        let path = normalizedPath(finding.path)
        return path.contains("/.npm")
            || path.contains("/library/pnpm/store")
            || path.contains("/library/caches/yarn")
    }

    private func packagePreviewCommand(for finding: Finding) -> [String]? {
        let path = normalizedPath(finding.path)
        if path.contains("/.npm") {
            return ["npm", "cache", "verify"]
        }
        if path.contains("/library/pnpm/store") {
            return ["pnpm", "store", "status"]
        }
        if path.contains("/library/caches/yarn") {
            return ["yarn", "cache", "dir"]
        }
        return nil
    }

    private func isAppBundleReviewCandidate(_ finding: Finding) -> Bool {
        guard finding.actionKind == .trash,
              finding.isDirectory,
              finding.path.hasSuffix(".app") else {
            return false
        }
        let path = URL(fileURLWithPath: finding.path).standardizedFileURL.path
        let userApplications = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications", isDirectory: true)
            .standardizedFileURL
            .path
        return path.hasPrefix("/Applications/") || path.hasPrefix(userApplications + "/")
    }

    private func isProtectedStorage(_ path: String, category: String) -> Bool {
        let normalized = normalizedPath(path)
        let loweredCategory = category.lowercased()
        if normalized.contains("/.codex/sessions")
            || normalized.contains("/.codex/memories")
            || normalized.contains("/.codex/auth")
            || normalized.contains("/.codex/config") {
            return true
        }
        if loweredCategory.contains("browser profile")
            || normalized.contains("/library/application support/google/chrome")
            || normalized.contains("/library/application support/firefox")
            || normalized.contains("/library/application support/brave") {
            return true
        }
        if normalized.contains("/.colima")
            || normalized.contains("docker.raw")
            || normalized.contains("/library/containers/com.docker.docker")
            || (normalized.hasSuffix("/disk.img") && loweredCategory.contains("container")) {
            return true
        }
        return false
    }

    private func normalizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path.lowercased()
    }
}

public struct NativeActionCommand: Codable, Hashable, Sendable {
    public let kind: SafeActionKind
    public let executable: String
    public let arguments: [String]

    public init(kind: SafeActionKind, executable: String, arguments: [String]) {
        self.kind = kind
        self.executable = executable
        self.arguments = arguments
    }
}

public enum NativeActionAllowlistResult: Codable, Hashable, Sendable {
    case allowed
    case blocked(String)

    public var blockedReason: String? {
        switch self {
        case .allowed:
            return nil
        case .blocked(let reason):
            return reason
        }
    }
}

public enum NativeActionAllowlist {
    public static func validate(_ command: NativeActionCommand) -> NativeActionAllowlistResult {
        if containsShellMetacharacter(command.executable) || command.arguments.contains(where: containsShellMetacharacter) {
            return .blocked("shell metacharacters are not allowed")
        }

        if isShellExecutable(command.executable) {
            return .blocked("shell execution is not allowed")
        }

        switch command.kind {
        case .homebrewCleanup:
            guard isBrewExecutable(command.executable) else {
                return .blocked("unexpected executable for homebrewCleanup")
            }
            guard command.arguments == ["cleanup"]
                || command.arguments == ["cleanup", "--dry-run"]
                || command.arguments == ["cleanup", "-n"] else {
                return .blocked("unexpected arguments for homebrewCleanup")
            }
            return .allowed

        case .dockerBuilderPrune:
            guard isDockerExecutable(command.executable) else {
                return .blocked("unexpected executable for dockerBuilderPrune")
            }
            guard command.arguments == ["builder", "prune", "--force"]
                || command.arguments == ["system", "df", "-v"] else {
                return .blocked("unexpected arguments for dockerBuilderPrune")
            }
            return .allowed

        case .npmCacheClean:
            guard isNpmExecutable(command.executable) else {
                return .blocked("unexpected executable for npmCacheClean")
            }
            guard command.arguments == ["cache", "verify"]
                || command.arguments == ["cache", "clean", "--force"] else {
                return .blocked("unexpected arguments for npmCacheClean")
            }
            return .allowed

        case .auditPrune, .trashAppBundle, .packageCacheGuidance, .openFinderReview:
            return .blocked("native command execution is not implemented for \(command.kind.rawValue)")
        }
    }

    private static func isBrewExecutable(_ executable: String) -> Bool {
        let last = URL(fileURLWithPath: executable).lastPathComponent
        return executable == "brew" || last == "brew"
    }

    private static func isDockerExecutable(_ executable: String) -> Bool {
        let last = URL(fileURLWithPath: executable).lastPathComponent
        return executable == "docker" || last == "docker"
    }

    private static func isNpmExecutable(_ executable: String) -> Bool {
        let last = URL(fileURLWithPath: executable).lastPathComponent
        return executable == "npm" || last == "npm"
    }

    private static func isShellExecutable(_ executable: String) -> Bool {
        let last = URL(fileURLWithPath: executable).lastPathComponent
        return ["sh", "bash", "zsh", "fish"].contains(last)
    }

    private static func containsShellMetacharacter(_ value: String) -> Bool {
        value.contains("&&")
            || value.contains(";")
            || value.contains("\n")
            || value.contains("`")
            || value.contains("$(")
    }
}
