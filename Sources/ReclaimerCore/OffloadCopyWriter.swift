import Foundation
import Darwin

public enum OffloadCopyError: LocalizedError, Sendable {
    case refused
    case retained(reason: String, path: String)
    case locationUnknown
    public var errorDescription: String? {
        switch self {
        case .refused: "Copy refused: the reviewed source/provider changed, or the destination already exists. The original was kept."
        case .retained(let reason, let path): "Copy was not accepted: \(reason) The original was kept. Review retained copy/staging at: \(path). No partial payload was deleted."
        case .locationUnknown: "Copy was not accepted. The original was kept. An external change prevented locating the staging copy; no partial payload was deleted."
        }
    }
}

public struct OffloadCopyWriter: Sendable {
    private let copyOperation: @Sendable (URL, URL) throws -> Void
    private let checkpoint: @Sendable (String, URL) throws -> Void
    public init() {
        copyOperation = { try FileManager.default.copyItem(at: $0, to: $1) }
        checkpoint = { _, _ in }
    }
    init(copyOperation: @escaping @Sendable (URL, URL) throws -> Void = {
        try FileManager.default.copyItem(at: $0, to: $1)
    }, checkpoint: @escaping @Sendable (String, URL) throws -> Void = { _, _ in }) {
        self.copyOperation = copyOperation
        self.checkpoint = checkpoint
    }

    public func copy(source: URL, sourceIdentity: FileIdentity, provider: URL,
                     providerIdentity: FileIdentity, name: String) throws -> URL {
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains("\0"),
              !sourceIdentity.isSymbolicLink, providerIdentity.isDirectory, !providerIdentity.isSymbolicLink,
              sourceIdentity.matchesCurrent(path: source.path), providerIdentity.matchesCurrent(path: provider.path) else {
            throw OffloadCopyError.refused
        }
        if sourceIdentity.isDirectory && (providerIdentity.canonicalPath == sourceIdentity.canonicalPath
            || providerIdentity.canonicalPath.hasPrefix(sourceIdentity.canonicalPath + "/")) {
            throw OffloadCopyError.refused
        }
        let sourceDescriptor = open(source.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard sourceDescriptor >= 0 else { throw OffloadCopyError.refused }
        defer { close(sourceDescriptor) }
        var original = stat()
        guard fstat(sourceDescriptor, &original) == 0, matches(original, sourceIdentity) else { throw OffloadCopyError.refused }
        let providerDescriptor = open(provider.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard providerDescriptor >= 0 else { throw OffloadCopyError.refused }
        defer { close(providerDescriptor) }
        var openedProvider = stat(), existing = stat()
        guard fstat(providerDescriptor, &openedProvider) == 0, matches(openedProvider, providerIdentity),
              providerIdentity.matchesCurrent(path: provider.path),
              fstatat(providerDescriptor, name, &existing, AT_SYMLINK_NOFOLLOW) != 0, errno == ENOENT else {
            throw OffloadCopyError.refused
        }
        let stagingName = ".ryddi-copy-\(UUID().uuidString)"
        guard mkdirat(providerDescriptor, stagingName, mode_t(0o700)) == 0 else { throw OffloadCopyError.refused }
        let stagingDescriptor = openat(providerDescriptor, stagingName, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard stagingDescriptor >= 0 else { throw OffloadCopyError.refused }
        defer { close(stagingDescriptor) }
        var staging = stat()
        guard fstat(stagingDescriptor, &staging) == 0 else { throw OffloadCopyError.locationUnknown }
        var stagingPath = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard fcntl(stagingDescriptor, F_GETPATH, &stagingPath) == 0 else { throw OffloadCopyError.locationUnknown }
        let stagingURL = URL(fileURLWithPath: String(cString: stagingPath), isDirectory: true)
        let partial = stagingURL.appendingPathComponent("payload")
        var payloadDescriptor: Int32 = -1
        defer { if payloadDescriptor >= 0 { close(payloadDescriptor) } }
        var accepted = false
        defer {
            if accepted && entryMatches(providerDescriptor, stagingName, staging) {
                unlinkat(providerDescriptor, stagingName, AT_REMOVEDIR)
            }
        }
        do {
            try checkpoint("reserved", stagingURL)
            try Task.checkCancellation()
            guard sourceIdentity.matchesCurrent(path: source.path), providerIdentity.matchesCurrent(path: provider.path),
                  entryMatches(providerDescriptor, stagingName, staging),
                  pathMatches(stagingURL.path, staging) else { throw OffloadCopyError.refused }
            try copyOperation(source, partial)
            payloadDescriptor = openat(stagingDescriptor, "payload", O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
            var payload = stat()
            guard payloadDescriptor >= 0, fstat(payloadDescriptor, &payload) == 0,
                  (payload.st_mode & S_IFMT) == S_IFREG || (payload.st_mode & S_IFMT) == S_IFDIR else {
                throw OffloadCopyError.refused
            }
            try checkpoint("copied", partial)
            try Task.checkCancellation()
            guard sourceIdentity.matchesCurrent(path: source.path), providerIdentity.matchesCurrent(path: provider.path),
                  entryMatches(providerDescriptor, stagingName, staging), entryMatches(stagingDescriptor, "payload", payload),
                  renameatx_np(stagingDescriptor, "payload", providerDescriptor, name, UInt32(RENAME_EXCL)) == 0 else {
                throw OffloadCopyError.refused
            }
            let destination = provider.appendingPathComponent(name)
            try checkpoint("published", destination)
            guard sourceIdentity.matchesCurrent(path: source.path), providerIdentity.matchesCurrent(path: provider.path),
                  entryMatches(providerDescriptor, name, payload) else { throw OffloadCopyError.refused }
            accepted = true
            return destination
        } catch {
            var path = [CChar](repeating: 0, count: Int(MAXPATHLEN))
            let retained = payloadDescriptor >= 0 ? payloadDescriptor : stagingDescriptor
            guard fcntl(retained, F_GETPATH, &path) == 0 else { throw OffloadCopyError.locationUnknown }
            throw OffloadCopyError.retained(reason: error.localizedDescription, path: String(cString: path))
        }
    }

    private func matches(_ info: stat, _ identity: FileIdentity) -> Bool {
        let kind = info.st_mode & S_IFMT
        return UInt64(info.st_dev) == identity.device && UInt64(info.st_ino) == identity.inode
            && (kind == S_IFREG || kind == S_IFDIR) && (kind == S_IFDIR) == identity.isDirectory
    }

    private func entryMatches(_ parent: Int32, _ name: String, _ expected: stat) -> Bool {
        var current = stat()
        return fstatat(parent, name, &current, AT_SYMLINK_NOFOLLOW) == 0
            && current.st_dev == expected.st_dev && current.st_ino == expected.st_ino
            && (current.st_mode & S_IFMT) == (expected.st_mode & S_IFMT)
    }

    private func pathMatches(_ path: String, _ expected: stat) -> Bool {
        var current = stat()
        return lstat(path, &current) == 0 && current.st_dev == expected.st_dev && current.st_ino == expected.st_ino
            && (current.st_mode & S_IFMT) == S_IFDIR
    }
}
