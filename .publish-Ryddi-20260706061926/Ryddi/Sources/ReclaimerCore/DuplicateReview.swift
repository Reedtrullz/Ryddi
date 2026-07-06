import CryptoKit
import Foundation

public struct DuplicateReviewOptions: Codable, Hashable, Sendable {
    public let minimumFileSize: Int64
    public let maximumDepth: Int
    public let maximumFilesToHash: Int
    public let includeHidden: Bool
    public let includePreserveByDefault: Bool

    public init(
        minimumFileSize: Int64 = 1_000_000,
        maximumDepth: Int = 6,
        maximumFilesToHash: Int = 5_000,
        includeHidden: Bool = true,
        includePreserveByDefault: Bool = false
    ) {
        self.minimumFileSize = minimumFileSize
        self.maximumDepth = maximumDepth
        self.maximumFilesToHash = maximumFilesToHash
        self.includeHidden = includeHidden
        self.includePreserveByDefault = includePreserveByDefault
    }
}

public struct DuplicateFile: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let scopeName: String
    public let path: String
    public let displayName: String
    public let logicalSize: Int64
    public let allocatedSize: Int64
    public let modificationDate: Date?
    public let ownerHint: String?
    public let safetyClass: SafetyClass
    public let actionKind: ActionKind
    public let category: String
    public let ruleMatches: [RuleMatch]
    public let evidence: [Evidence]
    public let digest: String

    public init(
        id: String = UUID().uuidString,
        scopeName: String,
        path: String,
        displayName: String,
        logicalSize: Int64,
        allocatedSize: Int64,
        modificationDate: Date?,
        ownerHint: String?,
        safetyClass: SafetyClass,
        actionKind: ActionKind,
        category: String,
        ruleMatches: [RuleMatch],
        evidence: [Evidence],
        digest: String
    ) {
        self.id = id
        self.scopeName = scopeName
        self.path = path
        self.displayName = displayName
        self.logicalSize = logicalSize
        self.allocatedSize = allocatedSize
        self.modificationDate = modificationDate
        self.ownerHint = ownerHint
        self.safetyClass = safetyClass
        self.actionKind = actionKind
        self.category = category
        self.ruleMatches = ruleMatches
        self.evidence = evidence
        self.digest = digest
    }
}

public struct DuplicateGroup: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let digest: String
    public let logicalSize: Int64
    public let files: [DuplicateFile]
    public let apparentDuplicateBytes: Int64
    public let notes: [String]

    public init(digest: String, logicalSize: Int64, files: [DuplicateFile], notes: [String]) {
        self.id = "\(logicalSize)-\(digest)"
        self.digest = digest
        self.logicalSize = logicalSize
        self.files = files.sorted { lhs, rhs in
            if lhs.safetyClass.riskRank == rhs.safetyClass.riskRank {
                return lhs.path < rhs.path
            }
            return lhs.safetyClass.riskRank > rhs.safetyClass.riskRank
        }
        self.apparentDuplicateBytes = Self.estimatedApparentBytes(files: files)
        self.notes = notes
    }

    private static func estimatedApparentBytes(files: [DuplicateFile]) -> Int64 {
        guard files.count > 1 else { return 0 }
        let allocated = files.map(\.allocatedSize).sorted(by: >)
        return allocated.dropFirst().reduce(0, +)
    }
}

public struct DuplicateReview: Codable, Hashable, Sendable {
    public let createdAt: Date
    public let scannedRoots: [String]
    public let groups: [DuplicateGroup]
    public let skipped: [String]
    public let notes: [String]

    public init(
        createdAt: Date = Date(),
        scannedRoots: [String],
        groups: [DuplicateGroup],
        skipped: [String],
        notes: [String]
    ) {
        self.createdAt = createdAt
        self.scannedRoots = scannedRoots
        self.groups = groups
        self.skipped = skipped
        self.notes = notes
    }

    public var duplicateFileCount: Int {
        groups.reduce(0) { $0 + $1.files.count }
    }

    public var apparentDuplicateBytes: Int64 {
        groups.reduce(0) { $0 + $1.apparentDuplicateBytes }
    }
}

public final class DuplicateReviewScanner: @unchecked Sendable {
    private struct Candidate: Hashable {
        let scopeName: String
        let url: URL
        let logicalSize: Int64
        let allocatedSize: Int64
        let modificationDate: Date?
        let ownerHint: String?
        let classification: Classification
        let resourceIdentifier: String?
    }

    private let fileManager: FileManager
    private let ruleEngine: RuleEngine

    public init(fileManager: FileManager = .default, ruleEngine: RuleEngine? = nil) throws {
        self.fileManager = fileManager
        self.ruleEngine = try ruleEngine ?? RuleEngine.bundled()
    }

    public func scan(scopes: [ScanScope], options: DuplicateReviewOptions = DuplicateReviewOptions()) -> DuplicateReview {
        var skipped: [String] = []
        var candidatesBySize: [Int64: [Candidate]] = [:]
        var seenResourceIdentifiers = Set<String>()

        for scope in scopes {
            collectCandidates(
                scope: scope,
                options: options,
                skipped: &skipped,
                seenResourceIdentifiers: &seenResourceIdentifiers,
                candidatesBySize: &candidatesBySize
            )
        }

        var hashedCount = 0
        var filesByDigest: [String: [DuplicateFile]] = [:]
        let candidateGroups = candidatesBySize.values
            .filter { $0.count > 1 }
            .flatMap { $0 }
            .sorted { lhs, rhs in
                if lhs.logicalSize == rhs.logicalSize {
                    return lhs.url.path < rhs.url.path
                }
                return lhs.logicalSize > rhs.logicalSize
            }

        for candidate in candidateGroups {
            guard hashedCount < options.maximumFilesToHash else {
                appendSkip("Skipped additional duplicate candidates after hashing \(options.maximumFilesToHash) file(s).", to: &skipped)
                break
            }

            guard let digest = stableDigest(for: candidate, skipped: &skipped) else { continue }
            hashedCount += 1
            let duplicateSafety = candidate.classification.safetyClass.riskRank > SafetyClass.reviewRequired.riskRank
                ? candidate.classification.safetyClass
                : .reviewRequired

            let file = DuplicateFile(
                scopeName: candidate.scopeName,
                path: candidate.url.path,
                displayName: candidate.url.lastPathComponent,
                logicalSize: candidate.logicalSize,
                allocatedSize: candidate.allocatedSize,
                modificationDate: candidate.modificationDate,
                ownerHint: candidate.ownerHint,
                safetyClass: duplicateSafety,
                actionKind: .openGuidance,
                category: candidate.classification.matches.first?.category ?? "Unmatched",
                ruleMatches: candidate.classification.matches,
                evidence: duplicateEvidence(for: candidate),
                digest: digest
            )
            filesByDigest[digest, default: []].append(file)
        }

        let groups = filesByDigest.values
            .filter { $0.count > 1 }
            .map { files in
                DuplicateGroup(
                    digest: files[0].digest,
                    logicalSize: files[0].logicalSize,
                    files: files,
                    notes: [
                        "Review-only duplicate signal. Ryddi does not choose which copy to keep.",
                        "Apparent duplicate bytes assume one copy is kept; APFS clones, snapshots, and sparse files can change immediate reclaim.",
                        "Use Finder or Quick Look before removing any duplicate, especially preserve-by-default files."
                    ]
                )
            }
            .sorted { lhs, rhs in
                if lhs.apparentDuplicateBytes == rhs.apparentDuplicateBytes {
                    return lhs.id < rhs.id
                }
                return lhs.apparentDuplicateBytes > rhs.apparentDuplicateBytes
            }

        return DuplicateReview(
            scannedRoots: scopes.map { $0.root.standardizedFileURL.path },
            groups: groups,
            skipped: skipped,
            notes: [
                "Duplicate review is local-only and hashes file contents on this Mac; hashes are not uploaded.",
                "Never-touch and preserve-by-default paths are excluded unless preserve-by-default review is explicitly enabled.",
                "No duplicate group is selected for automatic cleanup or added to a reclaim plan."
            ]
        )
    }

    private func collectCandidates(
        scope: ScanScope,
        options: DuplicateReviewOptions,
        skipped: inout [String],
        seenResourceIdentifiers: inout Set<String>,
        candidatesBySize: inout [Int64: [Candidate]]
    ) {
        let root = scope.root.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory) else {
            appendSkip("Missing root: \(root.path)", to: &skipped)
            return
        }
        guard fileManager.isReadableFile(atPath: root.path) else {
            appendSkip("Unreadable root: \(root.path)", to: &skipped)
            return
        }

        if !isDirectory.boolValue {
            addCandidateIfEligible(
                root,
                scopeName: scope.name,
                options: options,
                skipped: &skipped,
                seenResourceIdentifiers: &seenResourceIdentifiers,
                candidatesBySize: &candidatesBySize
            )
            return
        }

        var enumerationOptions: FileManager.DirectoryEnumerationOptions = [.skipsPackageDescendants]
        if !options.includeHidden {
            enumerationOptions.insert(.skipsHiddenFiles)
        }

        var enumerationSkips: [String] = []
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: duplicateResourceKeys,
            options: enumerationOptions,
            errorHandler: { url, error in
                appendSkip("Could not read \(url.path): \(error.localizedDescription)", to: &enumerationSkips)
                return true
            }
        ) else {
            appendSkip("Could not enumerate root: \(root.path)", to: &skipped)
            return
        }

        let rootDepth = root.pathComponents.count
        for case let url as URL in enumerator {
            let depth = max(0, url.standardizedFileURL.pathComponents.count - rootDepth)
            if depth > options.maximumDepth {
                enumerator.skipDescendants()
                continue
            }

            let values = try? url.resourceValues(forKeys: Set(duplicateResourceKeys))
            if values?.isDirectory == true {
                let classification = ruleEngine.classify(path: url.path, isDirectory: true, isSymbolicLink: values?.isSymbolicLink == true)
                if classification.safetyClass == .neverTouch || shouldSkipForDuplicateReview(path: url.path) {
                    appendSkip("Skipped protected subtree: \(url.path)", to: &skipped)
                    enumerator.skipDescendants()
                }
                continue
            }

            addCandidateIfEligible(
                url,
                scopeName: scope.name,
                values: values,
                options: options,
                skipped: &skipped,
                seenResourceIdentifiers: &seenResourceIdentifiers,
                candidatesBySize: &candidatesBySize
            )
        }
        for message in enumerationSkips {
            appendSkip(message, to: &skipped)
        }
    }

    private func addCandidateIfEligible(
        _ url: URL,
        scopeName: String,
        values providedValues: URLResourceValues? = nil,
        options: DuplicateReviewOptions,
        skipped: inout [String],
        seenResourceIdentifiers: inout Set<String>,
        candidatesBySize: inout [Int64: [Candidate]]
    ) {
        let values = providedValues ?? (try? url.resourceValues(forKeys: Set(duplicateResourceKeys)))
        guard values?.isSymbolicLink != true else { return }
        guard values?.isRegularFile == true else { return }

        let logicalSize = Int64(values?.fileSize ?? 0)
        guard logicalSize >= options.minimumFileSize else { return }

        let classification = ruleEngine.classify(path: url.path, isDirectory: false, isSymbolicLink: false)
        guard classification.safetyClass != .neverTouch, !shouldSkipForDuplicateReview(path: url.path) else {
            appendSkip("Skipped protected file: \(url.path)", to: &skipped)
            return
        }
        if classification.safetyClass == .preserveByDefault, !options.includePreserveByDefault {
            appendSkip("Skipped preserve-by-default file: \(url.path)", to: &skipped)
            return
        }

        let resourceIdentifier = values?.fileResourceIdentifier.map { String(describing: $0) }
        if let resourceIdentifier, !seenResourceIdentifiers.insert(resourceIdentifier).inserted {
            appendSkip("Skipped hard-linked file already represented elsewhere: \(url.path)", to: &skipped)
            return
        }

        let allocatedSize = Int64(values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? values?.fileSize ?? 0)
        let candidate = Candidate(
            scopeName: scopeName,
            url: url.standardizedFileURL,
            logicalSize: logicalSize,
            allocatedSize: allocatedSize,
            modificationDate: values?.contentModificationDate,
            ownerHint: duplicateOwnerHint(for: url.path),
            classification: classification,
            resourceIdentifier: resourceIdentifier
        )
        candidatesBySize[logicalSize, default: []].append(candidate)
    }

    private func stableDigest(for candidate: Candidate, skipped: inout [String]) -> String? {
        let before = try? candidate.url.resourceValues(forKeys: Set(duplicateResourceKeys))
        do {
            let digest = try sha256Hex(for: candidate.url)
            let after = try? candidate.url.resourceValues(forKeys: Set(duplicateResourceKeys))
            guard before?.fileSize == after?.fileSize,
                  before?.contentModificationDate == after?.contentModificationDate else {
                appendSkip("Skipped changing file while hashing: \(candidate.url.path)", to: &skipped)
                return nil
            }
            return digest
        } catch {
            appendSkip("Could not hash \(candidate.url.path): \(error.localizedDescription)", to: &skipped)
            return nil
        }
    }

    private func sha256Hex(for url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var hasher = SHA256()
        while true {
            let chunk = try handle.read(upToCount: 1024 * 1024) ?? Data()
            guard !chunk.isEmpty else { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func duplicateEvidence(for candidate: Candidate) -> [Evidence] {
        var evidence = candidate.classification.evidence
        evidence.append(Evidence(kind: "duplicate.hash", message: "Content hash matched another regular file with the same logical size."))
        evidence.append(Evidence(kind: "duplicate.review-only", message: "Duplicate review does not grant cleanup permission; choose any removal manually after inspection."))
        evidence.append(Evidence(kind: "size", message: "Allocated size: \(ByteFormat.string(candidate.allocatedSize)); logical size: \(ByteFormat.string(candidate.logicalSize))."))
        return evidence
    }
}

private let duplicateResourceKeys: [URLResourceKey] = [
    .isDirectoryKey,
    .isRegularFileKey,
    .isSymbolicLinkKey,
    .fileSizeKey,
    .fileAllocatedSizeKey,
    .totalFileAllocatedSizeKey,
    .contentModificationDateKey,
    .fileResourceIdentifierKey
]

private func appendSkip(_ message: String, to skipped: inout [String]) {
    guard skipped.count < 200, skipped.last != message else { return }
    skipped.append(message)
}

private func shouldSkipForDuplicateReview(path: String) -> Bool {
    let lower = (path as NSString).standardizingPath.lowercased()
    let basename = URL(fileURLWithPath: path).lastPathComponent.lowercased()

    if lower.contains("/applications/") || lower.hasSuffix(".app") { return true }
    if lower.contains("/library/keychains/") || lower.contains("/.ssh/") || lower.contains("/.gnupg/") { return true }
    if lower.contains("/library/application support/google/chrome/") { return true }
    if lower.contains("/library/application support/firefox/profiles/") { return true }
    if lower.contains("/library/application support/brave") { return true }
    if lower.contains("/library/application support/microsoft edge") { return true }
    if lower.contains("/library/group containers/") { return true }
    if lower.contains("/library/containers/") { return true }
    if lower.contains("/.colima/") || lower.contains("/.docker/") { return true }
    if lower.contains("/photos library.photoslibrary/") || lower.hasSuffix(".photoslibrary") { return true }
    if lower.contains("/music library.musiclibrary/") || lower.hasSuffix(".musiclibrary") { return true }
    if lower.contains("/.codex/memories") || lower.contains("/.codex/skills") || lower.contains("/.codex/plugins") { return true }
    if lower.contains("/mobile documents/") || lower.contains(".icloud") { return true }

    let protectedBasenames: Set<String> = [
        "auth.json",
        "config.toml",
        "known_hosts",
        "id_rsa",
        "id_ed25519",
        "login data",
        "cookies",
        "key4.db",
        "cert9.db",
        "places.sqlite",
        "docker.raw",
        "disk.img",
        "disk.raw"
    ]
    if protectedBasenames.contains(basename) { return true }

    let protectedExtensions: Set<String> = ["keychain", "keychain-db"]
    return protectedExtensions.contains(URL(fileURLWithPath: path).pathExtension.lowercased())
}

private func duplicateOwnerHint(for path: String) -> String? {
    let lower = path.lowercased()
    if lower.contains("/.codex") || lower.contains("com.openai.codex") { return "Codex" }
    if lower.contains("/.colima") { return "Colima" }
    if lower.contains("/docker") { return "Docker" }
    if lower.contains("/developer/xcode") || lower.contains("/deriveddata") { return "Xcode" }
    if lower.contains("/homebrew") || lower.contains("/.cache/homebrew") { return "Homebrew" }
    if lower.contains("/google/chrome") || lower.contains("/chrome/") { return "Chrome" }
    if lower.contains("/garageband") { return "GarageBand" }
    if lower.contains("/logic") { return "Logic" }
    return nil
}
