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
    public let policyDigest: String?
    public let findingDigest: String?
    public let planDigest: String?
    public let dryRunReceiptID: String?
    public let executionReceiptID: String?
    public let stage: ScanSessionStage
    public let invalidationReasons: [ScanSessionInvalidationReason]

    public var requiresVerificationScan: Bool {
        stage == .executed || stage == .recoveryAvailable
    }

    public init(
        id: String = UUID().uuidString,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        appVersion: String,
        ruleVersion: String,
        preset: ScanScopePreset,
        scopeDigest: String,
        policyDigest: String? = nil,
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
        self.policyDigest = policyDigest
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
        case policyDigest
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
        self.policyDigest = try container.decodeIfPresent(String.self, forKey: .policyDigest)
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

    public func recordScan(findingDigest: String, updatedAt: Date = Date()) -> ScanSession {
        return copy(
            updatedAt: updatedAt,
            findingDigest: findingDigest,
            planDigest: .some(nil),
            dryRunReceiptID: .some(nil),
            executionReceiptID: .some(nil),
            stage: .scanned,
            invalidationReasons: []
        )
    }

    public func recordReviewSelection(findingDigest: String, updatedAt: Date = Date()) -> ScanSession {
        guard !requiresVerificationScan else { return self }
        return copy(
            updatedAt: updatedAt,
            findingDigest: findingDigest,
            planDigest: .some(nil),
            dryRunReceiptID: .some(nil),
            executionReceiptID: .some(nil),
            stage: .reviewed,
            invalidationReasons: []
        )
    }

    public func recordReviewSelection(updatedAt: Date = Date()) -> ScanSession {
        guard !requiresVerificationScan else { return self }
        guard let findingDigest else {
            return copy(
                updatedAt: updatedAt,
                planDigest: .some(nil),
                dryRunReceiptID: .some(nil),
                executionReceiptID: .some(nil),
                stage: .invalidated,
                invalidationReasons: [.findingsChanged]
            )
        }
        return recordReviewSelection(findingDigest: findingDigest, updatedAt: updatedAt)
    }

    public func recordPlan(planDigest: String, updatedAt: Date = Date()) -> ScanSession {
        guard !requiresVerificationScan else { return self }
        return copy(
            updatedAt: updatedAt,
            planDigest: planDigest,
            dryRunReceiptID: .some(nil),
            executionReceiptID: .some(nil),
            stage: .planReady,
            invalidationReasons: []
        )
    }

    public func recordDryRunReceipt(_ receipt: ExecutionReceipt, updatedAt: Date = Date()) -> ScanSession {
        guard !requiresVerificationScan else { return self }
        return copy(
            updatedAt: updatedAt,
            dryRunReceiptID: receipt.id,
            executionReceiptID: .some(nil),
            stage: .dryRunReady,
            invalidationReasons: []
        )
    }

    public func markReclaimReady(updatedAt: Date = Date()) -> ScanSession {
        guard !requiresVerificationScan else { return self }
        return copy(updatedAt: updatedAt, stage: .reclaimReady, invalidationReasons: [])
    }

    public func recordExecutionReceipt(_ receipt: ExecutionReceipt, updatedAt: Date = Date()) -> ScanSession {
        let nextStage: ScanSessionStage = receipt.actions.contains(where: Self.isRecoverableAction) ? .recoveryAvailable : .executed
        return copy(updatedAt: updatedAt, executionReceiptID: receipt.id, stage: nextStage, invalidationReasons: [])
    }

    public func invalidatedIfBaselineChanged(
        scopeDigest: String,
        ruleVersion: String,
        policyDigest: String?,
        findingDigest: String?,
        updatedAt: Date = Date()
    ) -> ScanSession {
        var reasons: [ScanSessionInvalidationReason] = []
        if self.scopeDigest != scopeDigest {
            reasons.append(.rootsChanged)
        }
        if self.ruleVersion != ruleVersion {
            reasons.append(.rulesChanged)
        }
        if self.policyDigest != policyDigest {
            reasons.append(.policyChanged)
        }
        if self.findingDigest != findingDigest {
            reasons.append(.findingsChanged)
        }
        guard !reasons.isEmpty else {
            return self
        }
        return copy(
            updatedAt: updatedAt,
            planDigest: .some(nil),
            dryRunReceiptID: .some(nil),
            executionReceiptID: .some(nil),
            stage: .invalidated,
            invalidationReasons: reasons
        )
    }

    private static func isRecoverableAction(_ action: ExecutionActionReceipt) -> Bool {
        guard action.status == "done" else {
            return false
        }
        switch action.action {
        case .trash, .quarantineHold:
            return true
        case .reportOnly, .deleteCache, .compress, .nativeToolCommand, .openGuidance:
            return false
        }
    }

    private func copy(
        updatedAt: Date,
        scopeDigest: String? = nil,
        policyDigest: String?? = nil,
        findingDigest: String?? = nil,
        planDigest: String?? = nil,
        dryRunReceiptID: String?? = nil,
        executionReceiptID: String?? = nil,
        stage: ScanSessionStage? = nil,
        invalidationReasons: [ScanSessionInvalidationReason]? = nil
    ) -> ScanSession {
        ScanSession(
            id: id,
            createdAt: createdAt,
            updatedAt: updatedAt,
            appVersion: appVersion,
            ruleVersion: ruleVersion,
            preset: preset,
            scopeDigest: scopeDigest ?? self.scopeDigest,
            policyDigest: policyDigest ?? self.policyDigest,
            findingDigest: findingDigest ?? self.findingDigest,
            planDigest: planDigest ?? self.planDigest,
            dryRunReceiptID: dryRunReceiptID ?? self.dryRunReceiptID,
            executionReceiptID: executionReceiptID ?? self.executionReceiptID,
            stage: stage ?? self.stage,
            invalidationReasons: invalidationReasons ?? self.invalidationReasons
        )
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

public enum ScanSessionEvidenceBuilder {
    public static func scannedSession(
        appVersion: String,
        ruleVersion: String,
        preset: ScanScopePreset,
        scopes: [ScanScope],
        userPathPolicy: UserPathPolicy,
        findings: [Finding],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) -> ScanSession {
        let policy = policyDigest(preset: preset, userPathPolicy: userPathPolicy)
        let session = ScanSession(
            createdAt: createdAt,
            updatedAt: updatedAt,
            appVersion: appVersion,
            ruleVersion: ruleVersion,
            preset: preset,
            scopeDigest: scopeDigest(
                appVersion: appVersion,
                ruleVersion: ruleVersion,
                preset: preset,
                scopes: scopes,
                userPathPolicy: userPathPolicy
            ),
            policyDigest: policy,
            stage: .notStarted
        )
        return session.recordScan(
            findingDigest: findingDigest(
                appVersion: appVersion,
                ruleVersion: ruleVersion,
                preset: preset,
                scopes: scopes,
                userPathPolicy: userPathPolicy,
                findings: findings
            ),
            updatedAt: updatedAt
        )
    }

    public static func scopeDigest(
        appVersion: String,
        ruleVersion: String,
        preset: ScanScopePreset,
        scopes: [ScanScope],
        userPathPolicy: UserPathPolicy
    ) -> String {
        let policy = policyDigest(preset: preset, userPathPolicy: userPathPolicy)
        return ScanSessionDigestBuilder.digest(ScanSessionDigestParts(
            appVersion: appVersion,
            ruleVersion: ruleVersion,
            preset: preset,
            roots: scopes.map { $0.root.standardizedFileURL.path },
            userPolicyDigest: policy,
            findingIDs: [],
            actionKinds: [],
            pathMetadata: [:]
        ))
    }

    public static func policyDigest(
        preset: ScanScopePreset,
        userPathPolicy: UserPathPolicy
    ) -> String {
        let policyFingerprint = userPathPolicy.rules
            .map { rule in
                [
                    rule.kind.rawValue,
                    rule.path,
                    rule.includeDescendants ? "descendants" : "exact",
                    rule.reason ?? ""
                ].joined(separator: "\u{001f}")
            }
            .sorted()
            .joined(separator: "\u{001e}")
        return ScanSessionDigestBuilder.digest(ScanSessionDigestParts(
            appVersion: "user-path-policy",
            ruleVersion: "v1",
            preset: preset,
            roots: [],
            userPolicyDigest: policyFingerprint,
            findingIDs: [],
            actionKinds: [],
            pathMetadata: [:]
        ))
    }

    public static func findingDigest(
        appVersion: String,
        ruleVersion: String,
        preset: ScanScopePreset,
        scopes: [ScanScope],
        userPathPolicy: UserPathPolicy,
        findings: [Finding]
    ) -> String {
        let policy = policyDigest(preset: preset, userPathPolicy: userPathPolicy)
        let metadata = findings.reduce(into: [String: String]()) { output, finding in
            output[finding.path] = [
                "allocated=\(finding.allocatedSize)",
                "logical=\(finding.logicalSize)",
                "directory=\(finding.isDirectory)",
                "symlink=\(finding.isSymbolicLink)",
                "safety=\(finding.safetyClass.rawValue)",
                "action=\(finding.actionKind.rawValue)",
                "modified=\(finding.modificationDate?.timeIntervalSince1970 ?? -1)",
                "filesystemIdentity=\(finding.filesystemIdentity?.digestComponent ?? "missing")"
            ].joined(separator: "\u{001f}")
        }
        return ScanSessionDigestBuilder.digest(ScanSessionDigestParts(
            appVersion: appVersion,
            ruleVersion: ruleVersion,
            preset: preset,
            roots: scopes.map { $0.root.standardizedFileURL.path },
            userPolicyDigest: policy,
            findingIDs: findings.map(\.path),
            actionKinds: findings.map(\.actionKind.rawValue),
            pathMetadata: metadata
        ))
    }
}

private extension Data {
    var sha256Hex: String {
        SHA256.hash(data: self).map { String(format: "%02x", $0) }.joined()
    }
}
