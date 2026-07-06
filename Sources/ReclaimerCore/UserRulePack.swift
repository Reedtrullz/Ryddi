import Foundation

public enum UserRulePackValidationSeverity: String, Codable, Hashable, Sendable {
    case error
    case warning
}

public struct UserRulePackValidationIssue: Codable, Hashable, Identifiable, Sendable {
    public var id: String { "\(severity.rawValue):\(ruleID ?? "document"):\(message)" }
    public let severity: UserRulePackValidationSeverity
    public let ruleID: String?
    public let message: String

    public init(severity: UserRulePackValidationSeverity, ruleID: String? = nil, message: String) {
        self.severity = severity
        self.ruleID = ruleID
        self.message = message
    }
}

public struct UserRulePackDocument: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 1
    public static let defaultNonClaims = [
        "User rule packs are local review data; importing one does not delete files or grant macOS permissions.",
        "User rules are disabled for scans unless explicitly included.",
        "Imported rules cannot grant unattended cleanup permissions or override never-touch safety downward.",
        "Rule packs can contain private path fragments, app names, or user notes; review before sharing."
    ]

    public let schemaVersion: Int
    public let id: String
    public let exportedAt: Date
    public let rules: [ReclaimerRule]
    public let nonClaims: [String]

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        id: String = UUID().uuidString,
        exportedAt: Date = Date(),
        rules: [ReclaimerRule],
        nonClaims: [String] = Self.defaultNonClaims
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.exportedAt = exportedAt
        self.rules = rules
        self.nonClaims = nonClaims
    }
}

public struct UserRulePackPreview: Codable, Hashable, Sendable {
    public let sourcePath: String
    public let rulePackPath: String
    public let isImportable: Bool
    public let ruleCount: Int
    public let acceptedRuleCount: Int
    public let rejectedRuleCount: Int
    public let issues: [UserRulePackValidationIssue]
    public let document: UserRulePackDocument
    public let nonClaims: [String]

    public init(
        sourcePath: String,
        rulePackPath: String,
        isImportable: Bool,
        ruleCount: Int,
        acceptedRuleCount: Int,
        rejectedRuleCount: Int,
        issues: [UserRulePackValidationIssue],
        document: UserRulePackDocument,
        nonClaims: [String]
    ) {
        self.sourcePath = sourcePath
        self.rulePackPath = rulePackPath
        self.isImportable = isImportable
        self.ruleCount = ruleCount
        self.acceptedRuleCount = acceptedRuleCount
        self.rejectedRuleCount = rejectedRuleCount
        self.issues = issues
        self.document = document
        self.nonClaims = nonClaims
    }
}

public struct UserRulePackImportResult: Codable, Hashable, Sendable {
    public let sourcePath: String
    public let rulePackPath: String
    public let mode: String
    public let importedRuleCount: Int
    public let finalRuleCount: Int
    public let includedByDefault: Bool
    public let issues: [UserRulePackValidationIssue]
    public let nonClaims: [String]

    public init(
        sourcePath: String,
        rulePackPath: String,
        mode: String,
        importedRuleCount: Int,
        finalRuleCount: Int,
        includedByDefault: Bool,
        issues: [UserRulePackValidationIssue],
        nonClaims: [String]
    ) {
        self.sourcePath = sourcePath
        self.rulePackPath = rulePackPath
        self.mode = mode
        self.importedRuleCount = importedRuleCount
        self.finalRuleCount = finalRuleCount
        self.includedByDefault = includedByDefault
        self.issues = issues
        self.nonClaims = nonClaims
    }
}

public enum UserRulePackError: LocalizedError {
    case unsupportedSchemaVersion(Int)
    case validationFailed([UserRulePackValidationIssue])

    public var errorDescription: String? {
        switch self {
        case .unsupportedSchemaVersion(let version):
            return "Unsupported user rule pack schema version: \(version)"
        case .validationFailed(let issues):
            let errors = issues.filter { $0.severity == .error }
            return "User rule pack failed validation with \(errors.count) error(s). Preview the pack for details."
        }
    }
}

public final class UserRulePackStore: @unchecked Sendable {
    private let root: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(root: URL = UserPathPolicyStore.defaultRoot(), fileManager: FileManager = .default) {
        self.root = root
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
    }

    public var rulePackURL: URL {
        root.appendingPathComponent("user-rules.json")
    }

    public func loadDocument() throws -> UserRulePackDocument {
        guard fileManager.fileExists(atPath: rulePackURL.path) else {
            return UserRulePackDocument(rules: [])
        }
        let data = try Data(contentsOf: rulePackURL)
        let document = try decodeDocument(from: data)
        guard document.schemaVersion == UserRulePackDocument.currentSchemaVersion else {
            throw UserRulePackError.unsupportedSchemaVersion(document.schemaVersion)
        }
        return document
    }

    public func loadValidatedRules() throws -> [ReclaimerRule] {
        let document = try loadDocument()
        let issues = validate(document)
        guard !issues.contains(where: { $0.severity == .error }) else {
            throw UserRulePackError.validationFailed(issues)
        }
        return document.rules
    }

    public func preview(from url: URL) throws -> UserRulePackPreview {
        let data = try Data(contentsOf: url)
        let document = try decodeDocument(from: data)
        let issues = validate(document)
        let rejectedRuleIDs = Set(issues.filter { $0.severity == .error }.compactMap(\.ruleID))
        return UserRulePackPreview(
            sourcePath: url.standardizedFileURL.path,
            rulePackPath: rulePackURL.path,
            isImportable: document.schemaVersion == UserRulePackDocument.currentSchemaVersion && rejectedRuleIDs.isEmpty && !issues.contains { $0.severity == .error && $0.ruleID == nil },
            ruleCount: document.rules.count,
            acceptedRuleCount: document.rules.filter { !rejectedRuleIDs.contains($0.id) }.count,
            rejectedRuleCount: rejectedRuleIDs.count,
            issues: issues,
            document: document,
            nonClaims: document.nonClaims
        )
    }

    public func exportDocument(exportedAt: Date = Date()) throws -> UserRulePackDocument {
        let current = try loadDocument()
        return UserRulePackDocument(exportedAt: exportedAt, rules: current.rules, nonClaims: current.nonClaims)
    }

    @discardableResult
    public func writeExport(to url: URL, exportedAt: Date = Date()) throws -> URL {
        try writeExport(exportDocument(exportedAt: exportedAt), to: url)
    }

    @discardableResult
    public func writeExport(_ document: UserRulePackDocument, to url: URL) throws -> URL {
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(document).write(to: url, options: .atomic)
        return url
    }

    @discardableResult
    public func importDocument(from url: URL, merge: Bool = true) throws -> UserRulePackImportResult {
        let data = try Data(contentsOf: url)
        let importedDocument = try decodeDocument(from: data)
        guard importedDocument.schemaVersion == UserRulePackDocument.currentSchemaVersion else {
            throw UserRulePackError.unsupportedSchemaVersion(importedDocument.schemaVersion)
        }
        let issues = validate(importedDocument)
        guard !issues.contains(where: { $0.severity == .error }) else {
            throw UserRulePackError.validationFailed(issues)
        }

        let finalRules: [ReclaimerRule]
        if merge {
            let importedIDs = Set(importedDocument.rules.map(\.id))
            let retained = try loadDocument().rules.filter { !importedIDs.contains($0.id) }
            finalRules = retained + importedDocument.rules
        } else {
            finalRules = importedDocument.rules
        }

        let finalDocument = UserRulePackDocument(rules: finalRules, nonClaims: UserRulePackDocument.defaultNonClaims)
        try save(finalDocument)
        return UserRulePackImportResult(
            sourcePath: url.standardizedFileURL.path,
            rulePackPath: rulePackURL.path,
            mode: merge ? "merge" : "replace",
            importedRuleCount: importedDocument.rules.count,
            finalRuleCount: finalRules.count,
            includedByDefault: false,
            issues: issues,
            nonClaims: UserRulePackDocument.defaultNonClaims
        )
    }

    @discardableResult
    public func save(_ document: UserRulePackDocument) throws -> URL {
        let issues = validate(document)
        guard !issues.contains(where: { $0.severity == .error }) else {
            throw UserRulePackError.validationFailed(issues)
        }
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        try encoder.encode(document).write(to: rulePackURL, options: .atomic)
        return rulePackURL
    }

    public func validate(_ document: UserRulePackDocument) -> [UserRulePackValidationIssue] {
        var issues: [UserRulePackValidationIssue] = []
        if document.schemaVersion != UserRulePackDocument.currentSchemaVersion {
            issues.append(.init(severity: .error, message: "Unsupported schema version \(document.schemaVersion)."))
        }
        if document.rules.isEmpty {
            issues.append(.init(severity: .warning, message: "Rule pack contains no rules."))
        }

        let bundledIDs = (try? RuleEngine.bundled().rules.map(\.id)).map(Set.init) ?? []
        var seenRuleIDs = Set<String>()
        for rule in document.rules {
            let id = rule.id.trimmingCharacters(in: .whitespacesAndNewlines)
            if id.isEmpty {
                issues.append(.init(severity: .error, ruleID: rule.id, message: "Rule id cannot be empty."))
            }
            if bundledIDs.contains(rule.id) {
                issues.append(.init(severity: .error, ruleID: rule.id, message: "User rule id conflicts with a bundled rule id."))
            }
            if !seenRuleIDs.insert(rule.id).inserted {
                issues.append(.init(severity: .error, ruleID: rule.id, message: "Duplicate rule id in this rule pack."))
            }
            if rule.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append(.init(severity: .error, ruleID: rule.id, message: "Rule title cannot be empty."))
            }
            if rule.category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append(.init(severity: .error, ruleID: rule.id, message: "Rule category cannot be empty."))
            }
            if rule.evidence.isEmpty {
                issues.append(.init(severity: .warning, ruleID: rule.id, message: "Rule has no evidence text. Add a short explanation for review UX."))
            }
            validateSafety(rule, issues: &issues)
            validateMatch(rule, issues: &issues)
        }
        return issues
    }

    private func validateSafety(_ rule: ReclaimerRule, issues: inout [UserRulePackValidationIssue]) {
        switch rule.safetyClass {
        case .reviewRequired, .preserveByDefault, .neverTouch:
            break
        case .autoSafe, .safeAfterCondition:
            issues.append(.init(
                severity: .error,
                ruleID: rule.id,
                message: "User rules cannot use \(rule.safetyClass.label); custom packs may only add review, preserve, or never-touch signals."
            ))
        }

        switch rule.actionKind {
        case .reportOnly, .openGuidance, .nativeToolCommand:
            break
        case .trash, .deleteCache, .compress, .quarantineHold:
            issues.append(.init(
                severity: .error,
                ruleID: rule.id,
                message: "User rules cannot request \(rule.actionKind.label); custom packs cannot grant cleanup actions."
            ))
        }
    }

    private func validateMatch(_ rule: ReclaimerRule, issues: inout [UserRulePackValidationIssue]) {
        let patterns = rule.match.containsAny + rule.match.suffixAny + rule.match.basenameAny + rule.match.pathExtensionAny
        if patterns.isEmpty {
            issues.append(.init(severity: .error, ruleID: rule.id, message: "Rule must include at least one match pattern."))
            return
        }

        for pattern in patterns {
            let trimmed = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                issues.append(.init(severity: .error, ruleID: rule.id, message: "Match patterns cannot be empty."))
            }
            if trimmed == "/" || trimmed == "~" || trimmed == "/Users" || trimmed == "/Users/" {
                issues.append(.init(severity: .error, ruleID: rule.id, message: "Match pattern \(trimmed) is too broad."))
            } else if trimmed.count < 3 {
                issues.append(.init(severity: .warning, ruleID: rule.id, message: "Match pattern \(trimmed) is very short and may classify too many paths."))
            }
        }
    }

    private func decodeDocument(from data: Data) throws -> UserRulePackDocument {
        do {
            return try decoder.decode(UserRulePackDocument.self, from: data)
        } catch {
            do {
                let file = try decoder.decode(ReclaimerRuleFile.self, from: data)
                return UserRulePackDocument(rules: file.rules)
            } catch {
                let rules = try decoder.decode([ReclaimerRule].self, from: data)
                return UserRulePackDocument(rules: rules)
            }
        }
    }
}
