import Foundation
import Darwin

public enum SessionArchiveError: LocalizedError, Sendable {
    case invalidSource
    case invalidDestination
    case insufficientSpace
    case archiveAlreadyExists
    case compressionFailed
    case verificationFailed
    case sourceChanged

    public var errorDescription: String? {
        switch self {
        case .invalidSource: "The session is not a regular file or is a symbolic link."
        case .invalidDestination: "The private archive folder is missing, redirected, or symbolic."
        case .insufficientSpace: "There is not enough free space to create and verify the archive safely."
        case .archiveAlreadyExists: "A session archive with this name already exists."
        case .compressionFailed: "The session could not be compressed. The partial archive was removed."
        case .verificationFailed: "The compressed archive failed its integrity check and was removed."
        case .sourceChanged: "The session changed while it was being archived. The original was kept."
        }
    }
}

public enum SessionTrashError: LocalizedError, Equatable, Sendable {
    case invalidSource
    case sourceChanged
    case stagingFailed
    case trashFailed
    case retained(String)
    case locationUnknown

    public var errorDescription: String? {
        switch self {
        case .invalidSource: "The reviewed item is no longer a regular file or directory."
        case .sourceChanged: "The reviewed item changed before it could be moved."
        case .stagingFailed: "Ryddi could not stage the exact reviewed item safely."
        case .trashFailed: "The Trash handoff could not be verified."
        case .retained(let path): "The Trash handoff was refused. Retained item: \(path). Review this location before acting again."
        case .locationUnknown: "An external change prevented locating the reviewed item. Ryddi did not permanently delete it; review the source and Trash manually."
        }
    }
}

public struct SessionArchiveWriter: Sendable {
    public init() {}

    public func writeVerifiedArchive(source: URL, destinationDirectory: URL) throws -> URL {
        let manager = FileManager.default
        let source = source.standardizedFileURL
        let destinationDirectory = URL(
            fileURLWithPath: securityNormalizedPath(destinationDirectory.standardizedFileURL.path),
            isDirectory: true
        )
        let sourceDescriptor = open(source.path, O_RDONLY | O_NOFOLLOW)
        guard sourceDescriptor >= 0 else {
            throw SessionArchiveError.invalidSource
        }
        let input = FileHandle(fileDescriptor: sourceDescriptor, closeOnDealloc: true)
        defer { try? input.close() }
        guard let original = FileSnapshot.capture(descriptor: sourceDescriptor),
              original.isRegularFile,
              !original.isSymbolicLink,
              original.matchesCurrent(source) else {
            throw SessionArchiveError.invalidSource
        }

        let values = try manager.homeDirectoryForCurrentUser.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey]
        )
        let available = Int64(values.volumeAvailableCapacityForImportantUsage ?? 0)
        guard available > original.sizeBytes + 536_870_912 else {
            throw SessionArchiveError.insufficientSpace
        }

        var existingAncestor = destinationDirectory
        while !manager.fileExists(atPath: existingAncestor.path) {
            let parent = existingAncestor.deletingLastPathComponent()
            guard parent.path != existingAncestor.path else { throw SessionArchiveError.invalidDestination }
            existingAncestor = parent
        }
        guard let ancestorIdentity = FileIdentity.capture(path: existingAncestor.path),
              ancestorIdentity.isDirectory,
              !ancestorIdentity.isSymbolicLink,
              ancestorIdentity.canonicalPath == existingAncestor.path else {
            throw SessionArchiveError.invalidDestination
        }

        try manager.createDirectory(
            at: destinationDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        guard let destinationIdentity = FileIdentity.capture(path: destinationDirectory.path),
              destinationIdentity.isDirectory,
              !destinationIdentity.isSymbolicLink,
              ancestorIdentity.matchesCurrent(path: existingAncestor.path),
              isDescendantOrSame(destinationIdentity.canonicalPath, as: ancestorIdentity.canonicalPath) else {
            throw SessionArchiveError.invalidDestination
        }
        try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: destinationDirectory.path)
        let destinationDescriptor = open(destinationDirectory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard destinationDescriptor >= 0,
              let openedDestination = FileSnapshot.capture(descriptor: destinationDescriptor),
              openedDestination.isDirectory,
              openedDestination.matchesCurrentIdentity(destinationDirectory) else {
            if destinationDescriptor >= 0 { close(destinationDescriptor) }
            throw SessionArchiveError.invalidDestination
        }
        defer { close(destinationDescriptor) }

        let finalURL = destinationDirectory.appendingPathComponent(source.lastPathComponent + ".gz")
        let finalName = finalURL.lastPathComponent
        let existingFinalDescriptor = openat(destinationDescriptor, finalName, O_RDONLY | O_NOFOLLOW)
        if existingFinalDescriptor >= 0 {
            close(existingFinalDescriptor)
            throw SessionArchiveError.archiveAlreadyExists
        }
        guard errno == ENOENT else { throw SessionArchiveError.invalidDestination }
        let partialName = ".\(UUID().uuidString).partial.gz"
        let partialDescriptor = openat(
            destinationDescriptor,
            partialName,
            O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW,
            mode_t(0o600)
        )
        guard partialDescriptor >= 0 else {
            throw SessionArchiveError.compressionFailed
        }
        let output = FileHandle(fileDescriptor: partialDescriptor, closeOnDealloc: true)
        defer {
            try? output.close()
            unlinkat(destinationDescriptor, partialName, 0)
        }

        let compressor = Process()
        compressor.executableURL = URL(fileURLWithPath: "/usr/bin/gzip")
        compressor.arguments = ["-c"]
        compressor.standardInput = input
        compressor.standardOutput = output
        compressor.standardError = FileHandle.nullDevice
        try run(compressor, timeout: 1_800, failure: .compressionFailed)
        try output.synchronize()
        try output.close()

        guard original.matchesDescriptor(sourceDescriptor), original.matchesCurrent(source) else {
            throw SessionArchiveError.sourceChanged
        }

        let verificationDescriptor = openat(destinationDescriptor, partialName, O_RDONLY | O_NOFOLLOW)
        guard verificationDescriptor >= 0 else { throw SessionArchiveError.verificationFailed }
        let verificationInput = FileHandle(fileDescriptor: verificationDescriptor, closeOnDealloc: true)
        defer { try? verificationInput.close() }
        let verifier = Process()
        verifier.executableURL = URL(fileURLWithPath: "/usr/bin/gzip")
        verifier.arguments = ["-t"]
        verifier.standardInput = verificationInput
        verifier.standardOutput = FileHandle.nullDevice
        verifier.standardError = FileHandle.nullDevice
        try run(verifier, timeout: 300, failure: .verificationFailed)

        guard original.matchesDescriptor(sourceDescriptor),
              original.matchesCurrent(source),
              openedDestination.matchesDescriptorIdentity(destinationDescriptor),
              openedDestination.matchesCurrentIdentity(destinationDirectory) else {
            throw SessionArchiveError.sourceChanged
        }
        guard renameatx_np(
            destinationDescriptor,
            partialName,
            destinationDescriptor,
            finalName,
            UInt32(RENAME_EXCL)
        ) == 0 else {
            if errno == EEXIST { throw SessionArchiveError.archiveAlreadyExists }
            throw SessionArchiveError.invalidDestination
        }
        guard openedDestination.matchesDescriptorIdentity(destinationDescriptor),
              openedDestination.matchesCurrentIdentity(destinationDirectory) else {
            unlinkat(destinationDescriptor, finalName, 0)
            throw SessionArchiveError.invalidDestination
        }
        let finalDescriptor = openat(destinationDescriptor, finalName, O_RDONLY | O_NOFOLLOW)
        guard finalDescriptor >= 0 else { throw SessionArchiveError.invalidDestination }
        defer { close(finalDescriptor) }
        guard fchmod(finalDescriptor, mode_t(0o600)) == 0 else {
            unlinkat(destinationDescriptor, finalName, 0)
            throw SessionArchiveError.invalidDestination
        }
        return finalURL
    }

    private func run(_ process: Process, timeout: TimeInterval, failure: SessionArchiveError) throws {
        do {
            try process.run()
        } catch {
            throw failure
        }
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning {
            if Task.isCancelled || Date() >= deadline {
                process.terminate()
                process.waitUntilExit()
                throw failure
            }
            usleep(20_000)
        }
        guard process.terminationStatus == 0 else { throw failure }
    }

    private func isDescendantOrSame(_ path: String, as root: String) -> Bool {
        guard path != root else { return true }
        let rootWithSlash = root.hasSuffix("/") ? root : root + "/"
        return path.hasPrefix(rootWithSlash)
    }

    private func securityNormalizedPath(_ path: String) -> String {
        for (alias, canonical) in [("/var", "/private/var"), ("/tmp", "/private/tmp"), ("/etc", "/private/etc")] {
            if path == alias { return canonical }
            if path.hasPrefix(alias + "/") { return canonical + path.dropFirst(alias.count) }
        }
        return path
    }
}

public struct SessionTrashMover: Sendable {
    private let trashDirectory: @Sendable (URL) throws -> URL
    private let checkpoint: @Sendable (String, URL) throws -> Void

    public init() {
        self.trashDirectory = { _ in
            try FileManager.default.url(for: .trashDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        }
        self.checkpoint = { _, _ in }
    }

    init(trashDirectory: @escaping @Sendable (URL) throws -> URL,
         checkpoint: @escaping @Sendable (String, URL) throws -> Void = { _, _ in }) {
        self.trashDirectory = trashDirectory
        self.checkpoint = checkpoint
    }

    public func moveValidatedFileToTrash(source: URL, scannedIdentity: FileIdentity,
                                        reviewedFingerprint: SessionFileFingerprint? = nil) throws {
        let source = source.standardizedFileURL
        let parent = source.deletingLastPathComponent()
        let sourceName = source.lastPathComponent
        guard !sourceName.isEmpty, sourceName != ".", sourceName != ".." else {
            throw SessionTrashError.invalidSource
        }

        guard let parentIdentity = FileIdentity.capture(path: parent.path), !parentIdentity.isSymbolicLink else {
            throw SessionTrashError.stagingFailed
        }
        let parentDescriptor = open(parent.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard parentDescriptor >= 0,
              let parentSnapshot = FileSnapshot.capture(descriptor: parentDescriptor),
              parentSnapshot.isDirectory,
              parentSnapshot.matchesCurrentIdentity(parent), parentIdentity.matchesCurrent(path: parent.path) else {
            if parentDescriptor >= 0 { close(parentDescriptor) }
            throw SessionTrashError.stagingFailed
        }
        defer { close(parentDescriptor) }

        let sourceDescriptor = openat(parentDescriptor, sourceName, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard sourceDescriptor >= 0 else { throw SessionTrashError.invalidSource }
        defer { close(sourceDescriptor) }
        guard let openedSource = FileSnapshot.capture(descriptor: sourceDescriptor),
              openedSource.isRegularFile || openedSource.isDirectory,
              openedSource.matches(identity: scannedIdentity),
              scannedIdentity.matchesCurrent(path: source.path),
              reviewedFingerprint.map({ $0.matches(openedSource) }) ?? true else {
            throw SessionTrashError.sourceChanged
        }

        let trash = try trashDirectory(source).standardizedFileURL
        guard let trashIdentity = FileIdentity.capture(path: trash.path), !trashIdentity.isSymbolicLink else {
            throw SessionTrashError.stagingFailed
        }
        let trashDescriptor = open(trash.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard trashDescriptor >= 0,
              let trashSnapshot = FileSnapshot.capture(descriptor: trashDescriptor),
              trashSnapshot.isDirectory, trashSnapshot.matchesCurrentIdentity(trash),
              trashSnapshot.device == openedSource.device else {
            if trashDescriptor >= 0 { close(trashDescriptor) }
            throw SessionTrashError.stagingFailed
        }
        defer { close(trashDescriptor) }
        let stagingName = ".ryddi-trash-\(UUID().uuidString)"
        guard mkdirat(parentDescriptor, stagingName, mode_t(0o700)) == 0 else {
            throw SessionTrashError.stagingFailed
        }
        let stagingDescriptor = openat(parentDescriptor, stagingName, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard stagingDescriptor >= 0 else { throw SessionTrashError.stagingFailed }
        defer {
            let current = openat(parentDescriptor, stagingName, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
            if current >= 0 {
                if let staged = FileSnapshot.capture(descriptor: stagingDescriptor), staged.matchesDescriptorIdentity(current) {
                    unlinkat(parentDescriptor, stagingName, AT_REMOVEDIR)
                }
                close(current)
            }
            close(stagingDescriptor)
        }
        let stagedURL = parent.appendingPathComponent(stagingName).appendingPathComponent(sourceName)
        try checkpoint("opened", source)
        guard parentSnapshot.matchesDescriptorIdentity(parentDescriptor),
              parentSnapshot.matchesCurrentIdentity(parent),
              parentIdentity.matchesCurrent(path: parent.path),
              openedSource.matchesDescriptor(sourceDescriptor),
              openedSource.matchesCurrent(source),
              renameatx_np(parentDescriptor, sourceName, stagingDescriptor, sourceName, UInt32(RENAME_EXCL)) == 0 else {
            throw SessionTrashError.stagingFailed
        }

        func retain(_ descriptor: Int32, _ name: String) -> SessionTrashError {
            func location(_ fd: Int32, _ child: String? = nil) -> SessionTrashError {
                guard let url = descriptorPath(fd) else { return .locationUnknown }
                return .retained(child.map { url.appendingPathComponent($0).path } ?? url.path)
            }
            let current = openat(descriptor, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
            guard current >= 0 else { return location(sourceDescriptor) }
            defer { close(current) }
            guard openedSource.matchesDescriptorIdentity(current) else {
                return location(sourceDescriptor)
            }
            if renameatx_np(descriptor, name, parentDescriptor, sourceName, UInt32(RENAME_EXCL)) == 0 {
                return location(parentDescriptor, sourceName)
            }
            return location(descriptor, name)
        }

        do {
            try checkpoint("staged", stagedURL)
            guard openedSource.matchesDescriptor(sourceDescriptor),
                  openedSource.matchesCurrent(stagedURL),
                  parentSnapshot.matchesCurrentIdentity(parent),
                  parentIdentity.matchesCurrent(path: parent.path),
                  trashSnapshot.matchesCurrentIdentity(trash), trashIdentity.matchesCurrent(path: trash.path) else {
                throw SessionTrashError.sourceChanged
            }
            try Task.checkCancellation()
        } catch {
            throw retain(stagingDescriptor, sourceName)
        }
        let trashName = sourceName + ".ryddi-" + UUID().uuidString
        guard renameatx_np(stagingDescriptor, sourceName, trashDescriptor, trashName, UInt32(RENAME_EXCL)) == 0 else {
            throw retain(stagingDescriptor, sourceName)
        }
        do {
            try checkpoint("trashed", trash.appendingPathComponent(trashName))
            let received = openat(trashDescriptor, trashName, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
            guard received >= 0 else { throw SessionTrashError.trashFailed }
            defer { close(received) }
            guard openedSource.matchesDescriptor(received),
                  parentSnapshot.matchesCurrentIdentity(parent),
                  parentIdentity.matchesCurrent(path: parent.path),
                  trashSnapshot.matchesCurrentIdentity(trash), trashIdentity.matchesCurrent(path: trash.path) else {
                throw SessionTrashError.sourceChanged
            }
        } catch {
            throw retain(trashDescriptor, trashName)
        }
    }
}

public struct SessionFileFingerprint: Sendable, Hashable {
    public let identity: FileIdentity
    public let sizeBytes: Int64
    public let modifiedSeconds: Int
    public let modifiedNanoseconds: Int

    public static func capture(path: String) -> Self? {
        guard let snapshot = FileSnapshot.capture(URL(fileURLWithPath: path)), snapshot.isRegularFile,
              let identity = FileIdentity.capture(path: path), snapshot.matches(identity: identity) else { return nil }
        return Self(identity: identity, sizeBytes: snapshot.sizeBytes,
                    modifiedSeconds: snapshot.modifiedSeconds, modifiedNanoseconds: snapshot.modifiedNanoseconds)
    }

    public func matchesCurrent(path: String) -> Bool { Self.capture(path: path) == self }

    fileprivate func matches(_ snapshot: FileSnapshot) -> Bool {
        snapshot.matches(identity: identity) && snapshot.sizeBytes == sizeBytes
            && snapshot.modifiedSeconds == modifiedSeconds && snapshot.modifiedNanoseconds == modifiedNanoseconds
    }
}

private func descriptorPath(_ descriptor: Int32) -> URL? {
    var path = [CChar](repeating: 0, count: Int(MAXPATHLEN))
    guard fcntl(descriptor, F_GETPATH, &path) == 0 else {
        return nil
    }
    return URL(fileURLWithPath: String(cString: path))
}

fileprivate struct FileSnapshot {
    let device: UInt64
    let inode: UInt64
    let sizeBytes: Int64
    let modifiedSeconds: Int
    let modifiedNanoseconds: Int
    let isRegularFile: Bool
    let isSymbolicLink: Bool
    let isDirectory: Bool

    static func capture(_ url: URL) -> FileSnapshot? {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { return nil }
        let kind = info.st_mode & S_IFMT
        return FileSnapshot(
            device: UInt64(info.st_dev),
            inode: UInt64(info.st_ino),
            sizeBytes: Int64(info.st_size),
            modifiedSeconds: info.st_mtimespec.tv_sec,
            modifiedNanoseconds: info.st_mtimespec.tv_nsec,
            isRegularFile: kind == S_IFREG,
            isSymbolicLink: kind == S_IFLNK,
            isDirectory: kind == S_IFDIR
        )
    }

    static func capture(descriptor: Int32) -> FileSnapshot? {
        var info = stat()
        guard fstat(descriptor, &info) == 0 else { return nil }
        let kind = info.st_mode & S_IFMT
        return FileSnapshot(
            device: UInt64(info.st_dev),
            inode: UInt64(info.st_ino),
            sizeBytes: Int64(info.st_size),
            modifiedSeconds: info.st_mtimespec.tv_sec,
            modifiedNanoseconds: info.st_mtimespec.tv_nsec,
            isRegularFile: kind == S_IFREG,
            isSymbolicLink: kind == S_IFLNK,
            isDirectory: kind == S_IFDIR
        )
    }

    func matchesCurrent(_ url: URL) -> Bool {
        guard let current = Self.capture(url) else { return false }
        return current.device == device
            && current.inode == inode
            && current.sizeBytes == sizeBytes
            && current.modifiedSeconds == modifiedSeconds
            && current.modifiedNanoseconds == modifiedNanoseconds
            && current.isRegularFile == isRegularFile
            && current.isDirectory == isDirectory
            && current.isSymbolicLink == isSymbolicLink
            && !current.isSymbolicLink
    }

    func matchesDescriptor(_ descriptor: Int32) -> Bool {
        guard let current = Self.capture(descriptor: descriptor) else { return false }
        return current.device == device
            && current.inode == inode
            && current.sizeBytes == sizeBytes
            && current.modifiedSeconds == modifiedSeconds
            && current.modifiedNanoseconds == modifiedNanoseconds
            && current.isRegularFile == isRegularFile
            && current.isDirectory == isDirectory
    }

    func matchesCurrentIdentity(_ url: URL) -> Bool {
        guard let current = Self.capture(url) else { return false }
        return current.device == device
            && current.inode == inode
            && current.isRegularFile == isRegularFile
            && current.isDirectory == isDirectory
            && !current.isSymbolicLink
    }

    func matchesDescriptorIdentity(_ descriptor: Int32) -> Bool {
        guard let current = Self.capture(descriptor: descriptor) else { return false }
        return current.device == device
            && current.inode == inode
            && current.isRegularFile == isRegularFile
            && current.isDirectory == isDirectory
    }

    func matches(identity: FileIdentity) -> Bool {
        device == identity.device && inode == identity.inode && isDirectory == identity.isDirectory && !isSymbolicLink
    }
}
