import CryptoKit
import Foundation

public enum ScanSessionStage: String, Codable, Hashable, Sendable {
    case notStarted
    case scanned
    case reviewed
    case planReady
    case dryRunReady
    case reclaimReady
    case executed
    case recoveryAvailable
    case invalidated
}

public enum ScanSessionInvalidationReason: String, Codable, Hashable, Sendable {
    case rootsChanged
    case rulesChanged
    case policyChanged
    case findingsChanged
    case planSelectionChanged
    case receiptExpired
    case appVersionChanged
}

public struct ScanSession: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let createdAt: Date
    public let updatedAt: Date
    public let appVersion: String
    public let ruleVersion: String
    public let preset: ScanScopePreset
    public let scopeDigest: String
    public let findingDigest: String?
    public let planDigest: String?
    public let dryRunReceiptID: String?
    public let executionReceiptID: String?
    public let stage: ScanSessionStage
    public let invalidationReasons: [ScanSessionInvalidationReason]

    public init(
        id: String = UUID().uuidString,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        appVersion: String,
        ruleVersion: String,
        preset: ScanScopePreset,
        scopeDigest: String,
        findingDigest: String? = nil,
        planDigest: String? = nil,
        dryRunReceiptID: String? = nil,
        executionReceiptID: String? = nil,
        stage: ScanSessionStage = .notStarted,
        invalidationReasons: [ScanSessionInvalidationReason] = []
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.appVersion = appVersion
        self.ruleVersion = ruleVersion
        self.preset = preset
        self.scopeDigest = scopeDigest
        self.findingDigest = findingDigest
        self.planDigest = planDigest
        self.dryRunReceiptID = dryRunReceiptID
        self.executionReceiptID = executionReceiptID
        self.stage = stage
        self.invalidationReasons = invalidationReasons
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case createdAt
        case updatedAt
        case appVersion
        case ruleVersion
        case preset
        case scopeDigest
        case findingDigest
        case planDigest
        case dryRunReceiptID
        case executionReceiptID
        case stage
        case invalidationReasons
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
        self.updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        self.appVersion = try container.decode(String.self, forKey: .appVersion)
        self.ruleVersion = try container.decode(String.self, forKey: .ruleVersion)
        self.preset = try container.decode(ScanScopePreset.self, forKey: .preset)
        self.scopeDigest = try container.decode(String.self, forKey: .scopeDigest)
        self.findingDigest = try container.decodeIfPresent(String.self, forKey: .findingDigest)
        self.planDigest = try container.decodeIfPresent(String.self, forKey: .planDigest)
        self.dryRunReceiptID = try container.decodeIfPresent(String.self, forKey: .dryRunReceiptID)
        self.executionReceiptID = try container.decodeIfPresent(String.self, forKey: .executionReceiptID)

        let decodedStage = try container.decodeIfPresent(ScanSessionStage.self, forKey: .stage) ?? .notStarted
        let decodedReasons = try container.decodeIfPresent([ScanSessionInvalidationReason].self, forKey: .invalidationReasons)

        if let decodedReasons {
            self.stage = decodedStage
            self.invalidationReasons = decodedReasons
        } else if decodedStage == .invalidated || self.findingDigest == nil {
            self.stage = .invalidated
            self.invalidationReasons = [.findingsChanged]
        } else {
            self.stage = decodedStage
            self.invalidationReasons = []
        }
    }
}

public struct ScanSessionDigestParts: Hashable, Sendable {
    public let appVersion: String
    public let ruleVersion: String
    public let preset: ScanScopePreset
    public let roots: [String]
    public let userPolicyDigest: String
    public let findingIDs: [String]
    public let actionKinds: [String]
    public let pathMetadata: [String: String]
    public let selectedPlanIDs: [String]

    public init(
        appVersion: String,
        ruleVersion: String,
        preset: ScanScopePreset,
        roots: [String],
        userPolicyDigest: String,
        findingIDs: [String],
        actionKinds: [String],
        pathMetadata: [String: String],
        selectedPlanIDs: [String] = []
    ) {
        self.appVersion = appVersion
        self.ruleVersion = ruleVersion
        self.preset = preset
        self.roots = roots
        self.userPolicyDigest = userPolicyDigest
        self.findingIDs = findingIDs
        self.actionKinds = actionKinds
        self.pathMetadata = pathMetadata
        self.selectedPlanIDs = selectedPlanIDs
    }
}

public enum ScanSessionDigestBuilder {
    public static func digest(_ parts: ScanSessionDigestParts) -> String {
        let payload = DigestPayload(
            appVersion: parts.appVersion,
            ruleVersion: parts.ruleVersion,
            preset: parts.preset.rawValue,
            roots: parts.roots.sorted(),
            userPolicyDigest: parts.userPolicyDigest,
            findingIDs: parts.findingIDs.sorted(),
            actionKinds: parts.actionKinds.sorted(),
            pathMetadata: Dictionary(uniqueKeysWithValues: parts.pathMetadata.sorted { lhs, rhs in
                if lhs.key == rhs.key {
                    return lhs.value < rhs.value
                }
                return lhs.key < rhs.key
            }),
            selectedPlanIDs: parts.selectedPlanIDs.sorted()
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = (try? encoder.encode(payload)) ?? Data(payload.canonicalString.utf8)
        return data.sha256Hex
    }

    private struct DigestPayload: Codable, Hashable {
        let appVersion: String
        let ruleVersion: String
        let preset: String
        let roots: [String]
        let userPolicyDigest: String
        let findingIDs: [String]
        let actionKinds: [String]
        let pathMetadata: [String: String]
        let selectedPlanIDs: [String]

        var canonicalString: String {
            [
                appVersion,
                ruleVersion,
                preset,
                roots.joined(separator: "\u{001f}"),
                userPolicyDigest,
                findingIDs.joined(separator: "\u{001f}"),
                actionKinds.joined(separator: "\u{001f}"),
                pathMetadata
                    .sorted { lhs, rhs in
                        if lhs.key == rhs.key {
                            return lhs.value < rhs.value
                        }
                        return lhs.key < rhs.key
                    }
                    .map { "\($0.key)=\($0.value)" }
                    .joined(separator: "\u{001f}"),
                selectedPlanIDs.joined(separator: "\u{001f}")
            ].joined(separator: "\u{001e}")
        }
    }
}

private extension Data {
    var sha256Hex: String {
        SHA256.hash(data: self).map { String(format: "%02x", $0) }.joined()
    }
}
