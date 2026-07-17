import Foundation

public enum ProtectionRuleProposalError: Error, Equatable, Sendable {
    case invalidLocalPath
}

public enum ProtectionRuleProposalReason: String, CaseIterable, Hashable, Sendable {
    case localCloudRoot
    case secretSource
    case userSelectedProtection
}

public enum ProtectionRuleProposalKind: String, CaseIterable, Hashable, Sendable {
    case protect
}

/// An inert suggestion to add one local protection rule after an explicit user decision.
/// The proposal is runtime-only and has no policy-store or cleanup authority.
public struct ProtectionRuleProposal: Hashable, Identifiable, Sendable {
    public static let maximumPathBytes = 4_096

    public let id: UUID
    public let subject: ProtectionSubject
    public let localPath: String
    public let reason: ProtectionRuleProposalReason
    public let includeDescendants: Bool
    public let proposedAt: Date

    public init(
        id: UUID = UUID(),
        subject: ProtectionSubject,
        localPath: String,
        reason: ProtectionRuleProposalReason,
        includeDescendants: Bool = true,
        proposedAt: Date = Date()
    ) throws {
        guard Self.isValidLocalPath(localPath) else {
            throw ProtectionRuleProposalError.invalidLocalPath
        }
        self.id = id
        self.subject = subject
        self.localPath = Self.standardizedPath(localPath)
        self.reason = reason
        self.includeDescendants = includeDescendants
        self.proposedAt = proposedAt
    }

    public var proposedKind: ProtectionRuleProposalKind { .protect }
    public var isAdditiveOnly: Bool { true }
    public var requiresExplicitConfirmation: Bool { true }

    private static func isValidLocalPath(_ path: String) -> Bool {
        guard !path.isEmpty,
              path.utf8.count <= maximumPathBytes,
              NSString(string: path).isAbsolutePath,
              !path.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            return false
        }
        let standardized = standardizedPath(path)
        return standardized != "/"
            && standardized.utf8.count <= maximumPathBytes
    }

    private static func standardizedPath(_ path: String) -> String {
        URL(fileURLWithPath: NSString(string: path).expandingTildeInPath).standardizedFileURL.path
    }
}
