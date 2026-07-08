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

public enum ScanScopePreset: String, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    case developer
    case general
    case all

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .developer: "Developer"
        case .general: "General Mac"
        case .all: "All"
        }
    }

    public var summary: String {
        switch self {
        case .developer:
            "Developer and AI-agent storage such as Codex, containers, Xcode, package caches, IDE caches, browser caches, and build temp data."
        case .general:
            "General Mac cleanup review roots such as Downloads, Desktop, documents/media review, user caches, logs, app support, attachments, backups, and Trash."
        case .all:
            "General Mac cleanup roots plus developer and AI-agent storage, with overlapping child scopes collapsed to avoid double-counting."
        }
    }
}

public struct ScanScopePlan: Codable, Hashable, Sendable {
    public let preset: ScanScopePreset?
    public let label: String
    public let summary: String
    public let scopes: [ScanScope]
    public let nonClaims: [String]

    public init(
        preset: ScanScopePreset?,
        label: String,
        summary: String,
        scopes: [ScanScope],
        nonClaims: [String]
    ) {
        self.preset = preset
        self.label = label
        self.summary = summary
        self.scopes = scopes
        self.nonClaims = nonClaims
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

public struct RuleGateEvidence: Codable, Hashable, Sendable {
    public let minimumAgeDays: Int?
    public let retentionPolicy: String?
    public let retentionDays: Int?
    public let nativeToolName: String?
    public let nativePreviewAvailable: Bool

    public init(
        minimumAgeDays: Int? = nil,
        retentionPolicy: String? = nil,
        retentionDays: Int? = nil,
        nativeToolName: String? = nil,
        nativePreviewAvailable: Bool = false
    ) {
        self.minimumAgeDays = minimumAgeDays
        self.retentionPolicy = retentionPolicy
        self.retentionDays = retentionDays
        self.nativeToolName = nativeToolName
        self.nativePreviewAvailable = nativePreviewAvailable
    }

    private enum CodingKeys: String, CodingKey {
        case minimumAgeDays
        case retentionPolicy
        case retentionDays
        case nativeToolName
        case nativePreviewAvailable
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.minimumAgeDays = try container.decodeIfPresent(Int.self, forKey: .minimumAgeDays)
        self.retentionPolicy = try container.decodeIfPresent(String.self, forKey: .retentionPolicy)
        self.retentionDays = try container.decodeIfPresent(Int.self, forKey: .retentionDays)
        self.nativeToolName = try container.decodeIfPresent(String.self, forKey: .nativeToolName)
        self.nativePreviewAvailable = try container.decodeIfPresent(Bool.self, forKey: .nativePreviewAvailable) ?? false
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
    public let conditionGates: [PlanConditionKind]
    public let gateEvidence: RuleGateEvidence
    public let recovery: String?

    public init(
        ruleID: String,
        title: String,
        category: String,
        safetyClass: SafetyClass,
        actionKind: ActionKind,
        evidence: [String],
        conditions: [String] = [],
        conditionGates: [PlanConditionKind] = [],
        gateEvidence: RuleGateEvidence = RuleGateEvidence(),
        recovery: String? = nil
    ) {
        self.ruleID = ruleID
        self.title = title
        self.category = category
        self.safetyClass = safetyClass
        self.actionKind = actionKind
        self.evidence = evidence
        self.conditions = conditions
        self.conditionGates = conditionGates
        self.gateEvidence = gateEvidence
        self.recovery = recovery
    }

    private enum CodingKeys: String, CodingKey {
        case ruleID
        case title
        case category
        case safetyClass
        case actionKind
        case evidence
        case conditions
        case conditionGates
        case gateEvidence
        case recovery
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.ruleID = try container.decode(String.self, forKey: .ruleID)
        self.title = try container.decode(String.self, forKey: .title)
        self.category = try container.decode(String.self, forKey: .category)
        self.safetyClass = try container.decode(SafetyClass.self, forKey: .safetyClass)
        self.actionKind = try container.decode(ActionKind.self, forKey: .actionKind)
        self.evidence = try container.decodeIfPresent([String].self, forKey: .evidence) ?? []
        self.conditions = try container.decodeIfPresent([String].self, forKey: .conditions) ?? []
        self.conditionGates = try container.decodeIfPresent([PlanConditionKind].self, forKey: .conditionGates) ?? []
        self.gateEvidence = try container.decodeIfPresent(RuleGateEvidence.self, forKey: .gateEvidence) ?? RuleGateEvidence()
        self.recovery = try container.decodeIfPresent(String.self, forKey: .recovery)
    }
}

public struct OpenFileStatus: Codable, Hashable, Sendable {
    public let isOpen: Bool
    public let processSummary: [String]
    public let checkedAt: Date
    public let checkFailed: String?
    public let checkedRecursively: Bool
    public let checkedPath: String?

    public init(
        isOpen: Bool,
        processSummary: [String] = [],
        checkedAt: Date = Date(),
        checkFailed: String? = nil,
        checkedRecursively: Bool = false,
        checkedPath: String? = nil
    ) {
        self.isOpen = isOpen
        self.processSummary = processSummary
        self.checkedAt = checkedAt
        self.checkFailed = checkFailed
        self.checkedRecursively = checkedRecursively
        self.checkedPath = checkedPath
    }

    private enum CodingKeys: String, CodingKey {
        case isOpen
        case processSummary
        case checkedAt
        case checkFailed
        case checkedRecursively
        case checkedPath
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.isOpen = try container.decode(Bool.self, forKey: .isOpen)
        self.processSummary = try container.decodeIfPresent([String].self, forKey: .processSummary) ?? []
        self.checkedAt = try container.decodeIfPresent(Date.self, forKey: .checkedAt) ?? Date(timeIntervalSince1970: 0)
        self.checkFailed = try container.decodeIfPresent(String.self, forKey: .checkFailed)
        self.checkedRecursively = try container.decodeIfPresent(Bool.self, forKey: .checkedRecursively) ?? false
        self.checkedPath = try container.decodeIfPresent(String.self, forKey: .checkedPath)
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

    func withOpenFileStatus(_ status: OpenFileStatus) -> Finding {
        Finding(
            id: id,
            scopeName: scopeName,
            path: path,
            displayName: displayName,
            logicalSize: logicalSize,
            allocatedSize: allocatedSize,
            isDirectory: isDirectory,
            isSymbolicLink: isSymbolicLink,
            modificationDate: modificationDate,
            ownerHint: ownerHint,
            safetyClass: safetyClass,
            actionKind: actionKind,
            ruleMatches: ruleMatches,
            evidence: evidence,
            openFileStatus: status
        )
    }
}

public enum PlanConditionKind: String, Codable, CaseIterable, Hashable, Sendable {
    case openFileClear
    case recursiveOpenFileClear
    case userPolicyClear
    case notSymbolicLink
    case manualReviewRequired
    case nativeToolRequired
    case appQuitRequired
    case minimumAgeRequired
    case finalClassificationRequired

    public var label: String {
        switch self {
        case .openFileClear: "Open-file clear"
        case .recursiveOpenFileClear: "Recursive open-file clear"
        case .userPolicyClear: "User policy clear"
        case .notSymbolicLink: "Not a symbolic link"
        case .manualReviewRequired: "Manual review required"
        case .nativeToolRequired: "Native tool required"
        case .appQuitRequired: "App quit required"
        case .minimumAgeRequired: "Minimum age required"
        case .finalClassificationRequired: "Final classification required"
        }
    }
}

public struct PlanCondition: Codable, Hashable, Sendable {
    public let kind: PlanConditionKind
    public let message: String
    public let isSatisfied: Bool

    public init(kind: PlanConditionKind = .manualReviewRequired, message: String, isSatisfied: Bool) {
        self.kind = kind
        self.message = message
        self.isSatisfied = isSatisfied
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case message
        case isSatisfied
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.kind = try container.decodeIfPresent(PlanConditionKind.self, forKey: .kind) ?? .manualReviewRequired
        self.message = try container.decode(String.self, forKey: .message)
        self.isSatisfied = try container.decode(Bool.self, forKey: .isSatisfied)
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

public enum NativeToolRisk: String, Codable, CaseIterable, Hashable, Sendable {
    case inspect
    case reclaim
    case destructive

    public var label: String {
        switch self {
        case .inspect: "Inspect"
        case .reclaim: "Reclaim"
        case .destructive: "Destructive"
        }
    }
}

public struct NativeToolCommand: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let command: String
    public let purpose: String
    public let risk: NativeToolRisk
    public let requiresReview: Bool
    public let expectedEffect: String
    public let workingDirectory: String?
    public let context: String?

    public init(
        id: String,
        command: String,
        purpose: String,
        risk: NativeToolRisk,
        requiresReview: Bool,
        expectedEffect: String,
        workingDirectory: String? = nil,
        context: String? = nil
    ) {
        self.id = id
        self.command = command
        self.purpose = purpose
        self.risk = risk
        self.requiresReview = requiresReview
        self.expectedEffect = expectedEffect
        self.workingDirectory = workingDirectory?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.context = context?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }
}

public struct NativeToolReceipt: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let generatedAt: Date
    public let findingPath: String
    public let displayName: String
    public let category: String
    public let allocatedSize: Int64
    public let safetyClass: SafetyClass
    public let actionKind: ActionKind
    public let status: String
    public let message: String
    public let commands: [NativeToolCommand]
    public let nonClaims: [String]

    public init(
        id: String = UUID().uuidString,
        generatedAt: Date = Date(),
        findingPath: String,
        displayName: String,
        category: String,
        allocatedSize: Int64,
        safetyClass: SafetyClass,
        actionKind: ActionKind,
        status: String,
        message: String,
        commands: [NativeToolCommand],
        nonClaims: [String]
    ) {
        self.id = id
        self.generatedAt = generatedAt
        self.findingPath = findingPath
        self.displayName = displayName
        self.category = category
        self.allocatedSize = allocatedSize
        self.safetyClass = safetyClass
        self.actionKind = actionKind
        self.status = status
        self.message = message
        self.commands = commands
        self.nonClaims = nonClaims
    }
}

public struct NativeToolReport: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let createdAt: Date
    public let ruleVersion: String
    public let receipts: [NativeToolReceipt]
    public let totalBytesUnderNativeReview: Int64
    public let nonClaims: [String]

    public init(
        id: String = UUID().uuidString,
        createdAt: Date = Date(),
        ruleVersion: String,
        receipts: [NativeToolReceipt],
        nonClaims: [String]
    ) {
        self.id = id
        self.createdAt = createdAt
        self.ruleVersion = ruleVersion
        self.receipts = receipts
        self.totalBytesUnderNativeReview = receipts.reduce(0) { $0 + $1.allocatedSize }
        self.nonClaims = nonClaims
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

public enum ByteFormat {
    public static func string(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
