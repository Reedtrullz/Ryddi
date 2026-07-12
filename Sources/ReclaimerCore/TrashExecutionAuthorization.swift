import Foundation

#if canImport(Darwin)
import Darwin
#endif

public enum FileIdentityKind: String, Codable, Hashable, Sendable {
    case regularFile
    case directory
}

public struct FileIdentity: Codable, Hashable, Sendable {
    public let deviceID: UInt64
    public let fileID: UInt64
    public let kind: FileIdentityKind
    public let standardizedPath: String

    public init(deviceID: UInt64, fileID: UInt64, kind: FileIdentityKind, standardizedPath: String) {
        self.deviceID = deviceID
        self.fileID = fileID
        self.kind = kind
        self.standardizedPath = standardizedPath
    }
}

public enum FileIdentityReaderError: Error, Equatable, Sendable {
    case unreadablePath(String)
    case symbolicLink(String)
    case unsupportedFileKind(String)
}

public struct FileIdentityReader: Sendable {
    public init() {}

    public func read(at url: URL) throws -> FileIdentity {
        let standardizedURL = url.standardizedFileURL
        let path = standardizedURL.path

        #if canImport(Darwin)
        var info = Darwin.stat()
        let result: Int32 = standardizedURL.withUnsafeFileSystemRepresentation { representation in
            guard let representation else { return Int32(-1) }
            return Darwin.lstat(representation, &info)
        }
        guard result == 0 else {
            throw FileIdentityReaderError.unreadablePath(path)
        }

        let fileType = info.st_mode & S_IFMT
        let kind: FileIdentityKind
        switch fileType {
        case S_IFLNK:
            throw FileIdentityReaderError.symbolicLink(path)
        case S_IFREG:
            kind = .regularFile
        case S_IFDIR:
            kind = .directory
        default:
            throw FileIdentityReaderError.unsupportedFileKind(path)
        }

        return FileIdentity(
            deviceID: UInt64(info.st_dev),
            fileID: UInt64(info.st_ino),
            kind: kind,
            standardizedPath: path
        )
        #else
        throw FileIdentityReaderError.unreadablePath(path)
        #endif
    }
}

public struct TrashExecutionAuthorization: Codable, Hashable, Sendable {
    public let id: UUID
    public let sessionID: String
    public let planID: String
    public let dryRunReceiptID: String
    public let findingIDs: [String]
    public let identities: [String: FileIdentity]
    public let issuedAt: Date
    public let expiresAt: Date

    fileprivate init(
        id: UUID = UUID(),
        sessionID: String,
        planID: String,
        dryRunReceiptID: String,
        findingIDs: [String],
        identities: [String: FileIdentity],
        issuedAt: Date,
        expiresAt: Date
    ) {
        self.id = id
        self.sessionID = sessionID
        self.planID = planID
        self.dryRunReceiptID = dryRunReceiptID
        self.findingIDs = findingIDs
        self.identities = identities
        self.issuedAt = issuedAt
        self.expiresAt = expiresAt
    }
}

public enum TrashExecutionAuthorizationError: Error, Equatable, Sendable {
    case sessionNotReclaimReady
    case sessionInvalidated
    case planMismatch
    case dryRunReceiptMismatch
    case uncleanDryRunReceipt
    case dryRunActionsMismatch
    case noSelectedTrashItems
    case ineligibleFinding(String)
    case unsatisfiedConditions(String)
    case protectedRuleEvidence(String)
    case protectedPath(String)
    case duplicateFindingID(String)
    case authorizationExpired
    case authorizationUnavailable
}

public enum TrashExecutionReadinessState: String, Codable, Hashable, Sendable {
    case ready
    case missingEvidence
    case staleEvidence
    case uncleanDryRun
    case ineligibleSelection
}

public struct TrashExecutionReadiness: Codable, Hashable, Sendable {
    public let state: TrashExecutionReadinessState
    public let reason: String
    public let itemCount: Int
    public let estimatedBytes: Int64

    public var isReady: Bool { state == .ready }

    public static func evaluate(
        session: ScanSession?,
        plan: ReclaimPlan?,
        dryRunReceipt: ExecutionReceipt?
    ) -> TrashExecutionReadiness {
        guard let session, let plan, let dryRunReceipt else {
            return result(.missingEvidence, "Scan, plan, and dry-run evidence are required.")
        }
        guard [.dryRunReady, .reclaimReady].contains(session.stage),
              session.invalidationReasons.isEmpty,
              session.planDigest == plan.id,
              session.dryRunReceiptID == dryRunReceipt.id else {
            return result(.staleEvidence, "The plan or dry-run evidence is no longer current.")
        }
        guard dryRunReceipt.mode == ExecutionMode.dryRun.rawValue,
              dryRunReceipt.errors.isEmpty,
              !dryRunReceipt.userConfirmed else {
            return result(.uncleanDryRun, "Run a clean dry run before moving anything to Trash.")
        }
        let selected = plan.items.filter(\.selected)
        guard !selected.isEmpty,
              selected.allSatisfy({ item in
                  item.finding.safetyClass == .autoSafe
                      && item.finding.actionKind == .trash
                      && item.proposedAction == .trash
                      && item.conditions.allSatisfy(\.isSatisfied)
                      && !item.finding.ruleMatches.contains(where: {
                          $0.safetyClass == .preserveByDefault || $0.safetyClass == .neverTouch
                      })
                      && !isProtectedTrashPath(item.finding.path)
              }) else {
            return result(.ineligibleSelection, "Only selected auto-safe, recoverable Trash actions can run here.")
        }
        let expectedActions = selected.map {
            "\(URL(fileURLWithPath: $0.finding.path).standardizedFileURL.path)\u{0}\($0.proposedAction.rawValue)\u{0}dry-run"
        }.sorted()
        let actualActions = dryRunReceipt.actions.map {
            "\(URL(fileURLWithPath: $0.path).standardizedFileURL.path)\u{0}\($0.action.rawValue)\u{0}\($0.status)"
        }.sorted()
        guard expectedActions.count == actualActions.count,
              expectedActions == actualActions else {
            return result(.staleEvidence, "The dry-run actions do not match the selected plan.")
        }
        return TrashExecutionReadiness(
            state: .ready,
            reason: "A matching clean dry run is ready for explicit Trash confirmation.",
            itemCount: selected.count,
            estimatedBytes: selected.reduce(0) { $0 + $1.finding.allocatedSize }
        )
    }

    private static func result(_ state: TrashExecutionReadinessState, _ reason: String) -> TrashExecutionReadiness {
        TrashExecutionReadiness(state: state, reason: reason, itemCount: 0, estimatedBytes: 0)
    }
}

extension TrashExecutionAuthorizationError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .sessionNotReclaimReady: "The current scan session is not ready for reclaim."
        case .sessionInvalidated: "The current scan session was invalidated."
        case .planMismatch: "The current plan no longer matches the scan session."
        case .dryRunReceiptMismatch: "The dry-run receipt no longer matches the plan."
        case .uncleanDryRunReceipt: "A clean dry run is required."
        case .dryRunActionsMismatch: "The dry-run actions no longer match the selected items."
        case .noSelectedTrashItems: "No selected Trash items are available."
        case .ineligibleFinding: "A selected item is not eligible for recoverable Trash execution."
        case .unsatisfiedConditions: "A selected item's safety conditions are not satisfied."
        case .protectedRuleEvidence: "A selected item has protected rule evidence."
        case .protectedPath: "A selected path is protected by Ryddi's never-touch policy."
        case .duplicateFindingID: "The plan contains a duplicate finding identifier."
        case .authorizationExpired: "The one-time Trash authorization expired."
        case .authorizationUnavailable: "The one-time Trash authorization is unavailable or already used."
        }
    }
}

public actor TrashExecutionAuthorizationRegistry {
    public static let validityDuration: TimeInterval = 15 * 60

    private let identityReader: FileIdentityReader
    private var authorizations: [UUID: TrashExecutionAuthorization] = [:]

    public init(identityReader: FileIdentityReader = FileIdentityReader()) {
        self.identityReader = identityReader
    }

    public func issue(
        session: ScanSession,
        plan: ReclaimPlan,
        dryRunReceipt: ExecutionReceipt,
        now: Date = Date()
    ) throws -> TrashExecutionAuthorization {
        guard session.stage == .reclaimReady else {
            throw TrashExecutionAuthorizationError.sessionNotReclaimReady
        }
        guard session.invalidationReasons.isEmpty else {
            throw TrashExecutionAuthorizationError.sessionInvalidated
        }
        guard session.planDigest == plan.id else {
            throw TrashExecutionAuthorizationError.planMismatch
        }
        guard session.dryRunReceiptID == dryRunReceipt.id else {
            throw TrashExecutionAuthorizationError.dryRunReceiptMismatch
        }
        guard dryRunReceipt.mode == ExecutionMode.dryRun.rawValue,
              dryRunReceipt.errors.isEmpty,
              !dryRunReceipt.userConfirmed else {
            throw TrashExecutionAuthorizationError.uncleanDryRunReceipt
        }

        let selectedItems = plan.items.filter(\.selected)
        guard !selectedItems.isEmpty else {
            throw TrashExecutionAuthorizationError.noSelectedTrashItems
        }

        for item in selectedItems {
            try validate(item)
        }
        guard receiptActionsMatch(selectedItems: selectedItems, receipt: dryRunReceipt) else {
            throw TrashExecutionAuthorizationError.dryRunActionsMismatch
        }

        var identities: [String: FileIdentity] = [:]
        for item in selectedItems {
            guard identities[item.id] == nil else {
                throw TrashExecutionAuthorizationError.duplicateFindingID(item.id)
            }
            identities[item.id] = try identityReader.read(at: URL(fileURLWithPath: item.finding.path))
        }

        let authorization = TrashExecutionAuthorization(
            sessionID: session.id,
            planID: plan.id,
            dryRunReceiptID: dryRunReceipt.id,
            findingIDs: selectedItems.map(\.id),
            identities: identities,
            issuedAt: now,
            expiresAt: now.addingTimeInterval(Self.validityDuration)
        )
        authorizations[authorization.id] = authorization
        return authorization
    }

    public func consume(id: UUID, now: Date = Date()) throws -> TrashExecutionAuthorization {
        guard let authorization = authorizations.removeValue(forKey: id) else {
            throw TrashExecutionAuthorizationError.authorizationUnavailable
        }
        guard now < authorization.expiresAt else {
            throw TrashExecutionAuthorizationError.authorizationExpired
        }
        return authorization
    }

    public func revoke(id: UUID) {
        authorizations.removeValue(forKey: id)
    }

    private func validate(_ item: ReclaimPlanItem) throws {
        let finding = item.finding
        guard finding.safetyClass == .autoSafe,
              finding.actionKind == .trash,
              item.proposedAction == .trash else {
            throw TrashExecutionAuthorizationError.ineligibleFinding(item.id)
        }
        guard !hasProtectedRuleEvidence(finding) else {
            throw TrashExecutionAuthorizationError.protectedRuleEvidence(item.id)
        }
        guard !isProtectedTrashPath(finding.path) else {
            throw TrashExecutionAuthorizationError.protectedPath(item.id)
        }
        guard item.conditions.allSatisfy(\.isSatisfied) else {
            throw TrashExecutionAuthorizationError.unsatisfiedConditions(item.id)
        }
    }

    private func hasProtectedRuleEvidence(_ finding: Finding) -> Bool {
        finding.ruleMatches.contains { match in
            match.ruleID == "user.path.protected"
                || match.safetyClass == .preserveByDefault
                || match.safetyClass == .neverTouch
        }
    }

    private func receiptActionsMatch(
        selectedItems: [ReclaimPlanItem],
        receipt: ExecutionReceipt
    ) -> Bool {
        guard receipt.actions.count == selectedItems.count else {
            return false
        }

        let expected = selectedItems.map {
            DryRunActionIdentity(
                path: standardizedPath($0.finding.path),
                action: $0.proposedAction,
                status: "dry-run"
            )
        }
        let actual = receipt.actions.map {
            DryRunActionIdentity(
                path: standardizedPath($0.path),
                action: $0.action,
                status: $0.status
            )
        }
        return expected.sorted(by: DryRunActionIdentity.lessThan) == actual.sorted(by: DryRunActionIdentity.lessThan)
    }

    private func standardizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }
}

func isProtectedTrashPath(_ path: String) -> Bool {
    let normalized = URL(fileURLWithPath: path).standardizedFileURL.path.lowercased()
    let protectedCodexDirectories = [
        "/.codex/sessions",
        "/.codex/archived_sessions",
        "/.codex/memories"
    ]
    let protectedCodexFiles = [
        "/.codex/auth.json",
        "/.codex/config.toml"
    ]
    return protectedCodexDirectories.contains {
        normalized.hasSuffix($0) || normalized.contains($0 + "/")
    } || protectedCodexFiles.contains {
        normalized.hasSuffix($0)
    }
}

private struct DryRunActionIdentity: Equatable {
    let path: String
    let action: ActionKind
    let status: String

    static func lessThan(_ lhs: DryRunActionIdentity, _ rhs: DryRunActionIdentity) -> Bool {
        if lhs.path != rhs.path {
            return lhs.path < rhs.path
        }
        if lhs.action.rawValue != rhs.action.rawValue {
            return lhs.action.rawValue < rhs.action.rawValue
        }
        return lhs.status < rhs.status
    }
}
