import Darwin
import Foundation

public enum IssuePackagePathStyle: String, Codable, Hashable, Sendable {
    case redacted
    case homeRelative = "home-relative"

    var reportPathStyle: ReportPathStyle {
        switch self {
        case .redacted:
            .redacted
        case .homeRelative:
            .homeRelative
        }
    }
}

public struct IssuePackageManifest: Codable, Hashable, Sendable {
    public let createdAt: Date
    public let appVersion: String
    public let pathStyle: IssuePackagePathStyle
    public let includedFiles: [String]
    public let nonClaims: [String]

    public init(
        createdAt: Date,
        appVersion: String,
        pathStyle: IssuePackagePathStyle,
        includedFiles: [String],
        nonClaims: [String]
    ) {
        self.createdAt = createdAt
        self.appVersion = appVersion
        self.pathStyle = pathStyle
        self.includedFiles = includedFiles
        self.nonClaims = nonClaims
    }
}

public struct IssuePackageLocalSummary: Codable, Hashable, Sendable {
    public let auditRoot: String
    public let totalKnownFileCount: Int
    public let totalKnownBytes: Int64
    public let unknownFileCount: Int
    public let symlinkCount: Int
    public let latestScanSession: ScanSession?
    public let auditItems: [AuditStoreSummaryItem]

    public init(auditSummary: AuditStoreSummary, latestScanSession: ScanSession?, privacy: ReportPrivacyOptions) {
        self.auditRoot = privacy.displayText(auditSummary.rootPath, knownPaths: [auditSummary.rootPath])
        self.totalKnownFileCount = auditSummary.totalKnownFileCount
        self.totalKnownBytes = auditSummary.totalKnownBytes
        self.unknownFileCount = auditSummary.unknownFileCount
        self.symlinkCount = auditSummary.symlinkCount
        self.latestScanSession = latestScanSession
        self.auditItems = auditSummary.items
    }
}

public struct IssuePackageRemoteFindingSummary: Codable, Hashable, Sendable {
    public let bucket: String
    public let displayPath: String
    public let allocatedBytes: Int64?
    public let safetyClass: SafetyClass
    public let nextAction: ReviewNextAction
}

public struct IssuePackageRemoteSummary: Codable, Hashable, Sendable {
    public let scanID: String
    public let target: String
    public let host: String
    public let coverageLevel: RemoteScanCoverageLevel
    public let findingCount: Int
    public let totalFindingBytes: Int64
    public let topFindings: [IssuePackageRemoteFindingSummary]
    public let commandCards: [RemoteManualCommandCard]
    public let commandPreviews: [String]
    public let nonClaims: [String]

    public init(scan: RemoteScanReport, privacy: ReportPrivacyOptions, pathStyle: IssuePackagePathStyle, limit: Int = 20) {
        let findingPaths = scan.findings.flatMap { [$0.remotePath, $0.displayPath] }
        let redactor = RemotePrivacyRedactor(
            privacy: privacy,
            target: scan.target,
            additionalSensitiveValues: findingPaths
        )
        self.scanID = scan.id
        self.target = redactor.targetLabel()
        self.host = redactor.host()
        self.coverageLevel = scan.coverage.level
        self.findingCount = scan.findings.count
        self.totalFindingBytes = scan.findings.reduce(Int64(0)) { $0 + ($1.allocatedBytes ?? 0) }
        self.topFindings = scan.findings
            .sorted { ($0.allocatedBytes ?? 0) > ($1.allocatedBytes ?? 0) }
            .prefix(limit)
            .map {
                IssuePackageRemoteFindingSummary(
                    bucket: $0.bucket,
                    displayPath: redactor.path($0.remotePath),
                    allocatedBytes: $0.allocatedBytes,
                    safetyClass: $0.safetyClass,
                    nextAction: $0.recommendedNextAction
                )
            }
        self.commandCards = scan.commandCards.map(redactor.commandCard)
        self.commandPreviews = scan.commands
            .prefix(10)
            .flatMap { command in
                (command.stdoutPreview.prefix(2) + command.stderrPreview.prefix(2)).map {
                    redactor.text($0, knownPaths: findingPaths)
                }
            }
        self.nonClaims = scan.nonClaims
    }
}

public struct IssuePackageExportOptions: Codable, Hashable, Sendable {
    public let pathStyle: IssuePackagePathStyle
    public let includeLatestRemoteReport: Bool
    public let replaceExisting: Bool
    public let appVersion: String
    public let createdAt: Date

    public init(
        pathStyle: IssuePackagePathStyle = .redacted,
        includeLatestRemoteReport: Bool = false,
        replaceExisting: Bool = false,
        appVersion: String = "source",
        createdAt: Date = Date()
    ) {
        self.pathStyle = pathStyle
        self.includeLatestRemoteReport = includeLatestRemoteReport
        self.replaceExisting = replaceExisting
        self.appVersion = appVersion
        self.createdAt = createdAt
    }
}

public enum IssuePackageExportError: Error, LocalizedError, Equatable {
    case outputExistsAndIsNotDirectory(String)
    case outputDirectoryNotEmpty(String)
    case protectedOutputDirectory(String)
    case unsafeReplacement(String, String)
    case unsafeOutputPath(String, String)
    case outputEntryAlreadyExists(String)
    case outputWriteFailed(String, String)

    public var errorDescription: String? {
        switch self {
        case .outputExistsAndIsNotDirectory(let path):
            "Issue package output exists and is not a directory: \(path)"
        case .outputDirectoryNotEmpty(let path):
            "Issue package output directory is not empty; choose an empty output directory: \(path)"
        case .protectedOutputDirectory(let path):
            "Issue package output is a protected path and cannot be used: \(path)"
        case .unsafeReplacement(let path, let reason):
            "Issue package replacement rejected at \(path): \(reason)"
        case .unsafeOutputPath(let path, let reason):
            "Issue package output rejected at \(path): \(reason)"
        case .outputEntryAlreadyExists(let name):
            "Issue package output entry already exists: \(name)"
        case .outputWriteFailed(let name, let reason):
            "Issue package output write failed for \(name): \(reason)"
        }
    }
}

/// Holds a directory descriptor after validating it. Every package file is created with
/// `openat` relative to this descriptor, so later pathname swaps cannot redirect writes.
private final class BoundIssuePackageOutputDirectory {
    private let descriptor: Int32

    private init(descriptor: Int32) {
        self.descriptor = descriptor
    }

    deinit {
        Darwin.close(descriptor)
    }

    static func open(at requestedOutput: URL, replace: Bool) throws -> BoundIssuePackageOutputDirectory {
        let rawOutput = requestedOutput.standardizedFileURL
        guard !replace else {
            throw IssuePackageExportError.unsafeReplacement(
                rawOutput.path,
                "--replace is disabled because package entries cannot be safely unlinked or overwritten"
            )
        }

        try rejectFinalSymbolicLink(at: rawOutput)
        let outputPath = try outputWithCanonicalParent(rawOutput)
        let components = outputPath.split(separator: "/").map(String.init)
        guard let leaf = components.last, !leaf.isEmpty else {
            throw IssuePackageExportError.unsafeOutputPath(outputPath, "an ordinary output directory is required")
        }

        var parentDescriptor = Darwin.open("/", O_RDONLY | O_DIRECTORY)
        guard parentDescriptor >= 0 else {
            throw IssuePackageExportError.unsafeOutputPath(outputPath, errnoDescription())
        }
        defer { Darwin.close(parentDescriptor) }

        for component in components.dropLast() {
            let nextDescriptor = try openDirectory(named: component, relativeTo: parentDescriptor, outputPath: outputPath)
            Darwin.close(parentDescriptor)
            parentDescriptor = nextDescriptor
        }

        var initialStatus = Darwin.stat()
        let result = leaf.withCString {
            Darwin.fstatat(parentDescriptor, $0, &initialStatus, AT_SYMLINK_NOFOLLOW)
        }
        if result == 0 {
            guard isDirectory(initialStatus) else {
                throw IssuePackageExportError.outputExistsAndIsNotDirectory(outputPath)
            }
            let boundDescriptor = try openDirectory(named: leaf, relativeTo: parentDescriptor, outputPath: outputPath)
            do {
                var boundStatus = Darwin.stat()
                guard Darwin.fstat(boundDescriptor, &boundStatus) == 0,
                      sameIdentity(initialStatus, boundStatus) else {
                    throw IssuePackageExportError.unsafeOutputPath(
                        outputPath,
                        "the output directory changed while it was being opened"
                    )
                }
                guard try directoryIsEmpty(boundDescriptor) else {
                    throw IssuePackageExportError.outputDirectoryNotEmpty(outputPath)
                }
                return BoundIssuePackageOutputDirectory(descriptor: boundDescriptor)
            } catch {
                Darwin.close(boundDescriptor)
                throw error
            }
        }

        let lookupErrno = errno
        guard lookupErrno == ENOENT else {
            throw IssuePackageExportError.unsafeOutputPath(outputPath, errnoDescription(lookupErrno))
        }
        let createResult = leaf.withCString {
            Darwin.mkdirat(parentDescriptor, $0, 0o700)
        }
        guard createResult == 0 else {
            let createErrno = errno
            if createErrno == EEXIST {
                throw IssuePackageExportError.unsafeOutputPath(
                    outputPath,
                    "the output directory appeared during creation; choose a new empty directory"
                )
            }
            throw IssuePackageExportError.unsafeOutputPath(outputPath, errnoDescription(createErrno))
        }

        let boundDescriptor = try openDirectory(named: leaf, relativeTo: parentDescriptor, outputPath: outputPath)
        return BoundIssuePackageOutputDirectory(descriptor: boundDescriptor)
    }

    func write(_ data: Data, named name: String) throws {
        guard Self.isSafeEntryName(name) else {
            throw IssuePackageExportError.unsafeOutputPath(name, "package entry names must be simple file names")
        }
        let entryDescriptor = name.withCString {
            Darwin.openat(descriptor, $0, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        }
        guard entryDescriptor >= 0 else {
            let writeErrno = errno
            if writeErrno == EEXIST {
                throw IssuePackageExportError.outputEntryAlreadyExists(name)
            }
            throw IssuePackageExportError.outputWriteFailed(name, Self.errnoDescription(writeErrno))
        }
        defer { Darwin.close(entryDescriptor) }

        try data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) throws in
            var offset = 0
            while offset < buffer.count {
                guard let baseAddress = buffer.baseAddress else { break }
                let written = Darwin.write(entryDescriptor, baseAddress.advanced(by: offset), buffer.count - offset)
                if written > 0 {
                    offset += Int(written)
                    continue
                }
                if written < 0, errno == EINTR {
                    continue
                }
                throw IssuePackageExportError.outputWriteFailed(name, Self.errnoDescription())
            }
        }
        guard Darwin.fsync(entryDescriptor) == 0 else {
            throw IssuePackageExportError.outputWriteFailed(name, Self.errnoDescription())
        }
    }

    private static func rejectFinalSymbolicLink(at output: URL) throws {
        var status = Darwin.stat()
        let result = output.path.withCString { Darwin.lstat($0, &status) }
        guard result != 0 || !isSymbolicLink(status) else {
            throw IssuePackageExportError.unsafeOutputPath(output.path, "the output directory itself must not be a symbolic link")
        }
    }

    private static func outputWithCanonicalParent(_ output: URL) throws -> String {
        let parent = output.deletingLastPathComponent().standardizedFileURL
        guard let resolvedParent = parent.path.withCString({ Darwin.realpath($0, nil) }) else {
            throw IssuePackageExportError.unsafeOutputPath(output.path, "the output parent must already exist: \(errnoDescription())")
        }
        defer { Darwin.free(resolvedParent) }
        let parentPath = String(cString: resolvedParent)
        return parentPath == "/" ? "/\(output.lastPathComponent)" : "\(parentPath)/\(output.lastPathComponent)"
    }

    private static func openDirectory(named name: String, relativeTo parentDescriptor: Int32, outputPath: String) throws -> Int32 {
        let descriptor = name.withCString {
            Darwin.openat(parentDescriptor, $0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        }
        guard descriptor >= 0 else {
            throw IssuePackageExportError.unsafeOutputPath(outputPath, "\(errnoDescription()) while opening \(name)")
        }
        return descriptor
    }

    private static func directoryIsEmpty(_ descriptor: Int32) throws -> Bool {
        let scanDescriptor = Darwin.dup(descriptor)
        guard scanDescriptor >= 0 else {
            throw IssuePackageExportError.unsafeOutputPath("/dev/fd/\(descriptor)", errnoDescription())
        }
        guard let directory = Darwin.fdopendir(scanDescriptor) else {
            Darwin.close(scanDescriptor)
            throw IssuePackageExportError.unsafeOutputPath("/dev/fd/\(descriptor)", errnoDescription())
        }
        defer { Darwin.closedir(directory) }

        while let entry = Darwin.readdir(directory) {
            let name = withUnsafePointer(to: entry.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(entry.pointee.d_namlen) + 1) {
                    String(cString: $0)
                }
            }
            if name != "." && name != ".." {
                return false
            }
        }
        return true
    }

    private static func isSafeEntryName(_ name: String) -> Bool {
        !name.isEmpty && !name.contains("/") && name != "." && name != ".."
    }

    private static func isDirectory(_ status: Darwin.stat) -> Bool {
        (status.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR)
    }

    private static func isSymbolicLink(_ status: Darwin.stat) -> Bool {
        (status.st_mode & mode_t(S_IFMT)) == mode_t(S_IFLNK)
    }

    private static func sameIdentity(_ left: Darwin.stat, _ right: Darwin.stat) -> Bool {
        left.st_dev == right.st_dev && left.st_ino == right.st_ino
    }

    private static func errnoDescription(_ code: Int32 = errno) -> String {
        String(cString: Darwin.strerror(code))
    }
}

public enum IssuePackageExporter {
    public static let nonClaims = [
        "No cleanup was executed while creating this issue package.",
        "No secrets inventory was performed; review the package before sharing.",
        "Redaction is best-effort and may not remove every project, host, or object name.",
        "The package does not include raw SSH config, private keys, passwords, tokens, or arbitrary audit JSON."
    ]

    public static func export(
        to outputDirectory: URL,
        store: AuditStore = AuditStore(),
        options: IssuePackageExportOptions = IssuePackageExportOptions()
    ) throws -> IssuePackageManifest {
        try export(
            to: outputDirectory,
            store: store,
            options: options,
            beforeFirstWrite: nil
        )
    }

    static func export(
        to outputDirectory: URL,
        store: AuditStore = AuditStore(),
        options: IssuePackageExportOptions = IssuePackageExportOptions(),
        beforeFirstWrite: (() throws -> Void)?
    ) throws -> IssuePackageManifest {
        let output = outputDirectory.standardizedFileURL
        guard !isProtectedOutputDirectory(output) else {
            throw IssuePackageExportError.protectedOutputDirectory(output.path)
        }
        let directory = try BoundIssuePackageOutputDirectory.open(at: output, replace: options.replaceExisting)

        let privacy = ReportPrivacyOptions(
            pathStyle: options.pathStyle.reportPathStyle,
            redactUserText: options.pathStyle == .redacted
        )
        let localSummary = IssuePackageLocalSummary(
            auditSummary: store.summary(),
            latestScanSession: try store.latestScanSession(),
            privacy: privacy
        )
        let remoteSummary = options.includeLatestRemoteReport
            ? store.recentRemoteScanReports(limit: 1).first.map {
                IssuePackageRemoteSummary(scan: $0, privacy: privacy, pathStyle: options.pathStyle)
            }
            : nil

        try beforeFirstWrite?()

        var includedFiles: [String] = []
        try writeMarkdown(reportMarkdown(localSummary: localSummary, remoteSummary: remoteSummary, options: options), named: "report.md", to: directory, includedFiles: &includedFiles)
        try writeMarkdown(nonClaimsMarkdown(), named: "non-claims.md", to: directory, includedFiles: &includedFiles)
        try writeJSON(localSummary, named: "local-summary.json", to: directory, includedFiles: &includedFiles)
        if let remoteSummary {
            try writeJSON(remoteSummary, named: "remote-summary.json", to: directory, includedFiles: &includedFiles)
        }

        let manifest = IssuePackageManifest(
            createdAt: options.createdAt,
            appVersion: options.appVersion,
            pathStyle: options.pathStyle,
            includedFiles: (includedFiles + ["manifest.json"]).sorted(),
            nonClaims: nonClaims
        )
        try writeJSON(manifest, named: "manifest.json", to: directory, includedFiles: &includedFiles)
        return manifest
    }

    private static func isProtectedOutputDirectory(_ output: URL) -> Bool {
        let path = output.standardizedFileURL.path
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        let protectedExactPaths: Set<String> = [
            "/",
            home,
            "/Users",
            "/Volumes",
            "/Network",
            "/private",
            "/tmp",
            "/var",
            "/opt",
            "/dev",
            "/cores"
        ]
        if protectedExactPaths.contains(path) {
            return true
        }

        let protectedTrees = ["/Applications", "/Library", "/System", "/bin", "/sbin", "/usr", "/etc"]
        return protectedTrees.contains { root in
            path == root || path.hasPrefix(root + "/")
        }
    }

    private static func reportMarkdown(
        localSummary: IssuePackageLocalSummary,
        remoteSummary: IssuePackageRemoteSummary?,
        options: IssuePackageExportOptions
    ) -> String {
        var lines: [String] = []
        lines.append("# Ryddi Issue Package")
        lines.append("")
        lines.append("- App version: \(MarkdownTable.cell(options.appVersion))")
        lines.append("- Path style: \(options.pathStyle.rawValue)")
        lines.append("- Audit root: \(MarkdownTable.cell(localSummary.auditRoot))")
        lines.append("- Audit files: \(localSummary.totalKnownFileCount)")
        lines.append("- Audit bytes: \(ByteFormat.string(localSummary.totalKnownBytes))")
        if let session = localSummary.latestScanSession {
            lines.append("- Latest scan session: \(session.id) (\(session.stage.rawValue))")
        } else {
            lines.append("- Latest scan session: none")
        }
        if let remoteSummary {
            lines.append("")
            lines.append("## Remote Summary")
            lines.append("")
            lines.append("- Remote scan: \(remoteSummary.scanID)")
            lines.append("- Target: \(MarkdownTable.cell(remoteSummary.target))")
            lines.append("- Host: \(MarkdownTable.cell(remoteSummary.host))")
            lines.append("- Coverage: \(remoteSummary.coverageLevel.rawValue)")
            lines.append("- Findings: \(remoteSummary.findingCount)")
            lines.append("- Finding bytes: \(ByteFormat.string(remoteSummary.totalFindingBytes))")
            if !remoteSummary.topFindings.isEmpty {
                lines.append("")
                lines.append("| Bucket | Path | Size | Safety |")
                lines.append("| --- | --- | ---: | --- |")
                for finding in remoteSummary.topFindings.prefix(10) {
                    let row = [
                        finding.bucket,
                        finding.displayPath,
                        finding.allocatedBytes.map(ByteFormat.string) ?? "-",
                        finding.safetyClass.label
                    ].map(MarkdownTable.cell)
                    lines.append("| \(row.joined(separator: " | ")) |")
                }
            }
            if !remoteSummary.commandPreviews.isEmpty {
                lines.append("")
                lines.append("### Command Preview Lines")
                lines.append("")
                for preview in remoteSummary.commandPreviews.prefix(10) {
                    lines.append("- \(MarkdownTable.cell(preview))")
                }
            }
        }
        lines.append("")
        lines.append("## Non-Claims")
        lines.append(contentsOf: nonClaims.map { "- \($0)" })
        lines.append("")
        return lines.joined(separator: "\n")
    }

    private static func nonClaimsMarkdown() -> String {
        (["# Ryddi Issue Package Non-Claims", ""] + nonClaims.map { "- \($0)" }).joined(separator: "\n")
    }

    private static func writeMarkdown(_ markdown: String, named name: String, to directory: BoundIssuePackageOutputDirectory, includedFiles: inout [String]) throws {
        try directory.write(Data(markdown.utf8), named: name)
        includedFiles.append(name)
    }

    private static func writeJSON<T: Encodable>(_ value: T, named name: String, to directory: BoundIssuePackageOutputDirectory, includedFiles: inout [String]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try directory.write(try encoder.encode(value), named: name)
        if name != "manifest.json" {
            includedFiles.append(name)
        }
    }
}
