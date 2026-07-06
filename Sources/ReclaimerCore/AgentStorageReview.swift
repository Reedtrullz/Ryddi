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
