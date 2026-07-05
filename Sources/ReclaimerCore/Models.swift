import Foundation

public enum PermissionState: String, Codable, Hashable, Sendable {
    case readable
    case missing
    case denied
    case unknown
}

public struct ScanScope: Codable, Hashable, Sendable, Identifiable {
    public var id: String { name + ":" + root.path }
    public let name: String
    public let root: URL
    public let permissionState: PermissionState

    public init(name: String, root: URL, permissionState: PermissionState = .unknown) {
        self.name = name
        self.root = root
        self.permissionState = permissionState
    }
}

public enum SafetyClass: String, Codable, CaseIterable, Hashable, Sendable {
    case autoSafe
    case safeAfterCondition
    case reviewRequired
    case preserveByDefault
    case neverTouch

    public var label: String {
        switch self {
        case .autoSafe: "Auto-safe"
        case .safeAfterCondition: "Safe after condition"
        case .reviewRequired: "Review required"
        case .preserveByDefault: "Preserve by default"
        case .neverTouch: "Never touch"
        }
    }

    public var riskRank: Int {
        switch self {
        case .autoSafe: 0
        case .safeAfterCondition: 1
        case .reviewRequired: 2
        case .preserveByDefault: 3
        case .neverTouch: 4
        }
    }
}

public enum ActionKind: String, Codable, CaseIterable, Hashable, Sendable {
    case reportOnly
    case trash
    case deleteCache
    case compress
    case quarantineHold
    case nativeToolCommand
    case openGuidance

    public var label: String {
        switch self {
        case .reportOnly: "Report only"
        case .trash: "Move to Trash"
        case .deleteCache: "Delete cache"
        case .compress: "Compress"
        case .quarantineHold: "Hold aside"
        case .nativeToolCommand: "Use native tool"
        case .openGuidance: "Open guidance"
        }
    }
}

public struct Evidence: Codable, Hashable, Sendable {
    public let kind: String
    public let message: String

    public init(kind: String, message: String) {
        self.kind = kind
        self.message = message
    }
}

public struct RuleMatch: Codable, Hashable, Sendable {
    public let ruleID: String
    public let title: String
    public let category: String
    public let safetyClass: SafetyClass
    public let actionKind: ActionKind
    public let evidence: [String]
    public let conditions: [String]
    public let recovery: String?

    public init(
        ruleID: String,
        title: String,
        category: String,
        safetyClass: SafetyClass,
        actionKind: ActionKind,
        evidence: [String],
        conditions: [String] = [],
        recovery: String? = nil
    ) {
        self.ruleID = ruleID
        self.title = title
        self.category = category
        self.safetyClass = safetyClass
        self.actionKind = actionKind
        self.evidence = evidence
        self.conditions = conditions
        self.recovery = recovery
    }
}

public struct OpenFileStatus: Codable, Hashable, Sendable {
    public let isOpen: Bool
    public let processSummary: [String]
    public let checkedAt: Date
    public let checkFailed: String?

    public init(
        isOpen: Bool,
        processSummary: [String] = [],
        checkedAt: Date = Date(),
        checkFailed: String? = nil
    ) {
        self.isOpen = isOpen
        self.processSummary = processSummary
        self.checkedAt = checkedAt
        self.checkFailed = checkFailed
    }
}

public struct Finding: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let scopeName: String
    public let path: String
    public let displayName: String
    public let logicalSize: Int64
    public let allocatedSize: Int64
    public let isDirectory: Bool
    public let isSymbolicLink: Bool
    public let modificationDate: Date?
    public let ownerHint: String?
    public let safetyClass: SafetyClass
    public let actionKind: ActionKind
    public let ruleMatches: [RuleMatch]
    public let evidence: [Evidence]
    public let openFileStatus: OpenFileStatus?

    public init(
        id: String = UUID().uuidString,
        scopeName: String,
        path: String,
        displayName: String,
        logicalSize: Int64,
        allocatedSize: Int64,
        isDirectory: Bool,
        isSymbolicLink: Bool = false,
        modificationDate: Date? = nil,
        ownerHint: String? = nil,
        safetyClass: SafetyClass,
        actionKind: ActionKind,
        ruleMatches: [RuleMatch],
        evidence: [Evidence],
        openFileStatus: OpenFileStatus? = nil
    ) {
        self.id = id
        self.scopeName = scopeName
        self.path = path
        self.displayName = displayName
        self.logicalSize = logicalSize
        self.allocatedSize = allocatedSize
        self.isDirectory = isDirectory
        self.isSymbolicLink = isSymbolicLink
        self.modificationDate = modificationDate
        self.ownerHint = ownerHint
        self.safetyClass = safetyClass
        self.actionKind = actionKind
        self.ruleMatches = ruleMatches
        self.evidence = evidence
        self.openFileStatus = openFileStatus
    }
}

public extension Finding {
    var primaryCategory: String {
        ruleMatches.first?.category ?? ownerHint ?? "Unknown"
    }

    func ageInDays(referenceDate: Date = Date()) -> Int? {
        guard let modificationDate else { return nil }
        let seconds = referenceDate.timeIntervalSince(modificationDate)
        guard seconds >= 0 else { return 0 }
        return Int(seconds / (24 * 60 * 60))
    }

    var storageAccountingNote: String {
        if allocatedSize == logicalSize {
            return "Allocated and logical size are currently the same for this item."
        }
        if allocatedSize < logicalSize {
            return "Allocated size is lower than logical size, which can happen with sparse files, compression, clones, or APFS accounting."
        }
        return "Allocated size is higher than logical size because filesystem blocks and metadata can consume extra physical space."
    }
}

public struct PlanCondition: Codable, Hashable, Sendable {
    public let message: String
    public let isSatisfied: Bool

    public init(message: String, isSatisfied: Bool) {
        self.message = message
        self.isSatisfied = isSatisfied
    }
}

public struct ReclaimPlanItem: Codable, Hashable, Identifiable, Sendable {
    public var id: String { finding.id }
    public let finding: Finding
    public let selected: Bool
    public let proposedAction: ActionKind
    public let conditions: [PlanCondition]
    public let estimatedImmediateReclaim: Int64

    public init(
        finding: Finding,
        selected: Bool,
        proposedAction: ActionKind,
        conditions: [PlanCondition],
        estimatedImmediateReclaim: Int64
    ) {
        self.finding = finding
        self.selected = selected
        self.proposedAction = proposedAction
        self.conditions = conditions
        self.estimatedImmediateReclaim = estimatedImmediateReclaim
    }
}

public struct ReclaimPlan: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let createdAt: Date
    public let mode: String
    public let items: [ReclaimPlanItem]
    public let expectedImmediateReclaim: Int64
    public let dryRunSummary: [String]

    public init(
        id: String = UUID().uuidString,
        createdAt: Date = Date(),
        mode: String,
        items: [ReclaimPlanItem],
        dryRunSummary: [String]
    ) {
        self.id = id
        self.createdAt = createdAt
        self.mode = mode
        self.items = items
        self.expectedImmediateReclaim = items.filter(\.selected).reduce(0) { $0 + $1.estimatedImmediateReclaim }
        self.dryRunSummary = dryRunSummary
    }
}

public struct ExecutionActionReceipt: Codable, Hashable, Sendable {
    public let path: String
    public let action: ActionKind
    public let status: String
    public let message: String
    public let reclaimedBytes: Int64

    public init(path: String, action: ActionKind, status: String, message: String, reclaimedBytes: Int64 = 0) {
        self.path = path
        self.action = action
        self.status = status
        self.message = message
        self.reclaimedBytes = reclaimedBytes
    }
}

public struct ExecutionReceipt: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let createdAt: Date
    public let ruleVersion: String
    public let mode: String
    public let beforeFreeBytes: Int64?
    public let afterFreeBytes: Int64?
    public let actions: [ExecutionActionReceipt]
    public let userConfirmed: Bool
    public let errors: [String]

    public init(
        id: String = UUID().uuidString,
        createdAt: Date = Date(),
        ruleVersion: String,
        mode: String,
        beforeFreeBytes: Int64?,
        afterFreeBytes: Int64?,
        actions: [ExecutionActionReceipt],
        userConfirmed: Bool,
        errors: [String] = []
    ) {
        self.id = id
        self.createdAt = createdAt
        self.ruleVersion = ruleVersion
        self.mode = mode
        self.beforeFreeBytes = beforeFreeBytes
        self.afterFreeBytes = afterFreeBytes
        self.actions = actions
        self.userConfirmed = userConfirmed
        self.errors = errors
    }
}

public enum ByteFormat {
    public static func string(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
