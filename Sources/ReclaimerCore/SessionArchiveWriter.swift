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

public struct SessionArchiveWriter: Sendable {
    public init() {}

    public func writeVerifiedArchive(source: URL, destinationDirectory: URL) throws -> URL {
        let manager = FileManager.default
        let source = source.standardizedFileURL
        guard let original = FileSnapshot.capture(source), original.isRegularFile, !original.isSymbolicLink else {
            throw SessionArchiveError.invalidSource
        }

        let values = try manager.homeDirectoryForCurrentUser.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey]
        )
        let available = Int64(values.volumeAvailableCapacityForImportantUsage ?? 0)
        guard available > original.sizeBytes + 536_870_912 else {
            throw SessionArchiveError.insufficientSpace
        }

        var existingAncestor = destinationDirectory.standardizedFileURL
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

        let finalURL = destinationDirectory.appendingPathComponent(source.lastPathComponent + ".gz")
        guard !manager.fileExists(atPath: finalURL.path) else {
            throw SessionArchiveError.archiveAlreadyExists
        }
        let partialURL = destinationDirectory.appendingPathComponent(".\(UUID().uuidString).partial.gz")
        guard manager.createFile(atPath: partialURL.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
            throw SessionArchiveError.compressionFailed
        }
        defer {
            if manager.fileExists(atPath: partialURL.path) {
                try? manager.removeItem(at: partialURL)
            }
        }

        let output = try FileHandle(forWritingTo: partialURL)
        defer { try? output.close() }
        let compressor = Process()
        compressor.executableURL = URL(fileURLWithPath: "/usr/bin/gzip")
        compressor.arguments = ["-c", "--", source.path]
        compressor.standardOutput = output
        compressor.standardError = FileHandle.nullDevice
        try run(compressor, timeout: 1_800, failure: .compressionFailed)
        try output.synchronize()

        guard original.matchesCurrent(source) else {
            throw SessionArchiveError.sourceChanged
        }

        let verifier = Process()
        verifier.executableURL = URL(fileURLWithPath: "/usr/bin/gzip")
        verifier.arguments = ["-t", "--", partialURL.path]
        verifier.standardOutput = FileHandle.nullDevice
        verifier.standardError = FileHandle.nullDevice
        try run(verifier, timeout: 300, failure: .verificationFailed)

        guard original.matchesCurrent(source) else {
            throw SessionArchiveError.sourceChanged
        }
        try manager.moveItem(at: partialURL, to: finalURL)
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: finalURL.path)
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
}

private struct FileSnapshot {
    let device: UInt64
    let inode: UInt64
    let sizeBytes: Int64
    let modifiedSeconds: Int
    let modifiedNanoseconds: Int
    let isRegularFile: Bool
    let isSymbolicLink: Bool

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
            isSymbolicLink: kind == S_IFLNK
        )
    }

    func matchesCurrent(_ url: URL) -> Bool {
        guard let current = Self.capture(url) else { return false }
        return current.device == device
            && current.inode == inode
            && current.sizeBytes == sizeBytes
            && current.modifiedSeconds == modifiedSeconds
            && current.modifiedNanoseconds == modifiedNanoseconds
            && current.isRegularFile
            && !current.isSymbolicLink
    }
}
