import Foundation

public struct BucketSummary: Codable, Hashable, Identifiable, Sendable {
    public var id: String { name }
    public let name: String
    public let count: Int
    public let logicalSize: Int64
    public let allocatedSize: Int64

    public init(name: String, count: Int, logicalSize: Int64, allocatedSize: Int64) {
        self.name = name
        self.count = count
        self.logicalSize = logicalSize
        self.allocatedSize = allocatedSize
    }
}

public struct ScopeAccessSummary: Codable, Hashable, Identifiable, Sendable {
    public var id: String { path }
    public let name: String
    public let path: String
    public let permissionState: PermissionState
    public let message: String
    public let operation: ScopeAccessOperation?
    public let errorCode: Int?
    public let detail: String?

    public init(
        name: String,
        path: String,
        permissionState: PermissionState,
        message: String,
        operation: ScopeAccessOperation? = nil,
        errorCode: Int? = nil,
        detail: String? = nil
    ) {
        self.name = name
        self.path = path
        self.permissionState = permissionState
        self.message = message
        self.operation = operation
        self.errorCode = errorCode
        self.detail = detail
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case path
        case permissionState
        case message
        case operation
        case errorCode
        case detail
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        path = try container.decode(String.self, forKey: .path)
        permissionState = try container.decode(PermissionState.self, forKey: .permissionState)
        message = try container.decode(String.self, forKey: .message)
        operation = try container.decodeIfPresent(ScopeAccessOperation.self, forKey: .operation)
        errorCode = try container.decodeIfPresent(Int.self, forKey: .errorCode)
        detail = try container.decodeIfPresent(String.self, forKey: .detail)
    }
}

public struct DiskMapNode: Codable, Hashable, Identifiable, Sendable {
    public var id: String { "\(group):\(name)" }
    public let group: String
    public let name: String
    public let allocatedSize: Int64
    public let logicalSize: Int64
    public let count: Int
    public let safetyClass: SafetyClass?
    public let actionKind: ActionKind?
    public let isReclaimable: Bool

    public init(
        group: String,
        name: String,
        allocatedSize: Int64,
        logicalSize: Int64,
        count: Int,
        safetyClass: SafetyClass?,
        actionKind: ActionKind?,
        isReclaimable: Bool
    ) {
        self.group = group
        self.name = name
        self.allocatedSize = allocatedSize
        self.logicalSize = logicalSize
        self.count = count
        self.safetyClass = safetyClass
        self.actionKind = actionKind
        self.isReclaimable = isReclaimable
    }
}

public struct OwnerStorageSummary: Codable, Hashable, Identifiable, Sendable {
    public var id: String { ownerName }
    public let ownerName: String
    public let count: Int
    public let logicalSize: Int64
    public let allocatedSize: Int64
    public let expectedAutoSafeBytes: Int64
    public let reviewBytes: Int64
    public let protectedBytes: Int64
    public let dominantCategory: String
    public let safetyClass: SafetyClass?
    public let actionKind: ActionKind?
    public let isReclaimable: Bool
    public let topPaths: [String]

    public init(
        ownerName: String,
        count: Int,
        logicalSize: Int64,
        allocatedSize: Int64,
        expectedAutoSafeBytes: Int64,
        reviewBytes: Int64,
        protectedBytes: Int64,
        dominantCategory: String,
        safetyClass: SafetyClass?,
        actionKind: ActionKind?,
        isReclaimable: Bool,
        topPaths: [String]
    ) {
        self.ownerName = ownerName
        self.count = count
        self.logicalSize = logicalSize
        self.allocatedSize = allocatedSize
        self.expectedAutoSafeBytes = expectedAutoSafeBytes
        self.reviewBytes = reviewBytes
        self.protectedBytes = protectedBytes
        self.dominantCategory = dominantCategory
        self.safetyClass = safetyClass
        self.actionKind = actionKind
        self.isReclaimable = isReclaimable
        self.topPaths = topPaths
    }
}

public enum TopOffenderSort: String, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    case allocated
    case logical
    case reclaim
    case age
    case risk
    case category
    case safety
    case scope
    case owner
    case action

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .allocated: "Allocated"
        case .logical: "Logical"
        case .reclaim: "Reclaim"
        case .age: "Age"
        case .risk: "Risk"
        case .category: "Category"
        case .safety: "Safety"
        case .scope: "Scope"
        case .owner: "Owner"
        case .action: "Action"
        }
    }

    public static func parse(_ rawValue: String) -> TopOffenderSort? {
        switch rawValue {
        case "size", "allocated":
            .allocated
        default:
            TopOffenderSort(rawValue: rawValue)
        }
    }
}

public enum TopOffenderGroup: String, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    case none
    case category
    case safety
    case owner
    case scope
    case action

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .none: "No grouping"
        case .category: "Category"
        case .safety: "Safety"
        case .owner: "Owner"
        case .scope: "Scope"
        case .action: "Action"
        }
    }
}

public enum TopOffenderConfidence: String, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    case high
    case conditional
    case review
    case protected
    case blocked

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .high: "High"
        case .conditional: "Conditional"
        case .review: "Review"
        case .protected: "Protected"
        case .blocked: "Blocked"
        }
    }

    public var rank: Int {
        switch self {
        case .high: 0
        case .conditional: 1
        case .review: 2
        case .protected: 3
        case .blocked: 4
        }
    }
}

public enum ReviewNextAction: String, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    case safeMaintenance
    case quitAppFirst
    case useNativeTool
    case reviewInFinder
    case archiveCandidate
    case protectByDefault
    case doNotTouch

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .safeMaintenance: "Safe maintenance"
        case .quitAppFirst: "Quit app first"
        case .useNativeTool: "Use native tool"
        case .reviewInFinder: "Review in Finder"
        case .archiveCandidate: "Archive candidate"
        case .protectByDefault: "Protect by default"
        case .doNotTouch: "Do not touch"
        }
    }

    public var guidance: String {
        switch self {
        case .safeMaintenance:
            "Include this in a dry-run plan, then execute only after the receipt is clean."
        case .quitAppFirst:
            "Quit the owning app or tool, then re-run the active-file check."
        case .useNativeTool:
            "Use the package manager, simulator, container, or vendor tool instead of raw deletion."
        case .reviewInFinder:
            "Open the item in Finder and decide whether it is still valuable."
        case .archiveCandidate:
            "Consider archiving or moving this out of primary storage after review."
        case .protectByDefault:
            "Keep it unless you explicitly know it is disposable."
        case .doNotTouch:
            "Ryddi should not remove this automatically."
        }
    }
}

public extension Finding {
    var reviewNextAction: ReviewNextAction {
        if openFileStatus?.isOpen == true || openFileStatus?.checkFailed != nil {
            return .quitAppFirst
        }
        if safetyClass == .neverTouch {
            return .doNotTouch
        }
        if safetyClass == .preserveByDefault {
            return .protectByDefault
        }
        if actionKind == .nativeToolCommand {
            return .useNativeTool
        }
        if safetyClass == .autoSafe, actionKind == .deleteCache || actionKind == .trash {
            return .safeMaintenance
        }
        if actionKind == .compress || primaryCategory.localizedCaseInsensitiveContains("large") {
            return .archiveCandidate
        }
        if safetyClass == .reviewRequired {
            return .archiveCandidate
        }
        return .reviewInFinder
    }
}

public struct TopOffenderRow: Codable, Hashable, Identifiable, Sendable {
    public var id: String { finding.id }
    public let finding: Finding
    public let path: String
    public let displayName: String
    public let scopeName: String
    public let category: String
    public let ownerName: String
    public let safetyClass: SafetyClass
    public let actionKind: ActionKind
    public let logicalSize: Int64
    public let allocatedSize: Int64
    public let estimatedImmediateReclaim: Int64
    public let ageDays: Int?
    public let confidence: TopOffenderConfidence
    public let reclaimabilityLabel: String
    public let evidenceSummary: String
    public let nextAction: ReviewNextAction

    public init(finding: Finding, referenceDate: Date = Date()) {
        self.finding = finding
        path = finding.path
        displayName = finding.displayName
        scopeName = finding.scopeName
        category = finding.primaryCategory
        ownerName = TopOffenderRow.ownerName(for: finding)
        safetyClass = finding.safetyClass
        actionKind = finding.actionKind
        logicalSize = finding.logicalSize
        allocatedSize = finding.allocatedSize
        ageDays = finding.ageInDays(referenceDate: referenceDate)
        estimatedImmediateReclaim = TopOffenderRow.estimatedImmediateReclaim(for: finding)
        confidence = TopOffenderRow.confidence(for: finding, estimatedImmediateReclaim: estimatedImmediateReclaim)
        reclaimabilityLabel = TopOffenderRow.reclaimabilityLabel(
            for: finding,
            estimatedImmediateReclaim: estimatedImmediateReclaim,
            confidence: confidence
        )
        evidenceSummary = TopOffenderRow.evidenceSummary(for: finding)
        nextAction = finding.reviewNextAction
    }

    private static func estimatedImmediateReclaim(for finding: Finding) -> Int64 {
        if finding.openFileStatus?.isOpen == true || finding.openFileStatus?.checkFailed != nil {
            return 0
        }
        guard finding.safetyClass == .autoSafe else { return 0 }
        guard [.deleteCache, .trash].contains(finding.actionKind) else { return 0 }
        return finding.allocatedSize
    }

    private static func confidence(for finding: Finding, estimatedImmediateReclaim: Int64) -> TopOffenderConfidence {
        if finding.openFileStatus?.isOpen == true || finding.openFileStatus?.checkFailed != nil {
            return .blocked
        }
        if estimatedImmediateReclaim > 0 {
            return .high
        }
        switch finding.safetyClass {
        case .autoSafe, .safeAfterCondition:
            return .conditional
        case .reviewRequired:
            return .review
        case .preserveByDefault, .neverTouch:
            return .protected
        }
    }

    private static func reclaimabilityLabel(
        for finding: Finding,
        estimatedImmediateReclaim: Int64,
        confidence: TopOffenderConfidence
    ) -> String {
        if confidence == .blocked {
            if finding.openFileStatus?.isOpen == true {
                return "Quit app first"
            }
            return "Open check failed"
        }
        if estimatedImmediateReclaim > 0 {
            return "Can reclaim"
        }
        if finding.actionKind == .nativeToolCommand {
            return "Use native tool"
        }
        if finding.safetyClass == .reviewRequired {
            return "Review"
        }
        if [.preserveByDefault, .neverTouch].contains(finding.safetyClass) {
            return "Keep"
        }
        return "Conditional"
    }

    private static func ownerName(for finding: Finding) -> String {
        if let ownerHint = finding.ownerHint?.trimmingCharacters(in: .whitespacesAndNewlines), !ownerHint.isEmpty {
            return ownerHint
        }
        let category = finding.primaryCategory.trimmingCharacters(in: .whitespacesAndNewlines)
        if !category.isEmpty && category != "Unknown" {
            return category
        }
        let scopeName = finding.scopeName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !scopeName.isEmpty {
            return scopeName
        }
        return "Unknown"
    }

    private static func evidenceSummary(for finding: Finding) -> String {
        if let match = finding.ruleMatches.first {
            if let evidence = match.evidence.first, !evidence.isEmpty {
                return "\(match.title): \(evidence)"
            }
            return match.title
        }
        if let evidence = finding.evidence.first {
            return evidence.message
        }
        return "No rule evidence recorded."
    }
}

public struct TopOffenderGroupSection: Codable, Hashable, Identifiable, Sendable {
    public var id: String { "\(group.rawValue):\(key)" }
    public let group: TopOffenderGroup
    public let key: String
    public let title: String
    public let count: Int
    public let logicalSize: Int64
    public let allocatedSize: Int64
    public let estimatedImmediateReclaim: Int64
    public let rows: [TopOffenderRow]

    public init(group: TopOffenderGroup, key: String, title: String, rows: [TopOffenderRow]) {
        self.group = group
        self.key = key
        self.title = title
        self.count = rows.count
        self.logicalSize = rows.reduce(0) { $0 + $1.logicalSize }
        self.allocatedSize = rows.reduce(0) { $0 + $1.allocatedSize }
        self.estimatedImmediateReclaim = rows.reduce(0) { $0 + $1.estimatedImmediateReclaim }
        self.rows = rows
    }
}

public struct TopOffenderTable: Codable, Hashable, Sendable {
    public let generatedAt: Date
    public let sort: TopOffenderSort
    public let group: TopOffenderGroup
    public let limit: Int
    public let rowCount: Int
    public let logicalSize: Int64
    public let allocatedSize: Int64
    public let estimatedImmediateReclaim: Int64
    public let rows: [TopOffenderRow]
    public let sections: [TopOffenderGroupSection]
    public let nonClaims: [String]

    public init(
        generatedAt: Date,
        sort: TopOffenderSort,
        group: TopOffenderGroup,
        limit: Int,
        rows: [TopOffenderRow],
        sections: [TopOffenderGroupSection],
        nonClaims: [String] = TopOffenderTable.defaultNonClaims
    ) {
        self.generatedAt = generatedAt
        self.sort = sort
        self.group = group
        self.limit = limit
        self.rowCount = rows.count
        self.logicalSize = rows.reduce(0) { $0 + $1.logicalSize }
        self.allocatedSize = rows.reduce(0) { $0 + $1.allocatedSize }
        self.estimatedImmediateReclaim = rows.reduce(0) { $0 + $1.estimatedImmediateReclaim }
        self.rows = rows
        self.sections = sections
        self.nonClaims = nonClaims
    }

    public static let defaultNonClaims = [
        "Top offender rows use non-overlapping scan findings to avoid known parent/child double-counting.",
        "Estimated immediate reclaim only counts auto-safe trash/cache actions and is still subject to final open-file, permission, Trash, APFS, and snapshot behavior.",
        "Protected, history, app state, document, VM/container, and native-tool-managed data can be large without being counted as immediate reclaim."
    ]

    public static func empty(generatedAt: Date = Date()) -> TopOffenderTable {
        TopOffenderTable(
            generatedAt: generatedAt,
            sort: .allocated,
            group: .none,
            limit: 0,
            rows: [],
            sections: []
        )
    }
}

public protocol CleanupFlowPrioritizable {
    var cleanupFlowStage: CleanupFlowStage { get }
    var actionPriority: Int { get }
}

public enum ReviewQueueID: String, Codable, CaseIterable, Hashable, Identifiable, Sendable,
    CleanupFlowPrioritizable
{
    case safeMaintenance
    case quitAppFirst
    case useNativeTool
    case valuableHistory
    case personalAppAssets
    case unknown

    public var id: String { rawValue }

    public var cleanupFlowStage: CleanupFlowStage {
        switch self {
        case .safeMaintenance:
            .safeCleanup
        case .quitAppFirst, .useNativeTool:
            .needsAction
        case .valuableHistory, .personalAppAssets, .unknown:
            .keepOrInspect
        }
    }

    public var actionPriority: Int {
        switch self {
        case .safeMaintenance: 600
        case .quitAppFirst: 500
        case .useNativeTool: 400
        case .unknown: 300
        case .valuableHistory: 200
        case .personalAppAssets: 100
        }
    }

    public var title: String {
        switch self {
        case .safeMaintenance: "Safe Maintenance"
        case .quitAppFirst: "Quit App First"
        case .useNativeTool: "Use Native Tool"
        case .valuableHistory: "Valuable History"
        case .personalAppAssets: "Personal/App Assets"
        case .unknown: "Unknown"
        }
    }

    public var guidance: String {
        switch self {
        case .safeMaintenance:
            "Auto-safe cache/temp candidates that can enter a dry-run plan after open-file and permission checks."
        case .quitAppFirst:
            "Likely rebuildable data that is active, condition-gated, or needs an owner app to quit before cleanup."
        case .useNativeTool:
            "Container, VM, package-manager, or tool-owned state that should be handled by native cleanup commands."
        case .valuableHistory:
            "Sessions, transcripts, archives, and provenance that may be worth compressing or preserving."
        case .personalAppAssets:
            "Creative, media, browser profile, app state, credential, config, and other protected user/app assets."
        case .unknown:
            "Unmatched, ambiguous, large, old, or review-only findings that need manual inspection."
        }
    }

    public static func parse(_ rawValue: String) -> ReviewQueueID? {
        let normalized = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: " ", with: "-")
        switch normalized {
        case "safe", "safe-maintenance", "maintenance", "auto-safe":
            return .safeMaintenance
        case "quit", "quit-app", "quit-app-first", "app-first":
            return .quitAppFirst
        case "native", "native-tool", "use-native-tool":
            return .useNativeTool
        case "history", "valuable-history":
            return .valuableHistory
        case "assets", "personal-assets", "app-assets", "personal-app-assets":
            return .personalAppAssets
        case "unknown", "review", "manual":
            return .unknown
        default:
            return ReviewQueueID(rawValue: rawValue)
        }
    }
}

public enum CleanupFlowStage: String, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    case safeCleanup
    case needsAction
    case keepOrInspect

    public var id: String { rawValue }

    public var sortPriority: Int {
        switch self {
        case .safeCleanup: 0
        case .needsAction: 1
        case .keepOrInspect: 2
        }
    }

    public var title: String {
        switch self {
        case .safeCleanup: "Safe cleanup"
        case .needsAction: "Needs your action"
        case .keepOrInspect: "Keep or inspect"
        }
    }

    public var guidance: String {
        switch self {
        case .safeCleanup:
            "Rebuildable data that can enter a checked dry-run plan."
        case .needsAction:
            "Quit an app or use the owning tool before reclaiming storage."
        case .keepOrInspect:
            "History, personal data, and unknown storage stay outside cleanup plans."
        }
    }
}

public struct ReviewQueueSummary: Codable, Hashable, Identifiable, Sendable {
    public var id: String { queueID.rawValue }
    public let queueID: ReviewQueueID
    public let title: String
    public let guidance: String
    public let count: Int
    public let logicalSize: Int64
    public let allocatedSize: Int64
    public let estimatedImmediateReclaim: Int64
    public let highestRiskClass: SafetyClass?
    public let dominantCategory: String
    public let dominantAction: ActionKind?
    public let rows: [TopOffenderRow]

    public init(queueID: ReviewQueueID, rows: [TopOffenderRow], accountingRows: [TopOffenderRow]? = nil) {
        let accountingRows = accountingRows ?? rows
        self.queueID = queueID
        title = queueID.title
        guidance = queueID.guidance
        count = accountingRows.count
        logicalSize = accountingRows.reduce(0) { $0 + $1.logicalSize }
        allocatedSize = accountingRows.reduce(0) { $0 + $1.allocatedSize }
        estimatedImmediateReclaim = accountingRows.reduce(0) { $0 + $1.estimatedImmediateReclaim }
        highestRiskClass = accountingRows.map(\.safetyClass).max { $0.riskRank < $1.riskRank }
        dominantCategory = ReviewQueueSummary.dominantCategory(in: accountingRows)
        dominantAction = accountingRows.map(\.actionKind)
            .reduce(into: [:]) { counts, action in counts[action, default: 0] += 1 }
            .sorted {
                if $0.value == $1.value {
                    return $0.key.label < $1.key.label
                }
                return $0.value > $1.value
            }
            .first?.key
        self.rows = rows
    }

    private static func dominantCategory(in rows: [TopOffenderRow]) -> String {
        let counts = rows.reduce(into: [String: (count: Int, allocatedSize: Int64)]()) { partial, row in
            let current = partial[row.category] ?? (0, 0)
            partial[row.category] = (current.count + 1, current.allocatedSize + row.allocatedSize)
        }
        return counts.sorted {
            if $0.value.allocatedSize == $1.value.allocatedSize {
                if $0.value.count == $1.value.count {
                    return $0.key < $1.key
                }
                return $0.value.count > $1.value.count
            }
            return $0.value.allocatedSize > $1.value.allocatedSize
        }
        .first?.key ?? "None"
    }
}

public struct ReviewQueueReport: Codable, Hashable, Sendable {
    public let generatedAt: Date
    public let totalCount: Int
    public let totalLogicalSize: Int64
    public let totalAllocatedSize: Int64
    public let estimatedImmediateReclaim: Int64
    public let queues: [ReviewQueueSummary]
    public let nonClaims: [String]

    public init(
        generatedAt: Date,
        queues: [ReviewQueueSummary],
        nonClaims: [String] = ReviewQueueReport.defaultNonClaims
    ) {
        self.generatedAt = generatedAt
        self.queues = queues
        totalCount = queues.reduce(0) { $0 + $1.count }
        totalLogicalSize = queues.reduce(0) { $0 + $1.logicalSize }
        totalAllocatedSize = queues.reduce(0) { $0 + $1.allocatedSize }
        estimatedImmediateReclaim = queues.reduce(0) { $0 + $1.estimatedImmediateReclaim }
        self.nonClaims = nonClaims
    }

    public static let defaultNonClaims = [
        "Review queues organize existing findings by user intent; they do not grant cleanup permission or bypass safety classes.",
        "Queue reclaim estimates only count auto-safe trash/cache actions and remain subject to dry-run, open-file, permission, Trash, APFS, and snapshot behavior.",
        "Native-tool, valuable-history, personal/app-asset, unknown, and protected findings remain review-first unless a separate explicit plan says otherwise."
    ]

    public static func empty(generatedAt: Date = Date()) -> ReviewQueueReport {
        ReviewQueueReport(
            generatedAt: generatedAt,
            queues: ReviewQueueID.allCases.map { ReviewQueueSummary(queueID: $0, rows: []) }
        )
    }

    public func detailReport(for queueID: ReviewQueueID, limit: Int) -> ReviewQueueDetailReport {
        let queue = queues.first { $0.queueID == queueID }
            ?? ReviewQueueSummary(queueID: queueID, rows: [])
        return ReviewQueueDetailReport(
            generatedAt: generatedAt,
            queue: queue,
            limit: limit
        )
    }
}

public struct ReviewQueueDetailReport: Codable, Hashable, Sendable {
    public let generatedAt: Date
    public let queueID: ReviewQueueID
    public let title: String
    public let guidance: String
    public let count: Int
    public let rowCount: Int
    public let limit: Int
    public let logicalSize: Int64
    public let allocatedSize: Int64
    public let estimatedImmediateReclaim: Int64
    public let highestRiskClass: SafetyClass?
    public let dominantCategory: String
    public let dominantAction: ActionKind?
    public let rows: [TopOffenderRow]
    public let nonClaims: [String]

    public init(
        generatedAt: Date,
        queue: ReviewQueueSummary,
        limit: Int,
        nonClaims: [String] = ReviewQueueReport.defaultNonClaims
    ) {
        self.generatedAt = generatedAt
        queueID = queue.queueID
        title = queue.title
        guidance = queue.guidance
        count = queue.count
        let visibleRows = queue.rows.prefix(max(0, limit)).map { $0 }
        rowCount = visibleRows.count
        self.limit = limit
        logicalSize = queue.logicalSize
        allocatedSize = queue.allocatedSize
        estimatedImmediateReclaim = queue.estimatedImmediateReclaim
        highestRiskClass = queue.highestRiskClass
        dominantCategory = queue.dominantCategory
        dominantAction = queue.dominantAction
        rows = visibleRows
        self.nonClaims = nonClaims
    }
}

public enum LargeOldReviewMode: String, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    case all
    case large
    case old

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .all: "Large & Old"
        case .large: "Large"
        case .old: "Old"
        }
    }
}

public enum LargeOldReviewKind: String, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    case large
    case old
    case largeAndOld

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .large: "Large"
        case .old: "Old"
        case .largeAndOld: "Large and Old"
        }
    }
}

public struct LargeOldReviewRow: Codable, Hashable, Identifiable, Sendable {
    public var id: String { row.id }
    public let row: TopOffenderRow
    public let kind: LargeOldReviewKind
    public let path: String
    public let displayName: String
    public let scopeName: String
    public let category: String
    public let ownerName: String
    public let safetyClass: SafetyClass
    public let actionKind: ActionKind
    public let logicalSize: Int64
    public let allocatedSize: Int64
    public let ageDays: Int?
    public let reviewReason: String

    public init(row: TopOffenderRow, kind: LargeOldReviewKind) {
        self.row = row
        self.kind = kind
        path = row.path
        displayName = row.displayName
        scopeName = row.scopeName
        category = row.category
        ownerName = row.ownerName
        safetyClass = row.safetyClass
        actionKind = row.actionKind
        logicalSize = row.logicalSize
        allocatedSize = row.allocatedSize
        ageDays = row.ageDays
        reviewReason = LargeOldReviewRow.reason(for: row, kind: kind)
    }

    private static func reason(for row: TopOffenderRow, kind: LargeOldReviewKind) -> String {
        let age = row.ageDays.map { ", \($0) days old" } ?? ""
        switch kind {
        case .large:
            return "Large item\(age); inspect before archiving or moving to Trash."
        case .old:
            return "Old item\(age); age is a review signal, not cleanup permission."
        case .largeAndOld:
            return "Large and old item\(age); review value, ownership, and recovery path first."
        }
    }
}

public struct LargeOldReviewReport: Codable, Hashable, Sendable {
    public let generatedAt: Date
    public let mode: LargeOldReviewMode
    public let limit: Int
    public let totalCount: Int
    public let largeCount: Int
    public let oldCount: Int
    public let largeAndOldCount: Int
    public let totalLogicalSize: Int64
    public let totalAllocatedSize: Int64
    public let reviewRequiredBytes: Int64
    public let protectedBytes: Int64
    public let estimatedImmediateReclaim: Int64
    public let kindSummaries: [BucketSummary]
    public let categorySummaries: [BucketSummary]
    public let safetySummaries: [BucketSummary]
    public let rows: [LargeOldReviewRow]
    public let nonClaims: [String]

    public init(
        generatedAt: Date,
        mode: LargeOldReviewMode,
        limit: Int,
        rows: [LargeOldReviewRow],
        accountingRows: [LargeOldReviewRow]? = nil,
        nonClaims: [String] = LargeOldReviewReport.defaultNonClaims
    ) {
        let accountingRows = accountingRows ?? rows
        self.generatedAt = generatedAt
        self.mode = mode
        self.limit = limit
        totalCount = accountingRows.count
        largeCount = accountingRows.filter { [.large, .largeAndOld].contains($0.kind) }.count
        oldCount = accountingRows.filter { [.old, .largeAndOld].contains($0.kind) }.count
        largeAndOldCount = accountingRows.filter { $0.kind == .largeAndOld }.count
        totalLogicalSize = accountingRows.reduce(0) { $0 + $1.logicalSize }
        totalAllocatedSize = accountingRows.reduce(0) { $0 + $1.allocatedSize }
        reviewRequiredBytes = accountingRows
            .filter { [.safeAfterCondition, .reviewRequired].contains($0.safetyClass) }
            .reduce(0) { $0 + $1.allocatedSize }
        protectedBytes = accountingRows
            .filter { [.preserveByDefault, .neverTouch].contains($0.safetyClass) }
            .reduce(0) { $0 + $1.allocatedSize }
        estimatedImmediateReclaim = accountingRows.reduce(0) { $0 + $1.row.estimatedImmediateReclaim }
        kindSummaries = LargeOldReviewReport.bucket(accountingRows, by: { $0.kind.label })
        categorySummaries = LargeOldReviewReport.bucket(accountingRows, by: { $0.category })
        safetySummaries = LargeOldReviewReport.bucket(accountingRows, by: { $0.safetyClass.label })
        self.rows = rows
        self.nonClaims = nonClaims
    }

    public static let defaultNonClaims = [
        "Large and old review signals do not grant cleanup permission or bypass safety classes.",
        "These rows are review surfaces for Finder, Quick Look, archiving, or explicit Trash decisions; Ryddi does not auto-select them for cleanup.",
        "Allocated bytes shown here are not promised immediate free space because APFS clones, snapshots, purgeable data, permissions, and Trash behavior can change the result."
    ]

    private static func bucket(
        _ rows: [LargeOldReviewRow],
        by key: (LargeOldReviewRow) -> String
    ) -> [BucketSummary] {
        let grouped = Dictionary(grouping: rows, by: key)
        return grouped.map { name, items in
            BucketSummary(
                name: name,
                count: items.count,
                logicalSize: items.reduce(0) { $0 + $1.logicalSize },
                allocatedSize: items.reduce(0) { $0 + $1.allocatedSize }
            )
        }
        .sorted {
            if $0.allocatedSize == $1.allocatedSize {
                return $0.name < $1.name
            }
            return $0.allocatedSize > $1.allocatedSize
        }
    }
}

public struct ScanOverview: Codable, Hashable, Sendable {
    public let generatedAt: Date
    public let findingCount: Int
    public let totalLogicalSize: Int64
    public let totalAllocatedSize: Int64
    public let expectedAutoSafeBytes: Int64
    public let reviewBytes: Int64
    public let protectedBytes: Int64
    public let safetySummaries: [BucketSummary]
    public let categorySummaries: [BucketSummary]
    public let scopeSizeSummaries: [BucketSummary]
    public let scopeSummaries: [ScopeAccessSummary]
    public let mapNodes: [DiskMapNode]
    public let ownerSummaries: [OwnerStorageSummary]
    public let topFindings: [Finding]
    public let topOffenderTable: TopOffenderTable
    public let accountingNotes: [String]
    public let scanCoverage: ScanCoverage?

    public init(
        generatedAt: Date,
        findingCount: Int,
        totalLogicalSize: Int64,
        totalAllocatedSize: Int64,
        expectedAutoSafeBytes: Int64,
        reviewBytes: Int64,
        protectedBytes: Int64,
        safetySummaries: [BucketSummary],
        categorySummaries: [BucketSummary],
        scopeSizeSummaries: [BucketSummary],
        scopeSummaries: [ScopeAccessSummary],
        mapNodes: [DiskMapNode],
        ownerSummaries: [OwnerStorageSummary],
        topFindings: [Finding],
        topOffenderTable: TopOffenderTable? = nil,
        accountingNotes: [String],
        scanCoverage: ScanCoverage? = nil
    ) {
        self.generatedAt = generatedAt
        self.findingCount = findingCount
        self.totalLogicalSize = totalLogicalSize
        self.totalAllocatedSize = totalAllocatedSize
        self.expectedAutoSafeBytes = expectedAutoSafeBytes
        self.reviewBytes = reviewBytes
        self.protectedBytes = protectedBytes
        self.safetySummaries = safetySummaries
        self.categorySummaries = categorySummaries
        self.scopeSizeSummaries = scopeSizeSummaries
        self.scopeSummaries = scopeSummaries
        self.mapNodes = mapNodes
        self.ownerSummaries = ownerSummaries
        self.topFindings = topFindings
        self.topOffenderTable = topOffenderTable ?? TopOffenderTable.empty(generatedAt: generatedAt)
        self.accountingNotes = accountingNotes
        self.scanCoverage = scanCoverage
    }
}

public extension ScanOverview {
    func withScanCoverage(_ coverage: ScanCoverage) -> ScanOverview {
        ScanOverview(
            generatedAt: generatedAt,
            findingCount: findingCount,
            totalLogicalSize: totalLogicalSize,
            totalAllocatedSize: totalAllocatedSize,
            expectedAutoSafeBytes: expectedAutoSafeBytes,
            reviewBytes: reviewBytes,
            protectedBytes: protectedBytes,
            safetySummaries: safetySummaries,
            categorySummaries: categorySummaries,
            scopeSizeSummaries: scopeSizeSummaries,
            scopeSummaries: scopeSummaries,
            mapNodes: mapNodes,
            ownerSummaries: ownerSummaries,
            topFindings: topFindings,
            topOffenderTable: topOffenderTable,
            accountingNotes: accountingNotes,
            scanCoverage: coverage
        )
    }
}

public enum GrowthGroup: String, Codable, CaseIterable, Hashable, Sendable {
    case category
    case scope
    case safety

    public var label: String {
        switch self {
        case .category: "Category"
        case .scope: "Scope"
        case .safety: "Safety"
        }
    }
}

public struct ScanSnapshot: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let createdAt: Date
    public let findingCount: Int
    public let totalLogicalSize: Int64
    public let totalAllocatedSize: Int64
    public let expectedAutoSafeBytes: Int64
    public let reviewBytes: Int64
    public let protectedBytes: Int64
    public let categorySummaries: [BucketSummary]
    public let safetySummaries: [BucketSummary]
    public let scopeBuckets: [BucketSummary]
    public let scopeSummaries: [ScopeAccessSummary]
    public let topFindingPaths: [String]

    public init(
        id: String = UUID().uuidString,
        createdAt: Date,
        findingCount: Int,
        totalLogicalSize: Int64,
        totalAllocatedSize: Int64,
        expectedAutoSafeBytes: Int64,
        reviewBytes: Int64,
        protectedBytes: Int64,
        categorySummaries: [BucketSummary],
        safetySummaries: [BucketSummary],
        scopeBuckets: [BucketSummary],
        scopeSummaries: [ScopeAccessSummary],
        topFindingPaths: [String]
    ) {
        self.id = id
        self.createdAt = createdAt
        self.findingCount = findingCount
        self.totalLogicalSize = totalLogicalSize
        self.totalAllocatedSize = totalAllocatedSize
        self.expectedAutoSafeBytes = expectedAutoSafeBytes
        self.reviewBytes = reviewBytes
        self.protectedBytes = protectedBytes
        self.categorySummaries = categorySummaries
        self.safetySummaries = safetySummaries
        self.scopeBuckets = scopeBuckets
        self.scopeSummaries = scopeSummaries
        self.topFindingPaths = topFindingPaths
    }
}

public struct BucketGrowthDelta: Codable, Hashable, Identifiable, Sendable {
    public var id: String { name }
    public let name: String
    public let previousAllocatedSize: Int64
    public let currentAllocatedSize: Int64
    public let deltaAllocatedSize: Int64
    public let previousCount: Int
    public let currentCount: Int

    public init(
        name: String,
        previousAllocatedSize: Int64,
        currentAllocatedSize: Int64,
        previousCount: Int,
        currentCount: Int
    ) {
        self.name = name
        self.previousAllocatedSize = previousAllocatedSize
        self.currentAllocatedSize = currentAllocatedSize
        self.deltaAllocatedSize = currentAllocatedSize - previousAllocatedSize
        self.previousCount = previousCount
        self.currentCount = currentCount
    }
}

public enum FindingAnalytics {
    public static func overview(
        findings: [Finding],
        scopes: [ScanScope],
        topLimit: Int = 20,
        offenderSort: TopOffenderSort = .allocated,
        offenderGroup: TopOffenderGroup = .none,
        now: Date = Date(),
        fileManager: FileManager = .default,
        scopeAccessSummaries: [ScopeAccessSummary]? = nil,
        scopeAccessProbe: (any ScopeAccessProbing)? = nil
    ) -> ScanOverview {
        let accountingFindings = nonOverlappingFindings(findings)
        let totalLogical = accountingFindings.reduce(0) { $0 + $1.logicalSize }
        let totalAllocated = accountingFindings.reduce(0) { $0 + $1.allocatedSize }
        let autoSafe = accountingFindings
            .filter { $0.safetyClass == .autoSafe }
            .reduce(0) { $0 + $1.allocatedSize }
        let review = accountingFindings
            .filter { [.safeAfterCondition, .reviewRequired].contains($0.safetyClass) }
            .reduce(0) { $0 + $1.allocatedSize }
        let protected = accountingFindings
            .filter { [.preserveByDefault, .neverTouch].contains($0.safetyClass) }
            .reduce(0) { $0 + $1.allocatedSize }
        let offenderTable = topOffenderTable(
            findings: findings,
            sort: offenderSort,
            group: offenderGroup,
            limit: topLimit,
            now: now
        )

        return ScanOverview(
            generatedAt: now,
            findingCount: findings.count,
            totalLogicalSize: totalLogical,
            totalAllocatedSize: totalAllocated,
            expectedAutoSafeBytes: autoSafe,
            reviewBytes: review,
            protectedBytes: protected,
            safetySummaries: bucket(accountingFindings, by: { $0.safetyClass.label }),
            categorySummaries: bucket(accountingFindings, by: { $0.primaryCategory }),
            scopeSizeSummaries: bucket(accountingFindings, by: { $0.scopeName }),
            scopeSummaries: scopeAccessSummaries ?? PermissionAdvisor.report(
                scopes: scopes,
                now: now,
                fileManager: fileManager,
                probe: scopeAccessProbe
            ).scopeSummaries,
            mapNodes: mapNodes(from: accountingFindings),
            ownerSummaries: ownerSummaries(from: ownerAttributionFindings(findings)),
            topFindings: offenderTable.rows.map(\.finding),
            topOffenderTable: offenderTable,
            accountingNotes: accountingNotes(logicalSize: totalLogical, allocatedSize: totalAllocated)
        )
    }

    public static func topOffenderTable(
        findings: [Finding],
        sort: TopOffenderSort = .allocated,
        group: TopOffenderGroup = .none,
        limit: Int = 25,
        now: Date = Date()
    ) -> TopOffenderTable {
        let rows = nonOverlappingFindings(findings).map { TopOffenderRow(finding: $0, referenceDate: now) }
        let sortedRows = rows.sorted { lhs, rhs in
            compareTopOffenderRows(lhs, rhs, sort: sort)
        }
        let limitedRows = Array(sortedRows.prefix(max(0, limit)))
        return TopOffenderTable(
            generatedAt: now,
            sort: sort,
            group: group,
            limit: limit,
            rows: limitedRows,
            sections: topOffenderSections(from: limitedRows, group: group)
        )
    }

    public static func reviewQueueReport(
        findings: [Finding],
        limitPerQueue: Int = 10,
        now: Date = Date()
    ) -> ReviewQueueReport {
        let rows = nonOverlappingFindings(findings).map { TopOffenderRow(finding: $0, referenceDate: now) }
        let grouped = Dictionary(grouping: rows) { row in
            reviewQueueID(for: row)
        }
        let summaries = ReviewQueueID.allCases.map { queueID in
            let allRows = (grouped[queueID] ?? [])
                .sorted { lhs, rhs in
                    compareTopOffenderRows(lhs, rhs, sort: .allocated)
                }
            let displayRows = allRows.prefix(max(0, limitPerQueue)).map { $0 }
            return ReviewQueueSummary(queueID: queueID, rows: displayRows, accountingRows: allRows)
        }
        return ReviewQueueReport(generatedAt: now, queues: summaries)
    }

    public static func reviewQueueRows(
        findings: [Finding],
        queueID: ReviewQueueID,
        limit: Int = Int.max,
        now: Date = Date()
    ) -> [TopOffenderRow] {
        nonOverlappingFindings(findings)
            .map { TopOffenderRow(finding: $0, referenceDate: now) }
            .filter { reviewQueueID(for: $0) == queueID }
            .sorted { lhs, rhs in
                compareTopOffenderRows(lhs, rhs, sort: .allocated)
            }
            .prefix(max(0, limit))
            .map { $0 }
    }

    public static func reviewQueueDetailReport(
        findings: [Finding],
        queueID: ReviewQueueID,
        limit: Int = 80,
        now: Date = Date()
    ) -> ReviewQueueDetailReport {
        let allRows = reviewQueueRows(findings: findings, queueID: queueID, limit: Int.max, now: now)
        let displayRows = allRows.prefix(max(0, limit)).map { $0 }
        let summary = ReviewQueueSummary(queueID: queueID, rows: displayRows, accountingRows: allRows)
        return ReviewQueueDetailReport(generatedAt: now, queue: summary, limit: limit)
    }

    public static func largeOldReviewReport(
        findings: [Finding],
        mode: LargeOldReviewMode = .all,
        sort: TopOffenderSort = .allocated,
        limit: Int = 25,
        now: Date = Date()
    ) -> LargeOldReviewReport {
        let allRows = largeOldReviewFindings(findings)
            .map { TopOffenderRow(finding: $0, referenceDate: now) }
            .compactMap { row -> LargeOldReviewRow? in
                guard let kind = largeOldReviewKind(for: row) else { return nil }
                guard largeOldReviewMode(mode, contains: kind) else { return nil }
                return LargeOldReviewRow(row: row, kind: kind)
            }
            .sorted { lhs, rhs in
                compareLargeOldRows(lhs, rhs, sort: sort)
            }
        let displayRows = allRows.prefix(max(0, limit)).map { $0 }
        return LargeOldReviewReport(
            generatedAt: now,
            mode: mode,
            limit: limit,
            rows: displayRows,
            accountingRows: allRows
        )
    }

    public static func ownerSummaries(from findings: [Finding], limit: Int = 18) -> [OwnerStorageSummary] {
        let grouped = Dictionary(grouping: findings) { finding in
            ownerName(for: finding)
        }
        return grouped.map { ownerName, items in
            let allocated = items.reduce(0) { $0 + $1.allocatedSize }
            let logical = items.reduce(0) { $0 + $1.logicalSize }
            let autoSafe = items
                .filter { $0.safetyClass == .autoSafe }
                .reduce(0) { $0 + $1.allocatedSize }
            let review = items
                .filter { [.safeAfterCondition, .reviewRequired].contains($0.safetyClass) }
                .reduce(0) { $0 + $1.allocatedSize }
            let protected = items
                .filter { [.preserveByDefault, .neverTouch].contains($0.safetyClass) }
                .reduce(0) { $0 + $1.allocatedSize }
            let dominant = dominantFinding(in: items)
            let reclaimable = items.contains {
                $0.safetyClass == .autoSafe && [.deleteCache, .trash].contains($0.actionKind)
            }
            return OwnerStorageSummary(
                ownerName: ownerName,
                count: items.count,
                logicalSize: logical,
                allocatedSize: allocated,
                expectedAutoSafeBytes: autoSafe,
                reviewBytes: review,
                protectedBytes: protected,
                dominantCategory: dominantCategory(in: items),
                safetyClass: dominant?.safetyClass,
                actionKind: dominant?.actionKind,
                isReclaimable: reclaimable,
                topPaths: items.sorted(by: sortByAllocatedThenPath).prefix(3).map(\.path)
            )
        }
        .sorted {
            if $0.allocatedSize == $1.allocatedSize {
                return $0.ownerName < $1.ownerName
            }
            return $0.allocatedSize > $1.allocatedSize
        }
        .prefix(limit)
        .map { $0 }
    }

    public static func mapNodes(from findings: [Finding], limit: Int = 18) -> [DiskMapNode] {
        let grouped = Dictionary(grouping: findings) { finding in
            finding.primaryCategory
        }
        return grouped.map { category, items in
            let allocated = items.reduce(0) { $0 + $1.allocatedSize }
            let logical = items.reduce(0) { $0 + $1.logicalSize }
            let dominant = dominantFinding(in: items)
            let reclaimable = items.contains {
                $0.safetyClass == .autoSafe && [.deleteCache, .trash].contains($0.actionKind)
            }
            return DiskMapNode(
                group: "category",
                name: category,
                allocatedSize: allocated,
                logicalSize: logical,
                count: items.count,
                safetyClass: dominant?.safetyClass,
                actionKind: dominant?.actionKind,
                isReclaimable: reclaimable
            )
        }
        .sorted {
            if $0.allocatedSize == $1.allocatedSize {
                return $0.name < $1.name
            }
            return $0.allocatedSize > $1.allocatedSize
        }
        .prefix(limit)
        .map { $0 }
    }

    public static func snapshot(from overview: ScanOverview, id: String = UUID().uuidString) -> ScanSnapshot {
        ScanSnapshot(
            id: id,
            createdAt: overview.generatedAt,
            findingCount: overview.findingCount,
            totalLogicalSize: overview.totalLogicalSize,
            totalAllocatedSize: overview.totalAllocatedSize,
            expectedAutoSafeBytes: overview.expectedAutoSafeBytes,
            reviewBytes: overview.reviewBytes,
            protectedBytes: overview.protectedBytes,
            categorySummaries: overview.categorySummaries,
            safetySummaries: overview.safetySummaries,
            scopeBuckets: overview.scopeSizeSummaries,
            scopeSummaries: overview.scopeSummaries,
            topFindingPaths: overview.topFindings.map(\.path)
        )
    }

    public static func growthDeltas(
        previous: ScanSnapshot,
        current: ScanSnapshot,
        group: GrowthGroup = .category
    ) -> [BucketGrowthDelta] {
        let previousBuckets = buckets(in: previous, group: group)
        let currentBuckets = buckets(in: current, group: group)
        let names = Set(previousBuckets.map(\.name)).union(currentBuckets.map(\.name))
        return names.map { name in
            let previousBucket = previousBuckets.first { $0.name == name }
            let currentBucket = currentBuckets.first { $0.name == name }
            return BucketGrowthDelta(
                name: name,
                previousAllocatedSize: previousBucket?.allocatedSize ?? 0,
                currentAllocatedSize: currentBucket?.allocatedSize ?? 0,
                previousCount: previousBucket?.count ?? 0,
                currentCount: currentBucket?.count ?? 0
            )
        }
        .sorted {
            let leftMagnitude = abs($0.deltaAllocatedSize)
            let rightMagnitude = abs($1.deltaAllocatedSize)
            if leftMagnitude == rightMagnitude {
                return $0.name < $1.name
            }
            return leftMagnitude > rightMagnitude
        }
    }

    private static func buckets(in snapshot: ScanSnapshot, group: GrowthGroup) -> [BucketSummary] {
        switch group {
        case .category: snapshot.categorySummaries
        case .scope: snapshot.scopeBuckets
        case .safety: snapshot.safetySummaries
        }
    }

    private static func bucket(_ findings: [Finding], by key: (Finding) -> String) -> [BucketSummary] {
        let grouped = Dictionary(grouping: findings, by: key)
        return grouped.map { name, items in
            BucketSummary(
                name: name,
                count: items.count,
                logicalSize: items.reduce(0) { $0 + $1.logicalSize },
                allocatedSize: items.reduce(0) { $0 + $1.allocatedSize }
            )
        }
        .sorted {
            if $0.allocatedSize == $1.allocatedSize {
                return $0.name < $1.name
            }
            return $0.allocatedSize > $1.allocatedSize
        }
    }

    private static func ownerName(for finding: Finding) -> String {
        if let ownerHint = finding.ownerHint?.trimmingCharacters(in: .whitespacesAndNewlines), !ownerHint.isEmpty {
            return ownerHint
        }
        let category = finding.primaryCategory.trimmingCharacters(in: .whitespacesAndNewlines)
        if !category.isEmpty && category != "Unknown" {
            return category
        }
        let scopeName = finding.scopeName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !scopeName.isEmpty {
            return scopeName
        }
        return "Unknown"
    }

    private static func dominantFinding(in findings: [Finding]) -> Finding? {
        findings.sorted(by: sortByAllocatedThenPath).first
    }

    private static func dominantCategory(in findings: [Finding]) -> String {
        let categories = bucket(findings, by: { $0.primaryCategory })
        return categories.first?.name ?? "Unknown"
    }

    private static func reviewQueueID(for row: TopOffenderRow) -> ReviewQueueID {
        if row.actionKind == .nativeToolCommand {
            return .useNativeTool
        }
        if row.finding.openFileStatus?.isOpen == true || row.finding.openFileStatus?.checkFailed != nil {
            if [.autoSafe, .safeAfterCondition].contains(row.safetyClass) {
                return .quitAppFirst
            }
        }
        if row.safetyClass == .autoSafe {
            return .safeMaintenance
        }
        if row.safetyClass == .safeAfterCondition {
            return .quitAppFirst
        }
        if row.safetyClass == .preserveByDefault, isValuableHistory(row) {
            return .valuableHistory
        }
        if [.preserveByDefault, .neverTouch].contains(row.safetyClass) {
            return .personalAppAssets
        }
        return .unknown
    }

    private static func isValuableHistory(_ row: TopOffenderRow) -> Bool {
        let haystack = [
            row.category,
            row.ownerName,
            row.displayName,
            row.path,
            row.evidenceSummary
        ]
        .joined(separator: " ")
        .lowercased()
        let historyNeedles = [
            "history",
            "session",
            "sessions",
            "transcript",
            "archive",
            "archives",
            "conversation",
            "provenance",
            "rollout"
        ]
        return historyNeedles.contains { haystack.contains($0) }
    }

    private static func largeOldReviewKind(for row: TopOffenderRow) -> LargeOldReviewKind? {
        let isLarge = hasLargeOldSignal(row.finding, ruleID: "dynamic.large-item.review")
        let isOld = hasLargeOldSignal(row.finding, ruleID: "dynamic.old-item.review")
        switch (isLarge, isOld) {
        case (true, true): return .largeAndOld
        case (true, false): return .large
        case (false, true): return .old
        case (false, false): return nil
        }
    }

    private static func hasLargeOldSignal(_ finding: Finding, ruleID: String? = nil) -> Bool {
        finding.ruleMatches.contains { match in
            if let ruleID {
                return match.ruleID == ruleID
            }
            return match.ruleID == "dynamic.large-item.review" || match.ruleID == "dynamic.old-item.review"
        }
    }

    private static func largeOldReviewMode(_ mode: LargeOldReviewMode, contains kind: LargeOldReviewKind) -> Bool {
        switch mode {
        case .all:
            return true
        case .large:
            return [.large, .largeAndOld].contains(kind)
        case .old:
            return [.old, .largeAndOld].contains(kind)
        }
    }

    private static func compareLargeOldRows(
        _ lhs: LargeOldReviewRow,
        _ rhs: LargeOldReviewRow,
        sort: TopOffenderSort
    ) -> Bool {
        switch sort {
        case .age:
            let leftAge = lhs.ageDays ?? -1
            let rightAge = rhs.ageDays ?? -1
            if leftAge == rightAge {
                return compareTopOffenderRows(lhs.row, rhs.row, sort: .allocated)
            }
            return leftAge > rightAge
        case .category:
            if lhs.category == rhs.category {
                return compareTopOffenderRows(lhs.row, rhs.row, sort: .allocated)
            }
            return lhs.category < rhs.category
        case .owner:
            if lhs.ownerName == rhs.ownerName {
                return compareTopOffenderRows(lhs.row, rhs.row, sort: .allocated)
            }
            return lhs.ownerName < rhs.ownerName
        case .safety:
            if lhs.safetyClass == rhs.safetyClass {
                return compareTopOffenderRows(lhs.row, rhs.row, sort: .allocated)
            }
            return lhs.safetyClass.riskRank < rhs.safetyClass.riskRank
        case .logical:
            return compareTopOffenderRows(lhs.row, rhs.row, sort: .logical)
        default:
            return compareTopOffenderRows(lhs.row, rhs.row, sort: .allocated)
        }
    }

    private static func topOffenderSections(
        from rows: [TopOffenderRow],
        group: TopOffenderGroup
    ) -> [TopOffenderGroupSection] {
        guard group != .none else { return [] }
        let grouped = Dictionary(grouping: rows) { row in
            topOffenderGroupKey(row, group: group)
        }
        return grouped.map { key, groupRows in
            TopOffenderGroupSection(
                group: group,
                key: key,
                title: topOffenderGroupTitle(key, group: group),
                rows: groupRows.sorted { lhs, rhs in
                    compareTopOffenderRows(lhs, rhs, sort: .allocated)
                }
            )
        }
        .sorted {
            if $0.allocatedSize == $1.allocatedSize {
                return $0.title < $1.title
            }
            return $0.allocatedSize > $1.allocatedSize
        }
    }

    private static func topOffenderGroupKey(_ row: TopOffenderRow, group: TopOffenderGroup) -> String {
        switch group {
        case .none: "all"
        case .category: row.category
        case .safety: row.safetyClass.rawValue
        case .owner: row.ownerName
        case .scope: row.scopeName
        case .action: row.actionKind.rawValue
        }
    }

    private static func topOffenderGroupTitle(_ key: String, group: TopOffenderGroup) -> String {
        switch group {
        case .none:
            return "All"
        case .safety:
            return SafetyClass(rawValue: key)?.label ?? key
        case .action:
            return ActionKind(rawValue: key)?.label ?? key
        default:
            return key
        }
    }

    private static func compareTopOffenderRows(
        _ lhs: TopOffenderRow,
        _ rhs: TopOffenderRow,
        sort: TopOffenderSort
    ) -> Bool {
        switch sort {
        case .allocated:
            return compareNumeric(lhs.allocatedSize, rhs.allocatedSize, lhs.path, rhs.path)
        case .logical:
            return compareNumeric(lhs.logicalSize, rhs.logicalSize, lhs.path, rhs.path)
        case .reclaim:
            if lhs.estimatedImmediateReclaim == rhs.estimatedImmediateReclaim {
                return compareNumeric(lhs.allocatedSize, rhs.allocatedSize, lhs.path, rhs.path)
            }
            return lhs.estimatedImmediateReclaim > rhs.estimatedImmediateReclaim
        case .age:
            return compareNumeric(Int64(lhs.ageDays ?? -1), Int64(rhs.ageDays ?? -1), lhs.path, rhs.path)
        case .risk:
            if lhs.safetyClass.riskRank == rhs.safetyClass.riskRank {
                return compareNumeric(lhs.allocatedSize, rhs.allocatedSize, lhs.path, rhs.path)
            }
            return lhs.safetyClass.riskRank < rhs.safetyClass.riskRank
        case .category:
            return compareText(lhs.category, rhs.category, lhs.allocatedSize, rhs.allocatedSize, lhs.path, rhs.path)
        case .safety:
            if lhs.safetyClass.riskRank == rhs.safetyClass.riskRank {
                return compareNumeric(lhs.allocatedSize, rhs.allocatedSize, lhs.path, rhs.path)
            }
            return lhs.safetyClass.riskRank < rhs.safetyClass.riskRank
        case .scope:
            return compareText(lhs.scopeName, rhs.scopeName, lhs.allocatedSize, rhs.allocatedSize, lhs.path, rhs.path)
        case .owner:
            return compareText(lhs.ownerName, rhs.ownerName, lhs.allocatedSize, rhs.allocatedSize, lhs.path, rhs.path)
        case .action:
            return compareText(lhs.actionKind.label, rhs.actionKind.label, lhs.allocatedSize, rhs.allocatedSize, lhs.path, rhs.path)
        }
    }

    private static func compareText(
        _ lhsText: String,
        _ rhsText: String,
        _ lhsSize: Int64,
        _ rhsSize: Int64,
        _ lhsPath: String,
        _ rhsPath: String
    ) -> Bool {
        if lhsText == rhsText {
            return compareNumeric(lhsSize, rhsSize, lhsPath, rhsPath)
        }
        return lhsText.localizedCaseInsensitiveCompare(rhsText) == .orderedAscending
    }

    private static func compareNumeric(_ lhsValue: Int64, _ rhsValue: Int64, _ lhsPath: String, _ rhsPath: String) -> Bool {
        if lhsValue == rhsValue {
            return lhsPath < rhsPath
        }
        return lhsValue > rhsValue
    }

    private static func accountingNotes(logicalSize: Int64, allocatedSize: Int64) -> [String] {
        var notes = [
            "Ryddi reports allocated size for reclaim estimates because APFS physical usage is closer to what can be freed than Finder-style logical size."
        ]
        if allocatedSize != logicalSize {
            notes.append("Logical and allocated totals differ; APFS clones, hard links, compression, sparse files, local snapshots, and purgeable storage can make free-space gains differ from item size.")
        }
        notes.append("VM/container disks and native tool stores are reported for review; Ryddi does not raw-delete them automatically.")
        return notes
    }

    private static func sortByAllocatedThenPath(_ lhs: Finding, _ rhs: Finding) -> Bool {
        if lhs.allocatedSize == rhs.allocatedSize {
            return lhs.path < rhs.path
        }
        return lhs.allocatedSize > rhs.allocatedSize
    }

    private static func nonOverlappingFindings(_ findings: [Finding]) -> [Finding] {
        let nonRoot = findings.filter { finding in
            !finding.evidence.contains { $0.kind == "scope" }
        }
        let candidates = nonRoot.isEmpty ? findings : nonRoot
        let ordered = candidates.sorted { lhs, rhs in
            let lhsDepth = URL(fileURLWithPath: lhs.path).standardizedFileURL.pathComponents.count
            let rhsDepth = URL(fileURLWithPath: rhs.path).standardizedFileURL.pathComponents.count
            if lhsDepth == rhsDepth {
                return lhs.path < rhs.path
            }
            return lhsDepth < rhsDepth
        }
        var selected: [Finding] = []
        var selectedPaths = Set<String>()
        for finding in ordered {
            let path = URL(fileURLWithPath: finding.path).standardizedFileURL.path
            guard !hasSelectedAncestor(of: path, in: selectedPaths) else { continue }
            selected.append(finding)
            selectedPaths.insert(path)
        }
        return selected
    }

    private static func hasSelectedAncestor(of path: String, in selectedPaths: Set<String>) -> Bool {
        var ancestor = URL(fileURLWithPath: path).deletingLastPathComponent().standardizedFileURL.path
        while ancestor != path {
            if selectedPaths.contains(ancestor) {
                return true
            }
            guard ancestor != "/" else { return false }
            let parent = URL(fileURLWithPath: ancestor).deletingLastPathComponent().standardizedFileURL.path
            guard parent != ancestor else { return false }
            ancestor = parent
        }
        return false
    }

    private static func largeOldReviewFindings(_ findings: [Finding]) -> [Finding] {
        let nonRoot = findings.filter { finding in
            !finding.evidence.contains { $0.kind == "scope" }
        }
        let candidates = (nonRoot.isEmpty ? findings : nonRoot)
            .filter { hasLargeOldSignal($0) }
        let ordered = candidates.sorted { lhs, rhs in
            let lhsDepth = URL(fileURLWithPath: lhs.path).standardizedFileURL.pathComponents.count
            let rhsDepth = URL(fileURLWithPath: rhs.path).standardizedFileURL.pathComponents.count
            if lhsDepth == rhsDepth {
                return lhs.path < rhs.path
            }
            return lhsDepth < rhsDepth
        }
        var selected: [Finding] = []
        var selectedPaths: [String] = []
        for finding in ordered {
            let path = URL(fileURLWithPath: finding.path).standardizedFileURL.path
            guard !selectedPaths.contains(where: { isDescendant(path, of: $0) }) else { continue }
            if finding.isDirectory && hasLargeOldDescendant(of: path, in: candidates) {
                continue
            }
            selected.append(finding)
            selectedPaths.append(path)
        }
        return selected
    }

    private static func hasLargeOldDescendant(of path: String, in candidates: [Finding]) -> Bool {
        candidates.contains { candidate in
            isDescendant(URL(fileURLWithPath: candidate.path).standardizedFileURL.path, of: path)
        }
    }

    private static func ownerAttributionFindings(_ findings: [Finding]) -> [Finding] {
        let nonRoot = findings.filter { finding in
            !finding.evidence.contains { $0.kind == "scope" }
        }
        let candidates = nonRoot.isEmpty ? findings : nonRoot
        let ordered = candidates.sorted { lhs, rhs in
            let lhsDepth = URL(fileURLWithPath: lhs.path).standardizedFileURL.pathComponents.count
            let rhsDepth = URL(fileURLWithPath: rhs.path).standardizedFileURL.pathComponents.count
            if lhsDepth == rhsDepth {
                return lhs.path < rhs.path
            }
            return lhsDepth < rhsDepth
        }
        var selected: [Finding] = []
        var selectedPaths: [String] = []
        for finding in ordered {
            let path = URL(fileURLWithPath: finding.path).standardizedFileURL.path
            guard !selectedPaths.contains(where: { isDescendant(path, of: $0) }) else { continue }
            if !isOwnerAttributable(finding) && hasOwnerAttributableDescendant(of: path, in: candidates) {
                continue
            }
            selected.append(finding)
            selectedPaths.append(path)
        }
        return selected
    }

    private static func isOwnerAttributable(_ finding: Finding) -> Bool {
        if let ownerHint = finding.ownerHint?.trimmingCharacters(in: .whitespacesAndNewlines), !ownerHint.isEmpty {
            return true
        }
        return !finding.ruleMatches.isEmpty
    }

    private static func hasOwnerAttributableDescendant(of path: String, in findings: [Finding]) -> Bool {
        findings.contains { other in
            let otherPath = URL(fileURLWithPath: other.path).standardizedFileURL.path
            return isDescendant(otherPath, of: path) && isOwnerAttributable(other)
        }
    }

    private static func isDescendant(_ path: String, of ancestor: String) -> Bool {
        guard path != ancestor else { return false }
        let ancestorWithSlash = ancestor.hasSuffix("/") ? ancestor : ancestor + "/"
        return path.hasPrefix(ancestorWithSlash)
    }
}
