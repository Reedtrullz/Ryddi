import Foundation

public struct SavedScopeSet: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let summary: String?
    public let createdAt: Date
    public let updatedAt: Date
    public let scopes: [ScanScope]

    public init(
        id: String = UUID().uuidString,
        name: String,
        summary: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        scopes: [ScanScope]
    ) {
        self.id = id
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.summary = summary?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.scopes = Self.normalized(scopes)
    }

    public init(
        id: String = UUID().uuidString,
        name: String,
        summary: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        paths: [String]
    ) {
        self.init(
            id: id,
            name: name,
            summary: summary,
            createdAt: createdAt,
            updatedAt: updatedAt,
            scopes: paths.map {
                let url = URL(fileURLWithPath: $0).standardizedFileURL
                return ScanScope(name: url.lastPathComponent.nilIfEmpty ?? url.path, root: url)
            }
        )
    }

    public var plan: ScanScopePlan {
        DefaultScopes.customPlan(
            label: name,
            summary: summary ?? "Saved custom scan scope set with explicit local roots.",
            scopes: scopes,
            nonClaims: SavedScopeSetDocument.defaultNonClaims
        )
    }

    private static func normalized(_ scopes: [ScanScope]) -> [ScanScope] {
        DefaultScopes.customPlan(scopes: scopes.map {
            ScanScope(name: $0.name.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? $0.root.lastPathComponent.nilIfEmpty ?? $0.root.path, root: $0.root.standardizedFileURL)
        }).scopes
    }
}

public struct SavedScopeSetDocument: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 1
    public static let defaultNonClaims = [
        "Saved scope sets store scan roots only; they do not change Ryddi's safety rules or cleanup protections.",
        "Scanning a saved path does not mean Ryddi will select it for cleanup.",
        "Saved scope exports can contain private local paths and names; review before sharing."
    ]

    public let schemaVersion: Int
    public let id: String
    public let exportedAt: Date
    public let sets: [SavedScopeSet]
    public let nonClaims: [String]

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        id: String = UUID().uuidString,
        exportedAt: Date = Date(),
        sets: [SavedScopeSet],
        nonClaims: [String] = Self.defaultNonClaims
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.exportedAt = exportedAt
        self.sets = Self.deduplicated(sets)
        self.nonClaims = nonClaims
    }

    private static func deduplicated(_ sets: [SavedScopeSet]) -> [SavedScopeSet] {
        var seen = Set<String>()
        var output: [SavedScopeSet] = []
        for set in sets where !set.name.isEmpty && !set.scopes.isEmpty {
            let key = set.id
            guard seen.insert(key).inserted else { continue }
            output.append(set)
        }
        return output.sorted { lhs, rhs in
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }
}

public struct SavedScopeSetImportResult: Codable, Hashable, Sendable {
    public let sourcePath: String
    public let scopeSetPath: String
    public let mode: String
    public let importedSetCount: Int
    public let finalSetCount: Int
    public let nonClaims: [String]

    public init(
        sourcePath: String,
        scopeSetPath: String,
        mode: String,
        importedSetCount: Int,
        finalSetCount: Int,
        nonClaims: [String]
    ) {
        self.sourcePath = sourcePath
        self.scopeSetPath = scopeSetPath
        self.mode = mode
        self.importedSetCount = importedSetCount
        self.finalSetCount = finalSetCount
        self.nonClaims = nonClaims
    }
}

public enum SavedScopeSetError: LocalizedError {
    case unsupportedSchemaVersion(Int)
    case emptyName
    case emptyScopes
    case notFound(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedSchemaVersion(let version):
            return "Unsupported saved scope set schema version: \(version)"
        case .emptyName:
            return "Saved scope set name cannot be empty."
        case .emptyScopes:
            return "Saved scope set requires at least one path."
        case .notFound(let reference):
            return "No saved scope set found for \(reference)."
        }
    }
}

public final class SavedScopeSetStore: @unchecked Sendable {
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

    public var scopeSetURL: URL {
        root.appendingPathComponent("saved-scope-sets.json")
    }

    public func loadDocument() throws -> SavedScopeSetDocument {
        guard fileManager.fileExists(atPath: scopeSetURL.path) else {
            return SavedScopeSetDocument(sets: [])
        }
        let data = try Data(contentsOf: scopeSetURL)
        let document = try decoder.decode(SavedScopeSetDocument.self, from: data)
        guard document.schemaVersion == SavedScopeSetDocument.currentSchemaVersion else {
            throw SavedScopeSetError.unsupportedSchemaVersion(document.schemaVersion)
        }
        return document
    }

    public func list() -> [SavedScopeSet] {
        (try? loadDocument().sets) ?? []
    }

    public func find(_ reference: String) throws -> SavedScopeSet {
        let normalized = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw SavedScopeSetError.notFound(reference)
        }
        let lower = normalized.lowercased()
        let sets = try loadDocument().sets
        if let exact = sets.first(where: { $0.id == normalized || $0.name.lowercased() == lower }) {
            return exact
        }
        if let prefix = sets.first(where: { $0.id.hasPrefix(normalized) }) {
            return prefix
        }
        throw SavedScopeSetError.notFound(reference)
    }

    public func plan(reference: String) throws -> ScanScopePlan {
        try find(reference).plan
    }

    @discardableResult
    public func upsert(name: String, paths: [String], summary: String? = nil) throws -> SavedScopeSet {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw SavedScopeSetError.emptyName
        }
        guard !paths.isEmpty else {
            throw SavedScopeSetError.emptyScopes
        }

        let sets = try loadDocument().sets
        let existing = sets.first { $0.name.lowercased() == trimmed.lowercased() }
        let now = Date()
        let set = SavedScopeSet(
            id: existing?.id ?? UUID().uuidString,
            name: trimmed,
            summary: summary,
            createdAt: existing?.createdAt ?? now,
            updatedAt: now,
            paths: paths
        )
        guard !set.scopes.isEmpty else {
            throw SavedScopeSetError.emptyScopes
        }
        let retained = sets.filter { $0.id != set.id && $0.name.lowercased() != trimmed.lowercased() }
        try save(SavedScopeSetDocument(sets: retained + [set]))
        return set
    }

    @discardableResult
    public func remove(reference: String) throws -> SavedScopeSetDocument {
        let target = try find(reference)
        let document = SavedScopeSetDocument(sets: try loadDocument().sets.filter { $0.id != target.id })
        try save(document)
        return document
    }

    public func exportDocument(exportedAt: Date = Date()) throws -> SavedScopeSetDocument {
        SavedScopeSetDocument(exportedAt: exportedAt, sets: try loadDocument().sets)
    }

    @discardableResult
    public func writeExport(_ document: SavedScopeSetDocument, to url: URL) throws -> URL {
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(document).write(to: url, options: .atomic)
        return url
    }

    @discardableResult
    public func importDocument(from url: URL, merge: Bool = true) throws -> SavedScopeSetImportResult {
        let data = try Data(contentsOf: url)
        let imported = try decoder.decode(SavedScopeSetDocument.self, from: data)
        guard imported.schemaVersion == SavedScopeSetDocument.currentSchemaVersion else {
            throw SavedScopeSetError.unsupportedSchemaVersion(imported.schemaVersion)
        }
        let finalSets: [SavedScopeSet]
        if merge {
            let importedKeys = Set(imported.sets.flatMap { [$0.id, $0.name.lowercased()] })
            let retained = try loadDocument().sets.filter { !importedKeys.contains($0.id) && !importedKeys.contains($0.name.lowercased()) }
            finalSets = retained + imported.sets
        } else {
            finalSets = imported.sets
        }
        try save(SavedScopeSetDocument(sets: finalSets))
        return SavedScopeSetImportResult(
            sourcePath: url.standardizedFileURL.path,
            scopeSetPath: scopeSetURL.path,
            mode: merge ? "merge" : "replace",
            importedSetCount: imported.sets.count,
            finalSetCount: finalSets.count,
            nonClaims: SavedScopeSetDocument.defaultNonClaims
        )
    }

    @discardableResult
    public func save(_ document: SavedScopeSetDocument) throws -> URL {
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        try encoder.encode(document).write(to: scopeSetURL, options: .atomic)
        return scopeSetURL
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
