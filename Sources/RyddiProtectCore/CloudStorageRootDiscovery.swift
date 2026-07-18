import Foundation
#if canImport(Darwin)
import Darwin
#endif

public struct CloudRootIdentity: Hashable, Sendable {
    public let deviceID: UInt64
    public let inode: UInt64

    public init(deviceID: UInt64, inode: UInt64) {
        self.deviceID = deviceID
        self.inode = inode
    }
}

public enum CloudRootOrigin: String, Hashable, Sendable {
    case fileProvider
    case userSelected
}

public struct CloudStorageRootCandidate: Hashable, Identifiable, Sendable {
    public let id: String
    public let provider: CloudProviderKind
    public let url: URL
    public let displayName: String
    public let origin: CloudRootOrigin
    public let identity: CloudRootIdentity
    public let requiresConfirmation: Bool

    public init(
        provider: CloudProviderKind,
        url: URL,
        displayName: String,
        origin: CloudRootOrigin,
        identity: CloudRootIdentity,
        requiresConfirmation: Bool = true
    ) {
        self.id = "\(provider.rawValue):\(identity.deviceID):\(identity.inode)"
        self.provider = provider
        self.url = url.standardizedFileURL
        self.displayName = displayName
        self.origin = origin
        self.identity = identity
        self.requiresConfirmation = requiresConfirmation
    }
}

public struct CloudStorageRootDiscoveryReport: Sendable {
    public let generatedAt: Date
    public let cloudStorageContainer: URL
    public let candidates: [CloudStorageRootCandidate]
    public let rejectedSymlinks: [URL]
    public let unreadableRoots: [URL]
    public let nonClaims: [String]

    public init(
        generatedAt: Date = Date(),
        cloudStorageContainer: URL,
        candidates: [CloudStorageRootCandidate],
        rejectedSymlinks: [URL],
        unreadableRoots: [URL],
        nonClaims: [String]
    ) {
        self.generatedAt = generatedAt
        self.cloudStorageContainer = cloudStorageContainer
        self.candidates = candidates
        self.rejectedSymlinks = rejectedSymlinks
        self.unreadableRoots = unreadableRoots
        self.nonClaims = nonClaims
    }
}

public struct CloudStorageRootDiscovery: Sendable {
    public static let nonClaims = [
        "Discovery lists only immediate candidate sync roots and does not traverse their contents.",
        "A local sync folder is not proof that every file is uploaded, current, or recoverable.",
        "Ryddi does not hydrate placeholders, connect an account, move files, or delete cloud data during discovery.",
        "Every inferred root requires explicit confirmation before it can influence protection guidance."
    ]

    public init() {}

    public func discover(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        userSelectedMegaRoots: [URL] = []
    ) -> CloudStorageRootDiscoveryReport {
        let container = home
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("CloudStorage", isDirectory: true)
            .standardizedFileURL
        var candidates: [CloudStorageRootCandidate] = []
        var rejectedSymlinks: [URL] = []
        var unreadableRoots: [URL] = []
        let fileManager = FileManager.default

        if fileManager.fileExists(atPath: container.path) {
            do {
                let children = try fileManager.contentsOfDirectory(
                    at: container,
                    includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                    options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
                )
                for child in children.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                    guard let provider = Self.provider(forRootName: child.lastPathComponent) else { continue }
                    addCandidate(
                        child,
                        provider: provider,
                        origin: .fileProvider,
                        candidates: &candidates,
                        rejectedSymlinks: &rejectedSymlinks,
                        unreadableRoots: &unreadableRoots
                    )
                }
            } catch {
                unreadableRoots.append(container)
            }
        }

        for root in userSelectedMegaRoots.map(\.standardizedFileURL) {
            addCandidate(
                root,
                provider: .mega,
                origin: .userSelected,
                candidates: &candidates,
                rejectedSymlinks: &rejectedSymlinks,
                unreadableRoots: &unreadableRoots
            )
        }

        var seen = Set<String>()
        candidates = candidates.filter { seen.insert($0.id).inserted }
        return CloudStorageRootDiscoveryReport(
            cloudStorageContainer: container,
            candidates: candidates,
            rejectedSymlinks: rejectedSymlinks,
            unreadableRoots: unreadableRoots,
            nonClaims: Self.nonClaims
        )
    }

    public static func provider(forRootName name: String) -> CloudProviderKind? {
        let normalized = name.lowercased().replacingOccurrences(of: " ", with: "")
        if normalized.contains("dropbox") { return .dropbox }
        if normalized.contains("googledrive") { return .googleDrive }
        if normalized == "mega" || normalized.hasPrefix("mega-") { return .mega }
        return nil
    }

    private func addCandidate(
        _ url: URL,
        provider: CloudProviderKind,
        origin: CloudRootOrigin,
        candidates: inout [CloudStorageRootCandidate],
        rejectedSymlinks: inout [URL],
        unreadableRoots: inout [URL]
    ) {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values?.isSymbolicLink != true else {
            rejectedSymlinks.append(url)
            return
        }
        guard values?.isDirectory == true, let identity = identity(for: url) else {
            unreadableRoots.append(url)
            return
        }
        candidates.append(CloudStorageRootCandidate(
            provider: provider,
            url: url,
            displayName: url.lastPathComponent,
            origin: origin,
            identity: identity
        ))
    }

    private func identity(for url: URL) -> CloudRootIdentity? {
        #if canImport(Darwin)
        var metadata = stat()
        guard lstat(url.path, &metadata) == 0, (metadata.st_mode & S_IFMT) == S_IFDIR else {
            return nil
        }
        return CloudRootIdentity(deviceID: UInt64(metadata.st_dev), inode: UInt64(metadata.st_ino))
        #else
        return nil
        #endif
    }
}
