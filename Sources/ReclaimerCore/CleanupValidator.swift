import Foundation
import Darwin

public enum CleanupValidationError: LocalizedError, Equatable, Sendable {
    case notSelectedSafeItem
    case missingIdentity
    case changedIdentity
    case symbolicLink
    case openFiles
    case openFileCheckFailed
    case outsideReviewedRoot
    case classificationChanged
    case unsupportedAction

    public var errorDescription: String? {
        switch self {
        case .notSelectedSafeItem: "The item is no longer approved for cleanup."
        case .missingIdentity: "The scan did not capture a stable file identity. Scan again."
        case .changedIdentity: "The item changed since the scan. Scan again before cleaning."
        case .symbolicLink: "Symbolic links are review-only."
        case .openFiles: "The item is in use by a running process. Close the related app and scan again."
        case .openFileCheckFailed: "Ryddi could not prove that the item is unused. Scan again or review it manually."
        case .outsideReviewedRoot: "The item is outside the reviewed scan root."
        case .classificationChanged: "The item's safety classification changed. Scan again."
        case .unsupportedAction: "This action is guidance-only and cannot run directly."
        }
    }
}

public struct CleanupValidator: Sendable {
    public init() {}

    public func validate(_ item: ScanItem, ruleEngine: RuleEngine) throws -> URL {
        guard item.bucket == .safe, item.safetyClass == .autoSafe else {
            throw CleanupValidationError.notSelectedSafeItem
        }
        guard item.actionKind == .trash || item.actionKind == .deleteCache else {
            throw CleanupValidationError.unsupportedAction
        }
        guard let scannedIdentity = item.identity else {
            throw CleanupValidationError.missingIdentity
        }
        guard !scannedIdentity.isSymbolicLink else {
            throw CleanupValidationError.symbolicLink
        }
        guard isDescendant(scannedIdentity.canonicalPath, of: item.scanRoot) else {
            throw CleanupValidationError.outsideReviewedRoot
        }
        guard scannedIdentity.matchesCurrent(path: item.path) else {
            throw CleanupValidationError.changedIdentity
        }
        try requireNoOpenFiles(path: item.path, isDirectory: scannedIdentity.isDirectory)

        let current = ruleEngine.classify(
            path: item.path,
            isDirectory: scannedIdentity.isDirectory,
            isSymbolicLink: false
        )
        guard current.safetyClass == .autoSafe else {
            throw CleanupValidationError.classificationChanged
        }
        guard current.actionKind == .trash || current.actionKind == .deleteCache else {
            throw CleanupValidationError.unsupportedAction
        }
        guard scannedIdentity.matchesCurrent(path: item.path) else {
            throw CleanupValidationError.changedIdentity
        }
        return URL(fileURLWithPath: scannedIdentity.canonicalPath)
    }

    public func validate(_ recommendation: ReclaimRecommendation, scanRoot: String) throws -> URL {
        guard recommendation.safetyScore >= 0.8, recommendation.action == .moveToTrash else {
            throw CleanupValidationError.notSelectedSafeItem
        }
        guard let scannedIdentity = recommendation.identity else {
            throw CleanupValidationError.missingIdentity
        }
        guard !scannedIdentity.isSymbolicLink else {
            throw CleanupValidationError.symbolicLink
        }
        guard isDescendant(scannedIdentity.canonicalPath, of: scanRoot) else {
            throw CleanupValidationError.outsideReviewedRoot
        }
        guard scannedIdentity.matchesCurrent(path: recommendation.path) else {
            throw CleanupValidationError.changedIdentity
        }
        try requireNoOpenFiles(path: recommendation.path, isDirectory: scannedIdentity.isDirectory)

        let refreshed = SafetyChecker().check([recommendation], scanRoot: scanRoot)[0]
        guard refreshed.safetyScore >= 0.8, refreshed.action == .moveToTrash else {
            throw CleanupValidationError.classificationChanged
        }
        guard scannedIdentity.matchesCurrent(path: recommendation.path) else {
            throw CleanupValidationError.changedIdentity
        }
        return URL(fileURLWithPath: scannedIdentity.canonicalPath)
    }

    public func validateRecoverableDirectory(
        path: String,
        expectedPath: String,
        scannedIdentity: FileIdentity
    ) throws -> URL {
        guard scannedIdentity.isDirectory, !scannedIdentity.isSymbolicLink else {
            throw CleanupValidationError.symbolicLink
        }
        guard scannedIdentity.canonicalPath == canonicalizedPath(expectedPath) else {
            throw CleanupValidationError.outsideReviewedRoot
        }
        guard scannedIdentity.matchesCurrent(path: path) else {
            throw CleanupValidationError.changedIdentity
        }
        try requireNoOpenFiles(path: path, isDirectory: true)
        guard scannedIdentity.matchesCurrent(path: path) else {
            throw CleanupValidationError.changedIdentity
        }
        return URL(fileURLWithPath: scannedIdentity.canonicalPath)
    }

    private func isDescendant(_ path: String, of root: String) -> Bool {
        let candidate = URL(fileURLWithPath: canonicalizedPath(path)).pathComponents
        let parent = URL(fileURLWithPath: canonicalizedPath(root)).pathComponents
        return candidate.count > parent.count && Array(candidate.prefix(parent.count)) == parent
    }

    private func requireNoOpenFiles(path: String, isDirectory: Bool) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = isDirectory ? ["-Fn", "+D", path] : ["-Fn", "--", path]
        var outputTemplate = Array((NSTemporaryDirectory() + "ryddi-lsof.XXXXXX").utf8CString)
        let outputDescriptor = mkstemp(&outputTemplate)
        guard outputDescriptor >= 0 else {
            throw CleanupValidationError.openFileCheckFailed
        }
        let outputPath = String(
            decoding: outputTemplate.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) },
            as: UTF8.self
        )
        let output = FileHandle(fileDescriptor: outputDescriptor, closeOnDealloc: true)
        defer {
            try? output.close()
            unlink(outputPath)
        }
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            throw CleanupValidationError.openFileCheckFailed
        }

        let deadline = Date().addingTimeInterval(2)
        while process.isRunning && Date() < deadline {
            usleep(20_000)
        }
        if process.isRunning {
            process.terminate()
            process.waitUntilExit()
            throw CleanupValidationError.openFileCheckFailed
        }
        try? output.synchronize()
        var outputInfo = stat()
        guard fstat(outputDescriptor, &outputInfo) == 0 else {
            throw CleanupValidationError.openFileCheckFailed
        }
        if outputInfo.st_size > 0 {
            throw CleanupValidationError.openFiles
        }
        switch process.terminationStatus {
        case 0: return
        case 1: return
        default: throw CleanupValidationError.openFileCheckFailed
        }
    }
}
