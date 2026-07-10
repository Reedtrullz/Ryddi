import Foundation

public enum RecoveryState: String, Codable, CaseIterable, Hashable, Sendable {
    case restorableFromHolding
    case trashReview
    case notRecoverableByRyddi
    case dryRunOnly
    case skippedNoChange
    case guidanceOnly
    case manualReview

    public var label: String {
        switch self {
        case .restorableFromHolding: "Holding item review"
        case .trashReview: "Review Trash"
        case .notRecoverableByRyddi: "Not recoverable by Ryddi"
        case .dryRunOnly: "Dry run only"
        case .skippedNoChange: "Skipped or failed"
        case .guidanceOnly: "Guidance only"
        case .manualReview: "Manual review"
        }
    }
}

public struct RecoveryCenterItem: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let state: RecoveryState
    public let title: String
    public let originalPath: String?
    public let currentPath: String?
    public let receiptID: String?
    public let receiptCreatedAt: Date?
    public let receiptMode: String?
    public let actionKind: ActionKind?
    public let actionStatus: String?
    public let message: String
    public let bytes: Int64
    public let holdingID: String?
    public let canRestoreWithRyddi: Bool
    public let guidance: [String]

    public init(
        id: String,
        state: RecoveryState,
        title: String,
        originalPath: String?,
        currentPath: String?,
        receiptID: String?,
        receiptCreatedAt: Date?,
        receiptMode: String?,
        actionKind: ActionKind?,
        actionStatus: String?,
        message: String,
        bytes: Int64,
        holdingID: String?,
        canRestoreWithRyddi: Bool,
        guidance: [String]
    ) {
        self.id = id
        self.state = state
        self.title = title
        self.originalPath = originalPath
        self.currentPath = currentPath
        self.receiptID = receiptID
        self.receiptCreatedAt = receiptCreatedAt
        self.receiptMode = receiptMode
        self.actionKind = actionKind
        self.actionStatus = actionStatus
        self.message = message
        self.bytes = bytes
        self.holdingID = holdingID
        self.canRestoreWithRyddi = canRestoreWithRyddi
        self.guidance = guidance
    }
}

public struct RecoveryStateSummary: Codable, Hashable, Identifiable, Sendable {
    public var id: RecoveryState { state }
    public let state: RecoveryState
    public let count: Int
    public let bytes: Int64

    public init(state: RecoveryState, count: Int, bytes: Int64) {
        self.state = state
        self.count = count
        self.bytes = bytes
    }
}

public struct RecoveryCenterReport: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let generatedAt: Date
    public let itemCount: Int
    public let restorableCount: Int
    public let restorableBytes: Int64
    public let stateSummaries: [RecoveryStateSummary]
    public let items: [RecoveryCenterItem]
    public let nonClaims: [String]

    public init(
        id: String = UUID().uuidString,
        generatedAt: Date = Date(),
        itemCount: Int,
        restorableCount: Int,
        restorableBytes: Int64,
        stateSummaries: [RecoveryStateSummary],
        items: [RecoveryCenterItem],
        nonClaims: [String]
    ) {
        self.id = id
        self.generatedAt = generatedAt
        self.itemCount = itemCount
        self.restorableCount = restorableCount
        self.restorableBytes = restorableBytes
        self.stateSummaries = stateSummaries
        self.items = items
        self.nonClaims = nonClaims
    }
}

public enum RecoveryCenter {
    public static func build(
        heldItems: [HeldItem] = HoldingStore().list(),
        receipts: [ExecutionReceipt] = AuditStore().recentReceipts(limit: 50),
        limit: Int = 100,
        generatedAt: Date = Date()
    ) -> RecoveryCenterReport {
        var items = heldItems.map(heldItem)
        let heldOriginalPaths = Set(heldItems.compactMap(\.originalPath))

        for receipt in receipts {
            for (index, action) in receipt.actions.enumerated() {
                items.append(receiptItem(
                    receipt: receipt,
                    action: action,
                    index: index,
                    heldOriginalPaths: heldOriginalPaths
                ))
            }
        }

        let sorted = items
            .sorted { lhs, rhs in
                if lhs.state == .restorableFromHolding, rhs.state != .restorableFromHolding {
                    return true
                }
                if lhs.state != .restorableFromHolding, rhs.state == .restorableFromHolding {
                    return false
                }
                return (lhs.receiptCreatedAt ?? .distantPast) > (rhs.receiptCreatedAt ?? .distantPast)
            }
            .prefix(limit)

        let limited = Array(sorted)
        let summaries = RecoveryState.allCases.compactMap { state -> RecoveryStateSummary? in
            let matching = limited.filter { $0.state == state }
            guard !matching.isEmpty else { return nil }
            return RecoveryStateSummary(
                state: state,
                count: matching.count,
                bytes: matching.reduce(0) { $0 + $1.bytes }
            )
        }
        let restorable = limited.filter(\.canRestoreWithRyddi)
        return RecoveryCenterReport(
            generatedAt: generatedAt,
            itemCount: limited.count,
            restorableCount: restorable.count,
            restorableBytes: restorable.reduce(0) { $0 + $1.bytes },
            stateSummaries: summaries,
            items: limited,
            nonClaims: [
                "Holding-area records require manual Finder recovery; Ryddi does not restore, move, or delete them automatically.",
                "Trash actions require Finder Trash review; Ryddi cannot prove an item is still in Trash or restore it from Trash.",
                "Homebrew cleanup and external manual cleanup may require rebuilding caches, using the owning tool, or restoring from backups.",
                "Dry-run, skipped, and error actions did not prove a filesystem mutation."
            ]
        )
    }

    private static func heldItem(_ item: HeldItem) -> RecoveryCenterItem {
        RecoveryCenterItem(
            id: "holding:\(item.id)",
            state: .manualReview,
            title: item.displayName,
            originalPath: item.originalPath,
            currentPath: item.heldPath,
            receiptID: nil,
            receiptCreatedAt: item.heldAt,
            receiptMode: nil,
            actionKind: .quarantineHold,
            actionStatus: "held",
            message: "Item is currently in Ryddi's holding area for manual Finder recovery.",
            bytes: item.allocatedSize,
            holdingID: item.id,
            canRestoreWithRyddi: false,
            guidance: [
                "Reveal the held item in Finder and move it manually after review.",
                "Do not overwrite an existing destination."
            ]
        )
    }

    private static func receiptItem(
        receipt: ExecutionReceipt,
        action: ExecutionActionReceipt,
        index: Int,
        heldOriginalPaths: Set<String>
    ) -> RecoveryCenterItem {
        let state = stateFor(receipt: receipt, action: action, heldOriginalPaths: heldOriginalPaths)
        return RecoveryCenterItem(
            id: "receipt:\(receipt.id):\(index)",
            state: state,
            title: URL(fileURLWithPath: action.path).lastPathComponent,
            originalPath: action.path,
            currentPath: nil,
            receiptID: receipt.id,
            receiptCreatedAt: receipt.createdAt,
            receiptMode: receipt.mode,
            actionKind: action.action,
            actionStatus: action.status,
            message: action.message,
            bytes: action.reclaimedBytes,
            holdingID: nil,
            canRestoreWithRyddi: false,
            guidance: guidanceFor(state: state, action: action)
        )
    }

    private static func stateFor(
        receipt: ExecutionReceipt,
        action: ExecutionActionReceipt,
        heldOriginalPaths: Set<String>
    ) -> RecoveryState {
        if receipt.mode == ExecutionMode.dryRun.rawValue || action.status == "dry-run" {
            return .dryRunOnly
        }
        if action.status == "skipped" || action.status == "error" {
            return .skippedNoChange
        }
        guard action.status == "done" else {
            return .manualReview
        }
        switch action.action {
        case .quarantineHold:
            return .manualReview
        case .trash:
            return .trashReview
        case .deleteCache:
            return .notRecoverableByRyddi
        case .compress:
            return .manualReview
        case .nativeToolCommand, .openGuidance, .reportOnly:
            return .guidanceOnly
        }
    }

    private static func guidanceFor(state: RecoveryState, action: ExecutionActionReceipt) -> [String] {
        switch state {
        case .restorableFromHolding:
            return ["Use Ryddi restore for the held item."]
        case .trashReview:
            return [
                "Open Finder Trash and review the item manually.",
                "Ryddi cannot prove the Trash still contains this item."
            ]
        case .notRecoverableByRyddi:
            return [
                "Ryddi has no app-managed copy of this item.",
                "If needed, rebuild the cache with the owning app/tool or restore from backup."
            ]
        case .dryRunOnly:
            return ["Dry-run actions are plan evidence only; no recovery action is needed."]
        case .skippedNoChange:
            return ["Skipped or failed actions should not have completed a cleanup mutation."]
        case .guidanceOnly:
            return ["Review the owning native tool or guidance receipt for next steps."]
        case .manualReview:
            if action.action == .quarantineHold {
                return ["If the item is still held, use the restorable holding item row rather than this receipt row."]
            }
            if action.action == .compress {
                return ["Compression keeps recovery manual; review the original path and generated compressed file."]
            }
            return ["Review this receipt action manually."]
        }
    }
}
