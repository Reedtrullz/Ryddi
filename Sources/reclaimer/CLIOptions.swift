import Foundation
import ReclaimerCore

struct ParsedOptions {
    let args: [String]

    init(_ args: [String]) {
        self.args = args
    }

    var json: Bool { args.contains("--json") }
    var dryRun: Bool { args.contains("--dry-run") || !args.contains("--yes") }
    var yes: Bool { args.contains("--yes") }
    var reviewAll: Bool { args.contains("--review-all") }
    var saveAudit: Bool { args.contains("--save-audit") }
    var saveHistory: Bool { args.contains("--save-history") }
    var saveReport: Bool { args.contains("--save-report") }
    var includeOpenFiles: Bool { args.contains("--include-open-files") }
    var includeMissingScopes: Bool { args.contains("--include-missing-scopes") }
    var includeVCSStatus: Bool { args.contains("--include-vcs-status") }
    var includePolicySkippedProjects: Bool { args.contains("--include-policy-skipped") }
    var noLsof: Bool { args.contains("--no-lsof") }
    var hasPath: Bool { !values(after: "--path").isEmpty }
    var hasCustomScopeSelection: Bool { hasPath || scopeTemplateReference != nil || scopeSetReference != nil }
    var includePreserve: Bool { args.contains("--include-preserve") }
    var showExcluded: Bool { args.contains("--show-excluded") }
    var includeSystemApps: Bool { args.contains("--include-system-apps") }
    var includeOrphans: Bool { !args.contains("--no-orphans") }
    var includeCommandCards: Bool { !args.contains("--no-command-cards") }
    var ignoreUserPolicy: Bool { args.contains("--ignore-user-policy") }
    var includeUserRules: Bool { args.contains("--include-user-rules") }
    var replacePolicy: Bool { args.contains("--replace") }
    var hour: Int { Int(value(after: "--hour") ?? "") ?? 9 }
    var minute: Int { Int(value(after: "--minute") ?? "") ?? 30 }
    var limit: Int { max(1, Int(value(after: "--limit") ?? "") ?? 80) }
    var drilldownDepth: Int { max(0, Int(value(after: "--tree-depth") ?? value(after: "--max-depth") ?? "") ?? 3) }
    var presetName: String { value(after: "--preset") ?? ScanScopePreset.developer.rawValue }
    var sort: String { value(after: "--sort") ?? "size" }
    var group: String? { value(after: "--group") }
    var growthGroup: GrowthGroup { GrowthGroup(rawValue: group ?? "category") ?? .category }
    var review: String { value(after: "--review") ?? "all" }
    var largeThreshold: Int64 { Int64(value(after: "--large-threshold") ?? "") ?? 5_000_000_000 }
    var oldDays: Int { Int(value(after: "--old-days") ?? "") ?? 180 }
    var measurementBudget: Int { max(1, Int(value(after: "--measurement-budget") ?? "") ?? 25_000) }
    var measurementDepth: Int? { value(after: "--measurement-depth").flatMap(Int.init).map { max(0, $0) } }
    var deduplicateHardLinks: Bool { !args.contains("--no-deduplicate-hardlinks") }
    var auditOlderThanDays: Int { max(0, Int(value(after: "--older-than-days") ?? value(after: "--old-days") ?? "") ?? SafeActionPlanner.defaultAuditRetention.olderThanDays) }
    var keepRecent: Int { max(0, Int(value(after: "--keep-recent") ?? "") ?? SafeActionPlanner.defaultAuditRetention.keepRecent) }
    var maxFilesToHash: Int { max(1, Int(value(after: "--max-files") ?? "") ?? 5_000) }
    var reason: String? { value(after: "--reason") }
    var summary: String? { value(after: "--summary") }
    var outputPath: String? { value(after: "--output") }
    var releaseManifestPath: String { value(after: "--manifest") ?? "dist/Ryddi-release-manifest.txt" }
    var reportTitle: String { value(after: "--title") ?? "Ryddi Evidence Report" }
    var planReportTitle: String { value(after: "--title") ?? "Ryddi Plan Report" }
    var receiptReportTitle: String { value(after: "--title") ?? "Ryddi Receipt Report" }
    var nativeReceiptReportTitle: String { value(after: "--title") ?? "Ryddi Native Command Receipt Report" }
    var growthReportTitle: String { value(after: "--title") ?? "Ryddi Growth Report" }
    var appUninstallPreviewTitle: String { value(after: "--title") ?? "Ryddi App Uninstall Preview" }
    var archiveReviewTitle: String { value(after: "--title") ?? "Ryddi Archive Candidate Review" }
    var planID: String? { value(after: "--id") }
    var receiptID: String? { value(after: "--id") }
    var currentSnapshotID: String? { value(after: "--current-id") }
    var previousSnapshotID: String? { value(after: "--previous-id") }
    var scopeTemplateReference: String? { value(after: "--template") }
    var scopeSetReference: String? { value(after: "--scope-set") }
    var commandID: String? { value(after: "--command-id") }
    var nativeFindingPath: String? { value(after: "--finding-path") }
    var reportPrivacy: ReportPrivacyOptions {
        ReportPrivacyOptions(pathStyle: reportPathStyle, redactUserText: args.contains("--redact-user-text"))
    }
    var reportPathStyle: ReportPathStyle {
        if args.contains("--redact-paths") {
            return .redacted
        }
        if args.contains("--home-relative") {
            return .homeRelative
        }
        if let raw = value(after: "--path-style"), let style = ReportPathStyle(rawValue: raw) {
            return style
        }
        return .full
    }
    var policyKind: UserPathPolicyKind? {
        switch value(after: "--kind") {
        case "protect": .protect
        case "exclude": .exclude
        case nil: nil
        default: nil
        }
    }
    var projectDependencyPolicyDecision: ProjectDependencyPolicyDecision? {
        switch value(after: "--decision") {
        case "review": .review
        case "preserve": .preserve
        case "skip", "skip-review": .skipReview
        case nil: nil
        default: nil
        }
    }
    var timeoutSeconds: TimeInterval {
        let value = Double(value(after: "--timeout") ?? "") ?? 5
        return max(1, min(value, 60))
    }

    func values(after flag: String) -> [String] {
        var values: [String] = []
        var index = 0
        while index < args.count {
            guard args[index] == flag else {
                index += 1
                continue
            }
            index += 1
            while index < args.count, !args[index].hasPrefix("--") {
                values.append(args[index])
                index += 1
            }
        }
        return values
    }

    func value(after flag: String) -> String? {
        guard let index = args.firstIndex(of: flag), args.indices.contains(index + 1) else { return nil }
        return args[index + 1]
    }

    func validateReportPrivacyOptions() throws {
        if let raw = value(after: "--path-style"), ReportPathStyle(rawValue: raw) == nil {
            let allowed = ReportPathStyle.allCases.map(\.rawValue).joined(separator: ", ")
            throw CLIError.message("--path-style must be one of: \(allowed)")
        }
    }

    func scopePreset() throws -> ScanScopePreset {
        guard let preset = ScanScopePreset(rawValue: presetName) else {
            let allowed = ScanScopePreset.allCases.map(\.rawValue).joined(separator: ", ")
            throw CLIError.message("--preset must be one of: \(allowed)")
        }
        return preset
    }

    func remoteScanPreset() throws -> RemoteScanPreset {
        let raw = value(after: "--preset") ?? RemoteScanPreset.vpsGeneral.rawValue
        guard let preset = RemoteScanPreset(rawValue: raw) else {
            let allowed = RemoteScanPreset.allCases.map(\.rawValue).joined(separator: ", ")
            throw CLIError.message("--preset must be one of: \(allowed)")
        }
        return preset
    }

    func topOffenderSort() throws -> TopOffenderSort {
        guard let offenderSort = TopOffenderSort.parse(sort) else {
            let allowed = (["size"] + TopOffenderSort.allCases.map(\.rawValue)).joined(separator: ", ")
            throw CLIError.message("--sort must be one of: \(allowed)")
        }
        return offenderSort
    }

    func topOffenderGroup() throws -> TopOffenderGroup {
        guard let raw = group else { return .none }
        guard let offenderGroup = TopOffenderGroup(rawValue: raw) else {
            let allowed = TopOffenderGroup.allCases.map(\.rawValue).joined(separator: ", ")
            throw CLIError.message("--group must be one of: \(allowed)")
        }
        return offenderGroup
    }

    func largeOldReviewMode() throws -> LargeOldReviewMode {
        guard let mode = LargeOldReviewMode(rawValue: review) else {
            let allowed = LargeOldReviewMode.allCases.map(\.rawValue).joined(separator: ", ")
            throw CLIError.message("--review must be one of: \(allowed)")
        }
        return mode
    }

    func agentRetentionProfile() throws -> AgentRetentionProfile {
        let raw = value(after: "--profile")?.lowercased() ?? AgentRetentionProfile.balanced.rawValue
        guard let profile = AgentRetentionProfile(rawValue: raw) else {
            let allowed = AgentRetentionProfile.allCases.map(\.rawValue).joined(separator: ", ")
            throw CLIError.message("--profile must be one of: \(allowed)")
        }
        return profile
    }

    func scheduleConfiguration() throws -> ScheduleConfiguration {
        let kindName = value(after: "--kind") ?? ScheduledReportKind.plan.rawValue
        guard let reportKind = ScheduledReportKind(rawValue: kindName) else {
            let allowed = ScheduledReportKind.allCases.map(\.rawValue).joined(separator: ", ")
            throw CLIError.message("--kind must be one of: \(allowed)")
        }
        guard (0...23).contains(hour) else {
            throw CLIError.message("--hour must be between 0 and 23")
        }
        guard (0...59).contains(minute) else {
            throw CLIError.message("--minute must be between 0 and 59")
        }
        let selection: ScheduledScopeSelection
        if scopeTemplateReference != nil, scopeSetReference != nil {
            throw CLIError.message("--template and --scope-set cannot be used together")
        }
        if let scopeTemplateReference {
            _ = try ScopeTemplateCatalog.find(scopeTemplateReference, includeUnavailable: true)
            selection = ScheduledScopeSelection(template: scopeTemplateReference)
        } else if let scopeSetReference {
            _ = try SavedScopeSetStore().find(scopeSetReference)
            selection = ScheduledScopeSelection(savedScopeSet: scopeSetReference)
        } else {
            selection = ScheduledScopeSelection(preset: try scopePreset())
        }
        return ScheduleConfiguration(
            hour: hour,
            minute: minute,
            reportKind: reportKind,
            scopeSelection: selection,
            limit: limit,
            includeUserRules: includeUserRules
        )
    }

    func reviewQueueID() throws -> ReviewQueueID? {
        guard let raw = value(after: "--queue") else { return nil }
        guard let queueID = ReviewQueueID.parse(raw) else {
            let allowed = ReviewQueueID.allCases.map { "\($0.rawValue) / \($0.title.lowercased().replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: " ", with: "-"))" }
                .joined(separator: ", ")
            throw CLIError.message("--queue must be one of: \(allowed)")
        }
        return queueID
    }

    func scopePlan(includeUnavailable: Bool = false) throws -> ScanScopePlan {
        let paths = values(after: "--path")
        if !paths.isEmpty {
            let scopes = paths.map {
                let url = URL(fileURLWithPath: $0).standardizedFileURL
                return ScanScope(name: url.lastPathComponent, root: url)
            }
            return DefaultScopes.customPlan(scopes: scopes)
        }
        if scopeTemplateReference != nil, scopeSetReference != nil {
            throw CLIError.message("--template and --scope-set cannot be used together")
        }
        if let scopeTemplateReference {
            return try ScopeTemplateCatalog.plan(reference: scopeTemplateReference, includeUnavailable: includeUnavailable)
        }
        if let scopeSetReference {
            return try SavedScopeSetStore().plan(reference: scopeSetReference)
        }
        return DefaultScopes.plan(for: try scopePreset(), includeUnavailable: includeUnavailable)
    }

    func scopes(includeUnavailable: Bool = false) throws -> [ScanScope] {
        try scopePlan(includeUnavailable: includeUnavailable).scopes
    }

    func scanOptions(includeOpenFiles: Bool) -> ScanOptions {
        let minSize = Int64(value(after: "--min-size") ?? "") ?? 1_000_000
        let maxDepth = Int(value(after: "--max-depth") ?? "") ?? 2
        return ScanOptions(
            minimumFindingSize: minSize,
            maximumFindingDepth: maxDepth,
            measurementDepth: measurementDepth ?? (maxDepth + 4),
            includeOpenFileStatus: includeOpenFiles,
            largeFileThreshold: largeThreshold,
            oldFileAgeDays: oldDays,
            userPathPolicy: userPathPolicy,
            measurementItemBudget: measurementBudget,
            deduplicateHardLinks: deduplicateHardLinks
        )
    }

    func ruleEngine() throws -> RuleEngine {
        try RuleEngine.bundled(includingUserRules: includeUserRules)
    }

    var userPathPolicy: UserPathPolicy {
        ignoreUserPolicy ? .empty : UserPathPolicyStore().load()
    }

    var duplicateOptions: DuplicateReviewOptions {
        let minSize = Int64(value(after: "--min-size") ?? "") ?? 1_000_000
        let maxDepth = Int(value(after: "--max-depth") ?? "") ?? 6
        return DuplicateReviewOptions(
            minimumFileSize: minSize,
            maximumDepth: maxDepth,
            maximumFilesToHash: maxFilesToHash,
            includeHidden: !args.contains("--skip-hidden"),
            includePreserveByDefault: includePreserve
        )
    }

    var appReviewOptions: AppReviewOptions {
        let minSize = Int64(value(after: "--min-size") ?? "") ?? 1_000_000
        let home = value(after: "--home").map { URL(fileURLWithPath: $0).standardizedFileURL }
            ?? FileManager.default.homeDirectoryForCurrentUser
        let roots = values(after: "--path").map { URL(fileURLWithPath: $0).standardizedFileURL }
        return AppReviewOptions(
            appRoots: roots.isEmpty ? nil : roots,
            home: home,
            includeSystemApplications: includeSystemApps,
            includeOrphanCandidates: includeOrphans,
            minimumRelatedSize: minSize
        )
    }

    var appUninstallSelector: AppUninstallSelector {
        AppUninstallSelector(
            appPath: value(after: "--app"),
            bundleIdentifier: value(after: "--bundle-id"),
            displayName: value(after: "--name")
        )
    }

    func prepare(_ findings: [Finding]) -> [Finding] {
        let filtered = findings.filter { finding in
            switch review {
            case "large":
                finding.ruleMatches.contains { $0.ruleID == "dynamic.large-item.review" }
            case "old":
                finding.ruleMatches.contains { $0.ruleID == "dynamic.old-item.review" }
            default:
                true
            }
        }
        return filtered.sorted { lhs, rhs in
            switch sort {
            case "logical":
                return sort(lhs.logicalSize, rhs.logicalSize, lhs.path, rhs.path)
            case "age":
                return sort(Int64(lhs.ageInDays() ?? -1), Int64(rhs.ageInDays() ?? -1), lhs.path, rhs.path)
            case "risk":
                if lhs.safetyClass.riskRank == rhs.safetyClass.riskRank {
                    return lhs.allocatedSize > rhs.allocatedSize
                }
                return lhs.safetyClass.riskRank < rhs.safetyClass.riskRank
            case "category":
                if lhs.primaryCategory == rhs.primaryCategory {
                    return lhs.allocatedSize > rhs.allocatedSize
                }
                return lhs.primaryCategory < rhs.primaryCategory
            case "scope":
                if lhs.scopeName == rhs.scopeName {
                    return lhs.allocatedSize > rhs.allocatedSize
                }
                return lhs.scopeName < rhs.scopeName
            default:
                return sort(lhs.allocatedSize, rhs.allocatedSize, lhs.path, rhs.path)
            }
        }
    }

    private func sort(_ lhsValue: Int64, _ rhsValue: Int64, _ lhsPath: String, _ rhsPath: String) -> Bool {
        if lhsValue == rhsValue {
            return lhsPath < rhsPath
        }
        return lhsValue > rhsValue
    }
}
