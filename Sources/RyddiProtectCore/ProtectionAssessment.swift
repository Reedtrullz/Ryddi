import Foundation

public enum ProtectionAssessmentError: Error, Equatable, Sendable {
    case invalidScanSessionID
    case invalidFindingID
    case missingRequiredReason
}

/// Binds advisory protection evidence to the exact item observed by a scan.
/// This type is runtime-only and cannot authorize cleanup.
public struct ProtectionSubject: Hashable, Sendable {
    public let scanSessionID: String
    public let findingID: String
    public let filesystemIdentity: ProtectionFilesystemIdentity

    public init(
        scanSessionID: String,
        findingID: String,
        filesystemIdentity: ProtectionFilesystemIdentity
    ) throws {
        guard Self.isBoundedIdentifier(scanSessionID) else {
            throw ProtectionAssessmentError.invalidScanSessionID
        }
        guard Self.isBoundedIdentifier(findingID) else {
            throw ProtectionAssessmentError.invalidFindingID
        }
        self.scanSessionID = scanSessionID
        self.findingID = findingID
        self.filesystemIdentity = filesystemIdentity
    }

    private static func isBoundedIdentifier(_ value: String) -> Bool {
        !value.isEmpty
            && value.utf8.count <= 1_024
            && !value.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }
}

public enum ProtectionEvidenceSource: String, CaseIterable, Hashable, Sendable {
    case localCloudRoot
    case userSelectedCloudObject
    case secretSourceMetadata
    case unknown
}

public enum ProtectionAssessmentState: String, CaseIterable, Hashable, Sendable {
    case unknown
    case requiresProtection
    case providerEvidenceObserved
    case nativeExportRequired
    case rebuildableExclusionCandidate
}

public enum ProtectionAssessmentReason: String, CaseIterable, Hashable, Sendable {
    case noCurrentEvidence
    case metadataOnly
    case contentIdentityMatched
    case cloudNativeDocument
    case secretSource
    case rebuildableData
    case localIdentityChanged
    case unsupportedProviderState
    case userDecisionRequired
}

/// An inert explanation result. It is intentionally non-Codable and has no cleanup-eligible state.
public struct ProtectionAssessment: Hashable, Identifiable, Sendable {
    public let id: UUID
    public let subject: ProtectionSubject
    public let source: ProtectionEvidenceSource
    public let state: ProtectionAssessmentState
    public let reasons: Set<ProtectionAssessmentReason>
    public let assessedAt: Date

    public init(
        id: UUID = UUID(),
        subject: ProtectionSubject,
        source: ProtectionEvidenceSource,
        state: ProtectionAssessmentState,
        reasons: Set<ProtectionAssessmentReason>,
        assessedAt: Date = Date()
    ) throws {
        guard Self.requiredReasons(for: state).isSubset(of: reasons) else {
            throw ProtectionAssessmentError.missingRequiredReason
        }
        self.id = id
        self.subject = subject
        self.source = source
        self.state = state
        self.reasons = reasons
        self.assessedAt = assessedAt
    }

    /// Cleanup authority remains exclusively in ReclaimerCore's existing verified execution flow.
    public var isAdvisoryOnly: Bool { true }

    private static func requiredReasons(
        for state: ProtectionAssessmentState
    ) -> Set<ProtectionAssessmentReason> {
        switch state {
        case .unknown:
            [.noCurrentEvidence]
        case .requiresProtection:
            [.userDecisionRequired]
        case .providerEvidenceObserved:
            [.contentIdentityMatched]
        case .nativeExportRequired:
            [.cloudNativeDocument]
        case .rebuildableExclusionCandidate:
            [.rebuildableData]
        }
    }
}
