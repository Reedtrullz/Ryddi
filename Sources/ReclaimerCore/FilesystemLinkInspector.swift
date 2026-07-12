import Foundation

public struct OpenFileHit: Codable, Hashable, Sendable {
    public let path: String
    public let processSummary: String?
    public let fileIdentityKey: String?
    public let identityResolutionFailed: Bool

    public init(
        path: String,
        processSummary: String? = nil,
        fileIdentityKey: String? = nil,
        identityResolutionFailed: Bool = false
    ) {
        self.path = path
        self.processSummary = processSummary
        self.fileIdentityKey = fileIdentityKey
        self.identityResolutionFailed = identityResolutionFailed
    }
}

public struct FilesystemLinkEvidence: Codable, Hashable, Sendable {
    public let plannedIdentityKey: String?
    public let currentIdentityKey: String?
    public let plannedHardLinkCount: Int?
    public let currentHardLinkCount: Int?
    public let siblingPaths: [String]
    public let preservedSiblingPaths: [String]
    public let openIdentityKeys: [String]
    public let openHitPaths: [String]
    public let uniqueOpenHitPaths: [String]
    public let sharedOpenIdentityOnly: Bool
    public let blockReason: String?

    public init(
        plannedIdentityKey: String? = nil,
        currentIdentityKey: String? = nil,
        plannedHardLinkCount: Int? = nil,
        currentHardLinkCount: Int? = nil,
        siblingPaths: [String] = [],
        preservedSiblingPaths: [String] = [],
        openIdentityKeys: [String] = [],
        openHitPaths: [String] = [],
        uniqueOpenHitPaths: [String] = [],
        sharedOpenIdentityOnly: Bool = false,
        blockReason: String? = nil
    ) {
        self.plannedIdentityKey = plannedIdentityKey
        self.currentIdentityKey = currentIdentityKey
        self.plannedHardLinkCount = plannedHardLinkCount
        self.currentHardLinkCount = currentHardLinkCount
        self.siblingPaths = siblingPaths
        self.preservedSiblingPaths = preservedSiblingPaths
        self.openIdentityKeys = openIdentityKeys
        self.openHitPaths = openHitPaths
        self.uniqueOpenHitPaths = uniqueOpenHitPaths
        self.sharedOpenIdentityOnly = sharedOpenIdentityOnly
        self.blockReason = blockReason
    }

    public var isBlocked: Bool {
        blockReason != nil
    }
}

public protocol FilesystemLinkInspecting: Sendable {
    func inspect(
        candidateURL: URL,
        plannedIdentity: FilesystemIdentity?,
        openStatus: OpenFileStatus,
        selectedPaths: [String],
        knownPaths: [String]
    ) -> FilesystemLinkEvidence
}

public struct FilesystemLinkInspector: FilesystemLinkInspecting {
    public init() {}

    public func inspect(
        candidateURL: URL,
        plannedIdentity: FilesystemIdentity?,
        openStatus: OpenFileStatus,
        selectedPaths: [String],
        knownPaths: [String]
    ) -> FilesystemLinkEvidence {
        let candidatePath = candidateURL.standardizedFileURL.path
        let normalizedSelectedPaths = Set(selectedPaths.map(standardizedPath))
        let normalizedKnownPaths = Set(knownPaths.map(standardizedPath) + [candidatePath])

        let currentIdentity: FilesystemIdentity
        do {
            currentIdentity = try FilesystemIdentity.capture(at: candidateURL)
        } catch {
            return blocked(
                plannedIdentity: plannedIdentity,
                reason: "Filesystem identity could not be resolved before the open-file decision."
            )
        }

        var evidence = FilesystemLinkEvidence(
            plannedIdentityKey: plannedIdentity?.fileIdentityKey,
            currentIdentityKey: currentIdentity.fileIdentityKey,
            plannedHardLinkCount: plannedIdentity?.hardLinkCount,
            currentHardLinkCount: currentIdentity.hardLinkCount
        )

        if currentIdentity.isSymbolicLink {
            return evidence.withBlockReason("Symbolic links are ambiguous and cannot pass a clone-aware open-file check.")
        }

        if let checkedPath = openStatus.checkedPath,
           standardizedPath(checkedPath) != candidatePath {
            return evidence.withBlockReason("Open-file evidence was checked for a different path.")
        }

        if currentIdentity.isDirectory {
            guard openStatus.checkedRecursively else {
                return evidence.withBlockReason("Recursive open-file check was not completed for the directory.")
            }
            if let checkFailed = openStatus.checkFailed {
                return evidence.withBlockReason("Recursive open-file check failed: \(checkFailed)")
            }
            guard !openStatus.isOpen, openStatus.openHits.isEmpty else {
                return evidence.withBlockReason("Recursive open-file check found an open descendant.")
            }
            return evidence
        }

        guard currentIdentity.isRegularFile,
              let currentIdentityKey = currentIdentity.fileIdentityKey,
              let currentHardLinkCount = currentIdentity.hardLinkCount,
              currentHardLinkCount > 0 else {
            return evidence.withBlockReason("Regular-file identity or hard-link count could not be resolved.")
        }
        guard let plannedIdentity else {
            return evidence.withBlockReason("Planned filesystem identity is missing for a regular file.")
        }
        guard plannedIdentity == currentIdentity else {
            return evidence.withBlockReason("Filesystem identity or hard-link count changed after planning.")
        }
        if let checkFailed = openStatus.checkFailed {
            return evidence.withBlockReason("Open-file check failed: \(checkFailed)")
        }
        if openStatus.openHits.contains(where: \.identityResolutionFailed) {
            return evidence.withBlockReason("Open-file hit identity could not be resolved.")
        }
        if !openStatus.isOpen, !openStatus.openHits.isEmpty {
            return evidence.withBlockReason("Open-file evidence is inconsistent with the reported handle state.")
        }
        if openStatus.isOpen, openStatus.openHits.isEmpty {
            return evidence.withBlockReason("Open-file check reported a handle without identity evidence.")
        }

        guard currentHardLinkCount > 1 else {
            guard !openStatus.isOpen else {
                return evidence.withBlockReason("Open-file check found an active handle.")
            }
            return evidence
        }

        let siblingPaths: [String]
        do {
            siblingPaths = try discoverSiblingPaths(
                candidateURL: candidateURL,
                identityKey: currentIdentityKey,
                knownPaths: normalizedKnownPaths
            )
        } catch {
            return evidence.withBlockReason("Hard-link sibling set could not be resolved.")
        }
        guard siblingPaths.count >= currentHardLinkCount else {
            return evidence.withBlockReason("Hard-link sibling set is incomplete; cleanup would be ambiguous.")
        }

        let preservedSiblingPaths = siblingPaths.filter { !normalizedSelectedPaths.contains($0) }
        let openIdentityKeys = Array(Set(openStatus.openHits.compactMap(\.fileIdentityKey))).sorted()
        let openHitPaths = Array(Set(openStatus.openHits.map { standardizedPath($0.path) })).sorted()
        let uniqueOpenHitPaths = Array(Set(openStatus.openHits.filter {
            $0.fileIdentityKey != currentIdentityKey
        }.map { standardizedPath($0.path) })).sorted()

        evidence = FilesystemLinkEvidence(
            plannedIdentityKey: plannedIdentity.fileIdentityKey,
            currentIdentityKey: currentIdentityKey,
            plannedHardLinkCount: plannedIdentity.hardLinkCount,
            currentHardLinkCount: currentHardLinkCount,
            siblingPaths: siblingPaths,
            preservedSiblingPaths: preservedSiblingPaths,
            openIdentityKeys: openIdentityKeys,
            openHitPaths: openHitPaths,
            uniqueOpenHitPaths: uniqueOpenHitPaths,
            sharedOpenIdentityOnly: false
        )

        guard openStatus.isOpen else {
            return evidence
        }
        guard uniqueOpenHitPaths.isEmpty else {
            return evidence.withBlockReason("Unique open descendant or file identity was found.")
        }
        guard openStatus.openHits.allSatisfy({ $0.fileIdentityKey == currentIdentityKey }) else {
            return evidence.withBlockReason("Open-file hits could not be proven to share the candidate identity.")
        }
        guard !preservedSiblingPaths.isEmpty else {
            return evidence.withBlockReason("No preserved hard-link sibling remains outside the selected paths.")
        }

        return FilesystemLinkEvidence(
            plannedIdentityKey: evidence.plannedIdentityKey,
            currentIdentityKey: evidence.currentIdentityKey,
            plannedHardLinkCount: evidence.plannedHardLinkCount,
            currentHardLinkCount: evidence.currentHardLinkCount,
            siblingPaths: evidence.siblingPaths,
            preservedSiblingPaths: evidence.preservedSiblingPaths,
            openIdentityKeys: evidence.openIdentityKeys,
            openHitPaths: evidence.openHitPaths,
            uniqueOpenHitPaths: evidence.uniqueOpenHitPaths,
            sharedOpenIdentityOnly: true
        )
    }

    private func discoverSiblingPaths(
        candidateURL: URL,
        identityKey: String,
        knownPaths: Set<String>
    ) throws -> [String] {
        var paths = Set(knownPaths.filter { path in
            guard let identity = try? FilesystemIdentity.capture(at: URL(fileURLWithPath: path)) else {
                return false
            }
            return identity.fileIdentityKey == identityKey && !identity.isSymbolicLink
        })
        paths.insert(candidateURL.standardizedFileURL.path)

        let parent = candidateURL.deletingLastPathComponent()
        let children = try FileManager.default.contentsOfDirectory(
            at: parent,
            includingPropertiesForKeys: nil,
            options: [.skipsPackageDescendants]
        )
        for child in children {
            guard let identity = try? FilesystemIdentity.capture(at: child),
                  !identity.isSymbolicLink,
                  identity.fileIdentityKey == identityKey else {
                continue
            }
            paths.insert(child.standardizedFileURL.path)
        }
        return paths.sorted()
    }

    private func blocked(
        plannedIdentity: FilesystemIdentity?,
        reason: String
    ) -> FilesystemLinkEvidence {
        FilesystemLinkEvidence(
            plannedIdentityKey: plannedIdentity?.fileIdentityKey,
            plannedHardLinkCount: plannedIdentity?.hardLinkCount,
            blockReason: reason
        )
    }

    private func standardizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }
}

private extension FilesystemLinkEvidence {
    func withBlockReason(_ reason: String) -> FilesystemLinkEvidence {
        FilesystemLinkEvidence(
            plannedIdentityKey: plannedIdentityKey,
            currentIdentityKey: currentIdentityKey,
            plannedHardLinkCount: plannedHardLinkCount,
            currentHardLinkCount: currentHardLinkCount,
            siblingPaths: siblingPaths,
            preservedSiblingPaths: preservedSiblingPaths,
            openIdentityKeys: openIdentityKeys,
            openHitPaths: openHitPaths,
            uniqueOpenHitPaths: uniqueOpenHitPaths,
            sharedOpenIdentityOnly: sharedOpenIdentityOnly,
            blockReason: reason
        )
    }
}
