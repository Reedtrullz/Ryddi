import Foundation

public enum AgentStorageBucket: String, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    case reclaimableCache
    case quitFirst
    case valuableHistory
    case protectedState
    case manualReview
    case unknown

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .reclaimableCache: "Reclaimable cache"
        case .quitFirst: "Quit app first"
        case .valuableHistory: "Valuable history"
        case .protectedState: "Protected state"
        case .manualReview: "Manual review"
        case .unknown: "Unknown"
        }
    }

    public var guidance: String {
        switch self {
        case .reclaimableCache:
            "Rebuildable cache, log, or temporary data. Ryddi can plan cleanup only after open-file checks."
        case .quitFirst:
            "Likely rebuildable data, but the owning app or tool should be quit before any cleanup."
        case .valuableHistory:
            "Sessions, transcripts, projects, and other provenance can be useful. Review or compress instead of auto-deleting."
        case .protectedState:
            "Credentials, config, memories, model state, profiles, and app databases are blocked from cleanup."
        case .manualReview:
            "Agent-related storage without enough evidence for automation. Open and inspect before acting."
        case .unknown:
            "Ryddi could not confidently classify this item. Treat it as review-only."
        }
    }
}

public struct AgentStorageBucketSummary: Codable, Hashable, Identifiable, Sendable {
    public var id: AgentStorageBucket { bucket }
    public let bucket: AgentStorageBucket
    public let count: Int
    public let bytes: Int64

    public init(bucket: AgentStorageBucket, count: Int, bytes: Int64) {
        self.bucket = bucket
        self.count = count
        self.bytes = bytes
    }
}

public struct AgentStorageOwnerSummary: Codable, Hashable, Identifiable, Sendable {
    public var id: String { owner }
    public let owner: String
    public let count: Int
    public let bytes: Int64
    public let reclaimableBytes: Int64
    public let protectedBytes: Int64
    public let dominantBucket: AgentStorageBucket

    public init(
        owner: String,
        count: Int,
        bytes: Int64,
        reclaimableBytes: Int64,
        protectedBytes: Int64,
        dominantBucket: AgentStorageBucket
    ) {
        self.owner = owner
        self.count = count
        self.bytes = bytes
        self.reclaimableBytes = reclaimableBytes
        self.protectedBytes = protectedBytes
        self.dominantBucket = dominantBucket
    }
}

public struct AgentStorageItem: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let owner: String
    public let bucket: AgentStorageBucket
    public let path: String
    public let displayName: String
    public let allocatedSize: Int64
    public let logicalSize: Int64
    public let modificationDate: Date?
    public let safetyClass: SafetyClass
    public let actionKind: ActionKind
    public let ruleIDs: [String]
    public let evidence: [String]
    public let guidance: [String]

    public init(
        id: String,
        owner: String,
        bucket: AgentStorageBucket,
        path: String,
        displayName: String,
        allocatedSize: Int64,
        logicalSize: Int64,
        modificationDate: Date?,
        safetyClass: SafetyClass,
        actionKind: ActionKind,
        ruleIDs: [String],
        evidence: [String],
        guidance: [String]
    ) {
        self.id = id
        self.owner = owner
        self.bucket = bucket
        self.path = path
        self.displayName = displayName
        self.allocatedSize = allocatedSize
        self.logicalSize = logicalSize
        self.modificationDate = modificationDate
        self.safetyClass = safetyClass
        self.actionKind = actionKind
        self.ruleIDs = ruleIDs
        self.evidence = evidence
        self.guidance = guidance
    }
}

public struct AgentStorageReview: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let createdAt: Date
    public let scannedRoots: [ScanScope]
    public let itemCount: Int
    public let totalBytes: Int64
    public let reclaimableBytes: Int64
    public let protectedBytes: Int64
    public let bucketSummaries: [AgentStorageBucketSummary]
    public let ownerSummaries: [AgentStorageOwnerSummary]
    public let items: [AgentStorageItem]
    public let nonClaims: [String]

    public init(
        id: String = UUID().uuidString,
        createdAt: Date,
        scannedRoots: [ScanScope],
        itemCount: Int,
        totalBytes: Int64,
        reclaimableBytes: Int64,
        protectedBytes: Int64,
        bucketSummaries: [AgentStorageBucketSummary],
        ownerSummaries: [AgentStorageOwnerSummary],
        items: [AgentStorageItem],
        nonClaims: [String]
    ) {
        self.id = id
        self.createdAt = createdAt
        self.scannedRoots = scannedRoots
        self.itemCount = itemCount
        self.totalBytes = totalBytes
        self.reclaimableBytes = reclaimableBytes
        self.protectedBytes = protectedBytes
        self.bucketSummaries = bucketSummaries
        self.ownerSummaries = ownerSummaries
        self.items = items
        self.nonClaims = nonClaims
    }
}

public enum AgentStorageReviewBuilder {
    public static func build(
        findings: [Finding],
        scopes: [ScanScope],
        limit: Int = 80,
        generatedAt: Date = Date()
    ) -> AgentStorageReview {
        let nonRootFindings = findings.filter { finding in
            !finding.evidence.contains { $0.kind == "scope" }
        }
        let sourceFindings = nonRootFindings.isEmpty ? findings : nonRootFindings
        let items = sourceFindings
            .compactMap(makeItem(from:))
            .sorted(by: sortItems)
        let accountingItems = nonOverlapping(items)
        let totalBytes = accountingItems.reduce(0) { $0 + $1.allocatedSize }
        let reclaimableBytes = accountingItems
            .filter { $0.bucket == .reclaimableCache }
            .reduce(0) { $0 + $1.allocatedSize }
        let protectedBytes = accountingItems
            .filter { [.protectedState, .valuableHistory].contains($0.bucket) }
            .reduce(0) { $0 + $1.allocatedSize }

        return AgentStorageReview(
            createdAt: generatedAt,
            scannedRoots: scopes,
            itemCount: items.count,
            totalBytes: totalBytes,
            reclaimableBytes: reclaimableBytes,
            protectedBytes: protectedBytes,
            bucketSummaries: bucketSummaries(from: accountingItems),
            ownerSummaries: ownerSummaries(from: accountingItems),
            items: Array(items.prefix(limit)),
            nonClaims: [
                "Ryddi does not delete agent sessions, memories, credentials, config, model state, or browser/editor profiles automatically.",
                "Cache and log items still require the normal plan, dry-run, revalidation, and open-file checks before cleanup.",
                "Agent storage can contain private prompts, transcripts, file names, and project paths; reports stay local unless the user exports and shares them.",
                "Large model files and VM/container disks are reported for review or native-tool guidance, not raw-deleted by this report."
            ]
        )
    }

    private static func makeItem(from finding: Finding) -> AgentStorageItem? {
        guard let owner = agentOwner(for: finding) else { return nil }
        let bucket = bucket(for: finding)
        let ruleIDs = finding.ruleMatches.map(\.ruleID)
        let evidence = finding.evidence.prefix(5).map(\.message)
        return AgentStorageItem(
            id: finding.id,
            owner: owner,
            bucket: bucket,
            path: finding.path,
            displayName: finding.displayName,
            allocatedSize: finding.allocatedSize,
            logicalSize: finding.logicalSize,
            modificationDate: finding.modificationDate,
            safetyClass: finding.safetyClass,
            actionKind: finding.actionKind,
            ruleIDs: ruleIDs,
            evidence: Array(evidence),
            guidance: guidance(for: finding, bucket: bucket)
        )
    }

    private static func agentOwner(for finding: Finding) -> String? {
        if let ownerHint = finding.ownerHint, agentOwners.contains(ownerHint) {
            return ownerHint
        }
        if finding.ruleMatches.contains(where: { $0.category == "Codex" }) {
            return "Codex"
        }

        let lower = finding.path.lowercased()
        if lower.contains("/.codex") ||
            lower.contains("/library/caches/codex") ||
            lower.contains("/library/logs/com.openai.codex") ||
            lower.contains("com.openai.codex")
        {
            return "Codex"
        }
        if lower.contains("/.claude") || lower.contains("/application support/claude") {
            return "Claude"
        }
        if lower.contains("/application support/cursor") {
            return "Cursor"
        }
        if lower.contains("/application support/windsurf") {
            return "Windsurf"
        }
        if lower.contains("/.ollama") {
            return "Ollama"
        }
        return nil
    }

    private static func bucket(for finding: Finding) -> AgentStorageBucket {
        switch finding.safetyClass {
        case .autoSafe:
            return .reclaimableCache
        case .safeAfterCondition:
            return .quitFirst
        case .neverTouch:
            return .protectedState
        case .preserveByDefault:
            if finding.actionKind == .compress || isHistoryPath(finding.path) {
                return .valuableHistory
            }
            return .protectedState
        case .reviewRequired:
            if isHistoryPath(finding.path) {
                return .valuableHistory
            }
            return isProtectedPath(finding.path) ? .protectedState : .manualReview
        }
    }

    private static func guidance(for finding: Finding, bucket: AgentStorageBucket) -> [String] {
        var lines = [bucket.guidance]
        switch bucket {
        case .reclaimableCache:
            lines.append("Use a dry-run plan before reclaiming; active paths are skipped.")
        case .quitFirst:
            lines.append("Quit the owning app/tool, rescan, then use the indicated Trash/delete-cache guidance.")
        case .valuableHistory:
            lines.append("Prefer compression or export after review if the history is old but still useful.")
        case .protectedState:
            lines.append("Keep this path protected unless you are intentionally resetting the app or account state.")
        case .manualReview, .unknown:
            lines.append("Open in Finder or Terminal and confirm it is not unique work before removing anything.")
        }
        if finding.actionKind == .nativeToolCommand {
            lines.append("Use native tool guidance instead of deleting files directly.")
        }
        return lines
    }

    private static func bucketSummaries(from items: [AgentStorageItem]) -> [AgentStorageBucketSummary] {
        let grouped = Dictionary(grouping: items, by: \.bucket)
        return AgentStorageBucket.allCases.compactMap { bucket in
            guard let bucketItems = grouped[bucket], !bucketItems.isEmpty else { return nil }
            return AgentStorageBucketSummary(
                bucket: bucket,
                count: bucketItems.count,
                bytes: bucketItems.reduce(0) { $0 + $1.allocatedSize }
            )
        }
    }

    private static func ownerSummaries(from items: [AgentStorageItem]) -> [AgentStorageOwnerSummary] {
        Dictionary(grouping: items, by: \.owner)
            .map { owner, ownerItems in
                let bytes = ownerItems.reduce(0) { $0 + $1.allocatedSize }
                let reclaimable = ownerItems
                    .filter { $0.bucket == .reclaimableCache }
                    .reduce(0) { $0 + $1.allocatedSize }
                let protected = ownerItems
                    .filter { [.protectedState, .valuableHistory].contains($0.bucket) }
                    .reduce(0) { $0 + $1.allocatedSize }
                return AgentStorageOwnerSummary(
                    owner: owner,
                    count: ownerItems.count,
                    bytes: bytes,
                    reclaimableBytes: reclaimable,
                    protectedBytes: protected,
                    dominantBucket: dominantBucket(in: ownerItems)
                )
            }
            .sorted {
                if $0.bytes == $1.bytes {
                    return $0.owner < $1.owner
                }
                return $0.bytes > $1.bytes
            }
    }

    private static func dominantBucket(in items: [AgentStorageItem]) -> AgentStorageBucket {
        Dictionary(grouping: items, by: \.bucket)
            .map { bucket, bucketItems in
                (bucket, bucketItems.reduce(0) { $0 + $1.allocatedSize })
            }
            .sorted {
                if $0.1 == $1.1 {
                    return $0.0.label < $1.0.label
                }
                return $0.1 > $1.1
            }
            .first?.0 ?? .unknown
    }

    private static func nonOverlapping(_ items: [AgentStorageItem]) -> [AgentStorageItem] {
        let ordered = items.sorted { lhs, rhs in
            let lhsDepth = URL(fileURLWithPath: lhs.path).standardizedFileURL.pathComponents.count
            let rhsDepth = URL(fileURLWithPath: rhs.path).standardizedFileURL.pathComponents.count
            if lhsDepth == rhsDepth {
                return lhs.path < rhs.path
            }
            return lhsDepth < rhsDepth
        }
        var selected: [AgentStorageItem] = []
        var selectedPaths: [String] = []
        for item in ordered {
            let path = URL(fileURLWithPath: item.path).standardizedFileURL.path
            guard !selectedPaths.contains(where: { isDescendant(path, of: $0) }) else { continue }
            selected.append(item)
            selectedPaths.append(path)
        }
        return selected
    }

    private static func isHistoryPath(_ path: String) -> Bool {
        let lower = path.lowercased()
        return lower.contains("/sessions") ||
            lower.contains("/archived_sessions") ||
            lower.contains("/transcripts") ||
            lower.contains("/projects") ||
            lower.contains("/history") ||
            lower.contains("/conversations")
    }

    private static func isProtectedPath(_ path: String) -> Bool {
        let lower = path.lowercased()
        return lower.contains("/auth") ||
            lower.contains("/config") ||
            lower.contains("/credentials") ||
            lower.contains("/memories") ||
            lower.contains("/state") ||
            lower.contains("/database") ||
            lower.contains("/models")
    }

    private static func isDescendant(_ path: String, of ancestor: String) -> Bool {
        guard path != ancestor else { return false }
        let ancestorWithSlash = ancestor.hasSuffix("/") ? ancestor : ancestor + "/"
        return path.hasPrefix(ancestorWithSlash)
    }

    private static func sortItems(_ lhs: AgentStorageItem, _ rhs: AgentStorageItem) -> Bool {
        if lhs.allocatedSize == rhs.allocatedSize {
            return lhs.path < rhs.path
        }
        return lhs.allocatedSize > rhs.allocatedSize
    }

    private static let agentOwners: Set<String> = [
        "Codex",
        "Claude",
        "Cursor",
        "Windsurf",
        "Ollama"
    ]
}

public enum AgentRetentionProfile: String, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    case conservative
    case balanced
    case aggressive

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .conservative: "Conservative"
        case .balanced: "Balanced"
        case .aggressive: "Aggressive"
        }
    }

    public var summary: String {
        switch self {
        case .conservative:
            "Prefer long retention. Review old cache/log churn and compress old history only after it is clearly cold."
        case .balanced:
            "Reduce routine growth while preserving useful sessions, memories, credentials, config, and model state."
        case .aggressive:
            "Surface shorter-retention candidates for machines under disk pressure while still blocking protected state."
        }
    }

    public var cacheAgeDays: Int {
        switch self {
        case .conservative: 30
        case .balanced: 14
        case .aggressive: 7
        }
    }

    public var quitFirstAgeDays: Int {
        switch self {
        case .conservative: 45
        case .balanced: 21
        case .aggressive: 10
        }
    }

    public var historyCompressAgeDays: Int {
        switch self {
        case .conservative: 365
        case .balanced: 180
        case .aggressive: 90
        }
    }

    public var manualReviewAgeDays: Int {
        switch self {
        case .conservative: 365
        case .balanced: 180
        case .aggressive: 90
        }
    }
}

public enum AgentRetentionRecommendationKind: String, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    case cleanupPlan
    case quitThenCleanup
    case compressAfterReview
    case manualReview
    case keep
    case protect

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .cleanupPlan: "Use Cleanup Plan"
        case .quitThenCleanup: "Quit Then Cleanup"
        case .compressAfterReview: "Compress After Review"
        case .manualReview: "Manual Review"
        case .keep: "Keep"
        case .protect: "Protect"
        }
    }
}

public struct AgentRetentionSummary: Codable, Hashable, Identifiable, Sendable {
    public var id: AgentRetentionRecommendationKind { recommendation }
    public let recommendation: AgentRetentionRecommendationKind
    public let count: Int
    public let bytes: Int64

    public init(recommendation: AgentRetentionRecommendationKind, count: Int, bytes: Int64) {
        self.recommendation = recommendation
        self.count = count
        self.bytes = bytes
    }
}

public struct AgentRetentionRecommendation: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let owner: String
    public let bucket: AgentStorageBucket
    public let path: String
    public let displayName: String
    public let allocatedSize: Int64
    public let ageDays: Int?
    public let recommendation: AgentRetentionRecommendationKind
    public let actionKind: ActionKind
    public let eligibleForCleanupPlan: Bool
    public let reason: String
    public let nextSteps: [String]

    public init(
        id: String,
        owner: String,
        bucket: AgentStorageBucket,
        path: String,
        displayName: String,
        allocatedSize: Int64,
        ageDays: Int?,
        recommendation: AgentRetentionRecommendationKind,
        actionKind: ActionKind,
        eligibleForCleanupPlan: Bool,
        reason: String,
        nextSteps: [String]
    ) {
        self.id = id
        self.owner = owner
        self.bucket = bucket
        self.path = path
        self.displayName = displayName
        self.allocatedSize = allocatedSize
        self.ageDays = ageDays
        self.recommendation = recommendation
        self.actionKind = actionKind
        self.eligibleForCleanupPlan = eligibleForCleanupPlan
        self.reason = reason
        self.nextSteps = nextSteps
    }
}

public struct AgentRetentionReport: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let createdAt: Date
    public let profile: AgentRetentionProfile
    public let profileSummary: String
    public let reviewedItemCount: Int
    public let totalBytes: Int64
    public let cleanupCandidateBytes: Int64
    public let compressionCandidateBytes: Int64
    public let protectedBytes: Int64
    public let summaries: [AgentRetentionSummary]
    public let recommendations: [AgentRetentionRecommendation]
    public let nonClaims: [String]

    public init(
        id: String = UUID().uuidString,
        createdAt: Date = Date(),
        profile: AgentRetentionProfile,
        profileSummary: String,
        reviewedItemCount: Int,
        totalBytes: Int64,
        cleanupCandidateBytes: Int64,
        compressionCandidateBytes: Int64,
        protectedBytes: Int64,
        summaries: [AgentRetentionSummary],
        recommendations: [AgentRetentionRecommendation],
        nonClaims: [String]
    ) {
        self.id = id
        self.createdAt = createdAt
        self.profile = profile
        self.profileSummary = profileSummary
        self.reviewedItemCount = reviewedItemCount
        self.totalBytes = totalBytes
        self.cleanupCandidateBytes = cleanupCandidateBytes
        self.compressionCandidateBytes = compressionCandidateBytes
        self.protectedBytes = protectedBytes
        self.summaries = summaries
        self.recommendations = recommendations
        self.nonClaims = nonClaims
    }
}

public enum AgentRetentionBuilder {
    public static func build(
        review: AgentStorageReview,
        profile: AgentRetentionProfile = .balanced,
        limit: Int = 80,
        referenceDate: Date = Date(),
        generatedAt: Date = Date()
    ) -> AgentRetentionReport {
        let rows = review.items
            .map { recommendation(for: $0, profile: profile, referenceDate: referenceDate) }
            .sorted(by: sortRecommendations)
        let limitedRows = Array(rows.prefix(limit))
        return AgentRetentionReport(
            createdAt: generatedAt,
            profile: profile,
            profileSummary: profile.summary,
            reviewedItemCount: review.items.count,
            totalBytes: review.totalBytes,
            cleanupCandidateBytes: rows
                .filter { [.cleanupPlan, .quitThenCleanup].contains($0.recommendation) }
                .reduce(0) { $0 + $1.allocatedSize },
            compressionCandidateBytes: rows
                .filter { $0.recommendation == .compressAfterReview }
                .reduce(0) { $0 + $1.allocatedSize },
            protectedBytes: rows
                .filter { $0.recommendation == .protect }
                .reduce(0) { $0 + $1.allocatedSize },
            summaries: summaries(from: rows),
            recommendations: limitedRows,
            nonClaims: [
                "This retention report does not delete, compress, move, or modify agent files.",
                "Agent sessions, memories, credentials, config, model state, and unknown app state remain protected or review-only.",
                "Cleanup recommendations still require the normal plan, dry-run, open-file checks, and final confirmation before any action.",
                "Compression recommendations are review guidance only; Ryddi does not compress agent history from this report."
            ]
        )
    }

    private static func recommendation(
        for item: AgentStorageItem,
        profile: AgentRetentionProfile,
        referenceDate: Date
    ) -> AgentRetentionRecommendation {
        let ageDays = item.modificationDate.map { ageInDays(from: $0, referenceDate: referenceDate) }
        let decision: (AgentRetentionRecommendationKind, ActionKind, Bool, String, [String])

        switch item.bucket {
        case .reclaimableCache:
            if let ageDays, ageDays >= profile.cacheAgeDays {
                decision = (
                    .cleanupPlan,
                    item.actionKind,
                    item.safetyClass == .autoSafe,
                    "\(item.owner) cache/log data is at least \(profile.cacheAgeDays) days old under the \(profile.label) profile.",
                    [
                        "Run a normal Ryddi plan and dry-run before cleanup.",
                        "Confirm the owning app or agent is not actively using this path."
                    ]
                )
            } else {
                decision = (
                    .keep,
                    .reportOnly,
                    false,
                    ageReason(ageDays: ageDays, threshold: profile.cacheAgeDays, label: "cache/log"),
                    ["Let this cache age or review manually if disk pressure is urgent."]
                )
            }
        case .quitFirst:
            if let ageDays, ageDays >= profile.quitFirstAgeDays {
                decision = (
                    .quitThenCleanup,
                    item.actionKind,
                    false,
                    "\(item.owner) quit-first data is at least \(profile.quitFirstAgeDays) days old under the \(profile.label) profile.",
                    [
                        "Quit \(item.owner), rescan active handles, then use normal dry-run cleanup guidance.",
                        "Do not force-delete while the owning app or agent is running."
                    ]
                )
            } else {
                decision = (
                    .keep,
                    .reportOnly,
                    false,
                    ageReason(ageDays: ageDays, threshold: profile.quitFirstAgeDays, label: "quit-first"),
                    ["Keep until it is older or the owning app is clearly idle."]
                )
            }
        case .valuableHistory:
            if let ageDays, ageDays >= profile.historyCompressAgeDays {
                decision = (
                    .compressAfterReview,
                    .compress,
                    false,
                    "\(item.owner) history is at least \(profile.historyCompressAgeDays) days old under the \(profile.label) profile.",
                    [
                        "Review for useful provenance before compressing or archiving.",
                        "Keep recent or active project/session history unmodified."
                    ]
                )
            } else {
                decision = (
                    .keep,
                    .reportOnly,
                    false,
                    ageReason(ageDays: ageDays, threshold: profile.historyCompressAgeDays, label: "history"),
                    ["Keep this history available unless you deliberately archive it elsewhere."]
                )
            }
        case .protectedState:
            decision = (
                .protect,
                .reportOnly,
                false,
                "Protected agent state is not a retention cleanup candidate.",
                ["Do not remove unless you are intentionally resetting credentials, config, memories, profiles, or model state."]
            )
        case .manualReview, .unknown:
            if let ageDays, ageDays >= profile.manualReviewAgeDays {
                decision = (
                    .manualReview,
                    .openGuidance,
                    false,
                    "\(item.owner) review-only data is at least \(profile.manualReviewAgeDays) days old under the \(profile.label) profile.",
                    ["Open in Finder or Terminal and confirm it is not unique work before moving anything."]
                )
            } else {
                decision = (
                    .keep,
                    .reportOnly,
                    false,
                    ageReason(ageDays: ageDays, threshold: profile.manualReviewAgeDays, label: "review-only"),
                    ["Keep or inspect manually; Ryddi does not have enough evidence for automated retention."]
                )
            }
        }

        return AgentRetentionRecommendation(
            id: item.id,
            owner: item.owner,
            bucket: item.bucket,
            path: item.path,
            displayName: item.displayName,
            allocatedSize: item.allocatedSize,
            ageDays: ageDays,
            recommendation: decision.0,
            actionKind: decision.1,
            eligibleForCleanupPlan: decision.2,
            reason: decision.3,
            nextSteps: decision.4
        )
    }

    private static func summaries(from rows: [AgentRetentionRecommendation]) -> [AgentRetentionSummary] {
        let grouped = Dictionary(grouping: rows, by: \.recommendation)
        return AgentRetentionRecommendationKind.allCases.compactMap { recommendation in
            guard let items = grouped[recommendation], !items.isEmpty else { return nil }
            return AgentRetentionSummary(
                recommendation: recommendation,
                count: items.count,
                bytes: items.reduce(0) { $0 + $1.allocatedSize }
            )
        }
    }

    private static func sortRecommendations(_ lhs: AgentRetentionRecommendation, _ rhs: AgentRetentionRecommendation) -> Bool {
        let lhsRank = rank(lhs.recommendation)
        let rhsRank = rank(rhs.recommendation)
        if lhsRank == rhsRank {
            if lhs.allocatedSize == rhs.allocatedSize {
                return lhs.path < rhs.path
            }
            return lhs.allocatedSize > rhs.allocatedSize
        }
        return lhsRank < rhsRank
    }

    private static func rank(_ recommendation: AgentRetentionRecommendationKind) -> Int {
        switch recommendation {
        case .cleanupPlan: 0
        case .quitThenCleanup: 1
        case .compressAfterReview: 2
        case .manualReview: 3
        case .keep: 4
        case .protect: 5
        }
    }

    private static func ageInDays(from date: Date, referenceDate: Date) -> Int {
        let seconds = referenceDate.timeIntervalSince(date)
        guard seconds >= 0 else { return 0 }
        return Int(seconds / (24 * 60 * 60))
    }

    private static func ageReason(ageDays: Int?, threshold: Int, label: String) -> String {
        guard let ageDays else {
            return "Age is unknown; \(label) retention needs a known modification date before profile guidance."
        }
        return "Age \(ageDays) day(s) is below the \(threshold)-day \(label) retention threshold."
    }
}
