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

    public var errorDescription: String? {
        switch self {
        case .outputExistsAndIsNotDirectory(let path):
            "Issue package output exists and is not a directory: \(path)"
        case .outputDirectoryNotEmpty(let path):
            "Issue package output directory is not empty; pass --replace to overwrite: \(path)"
        case .protectedOutputDirectory(let path):
            "Issue package output is a protected path and cannot be used: \(path)"
        case .unsafeReplacement(let path, let reason):
            "Issue package replacement rejected at \(path): \(reason)"
        }
    }
}

public enum IssuePackageExporter {
    private static let requiredPackageFiles: Set<String> = [
        "local-summary.json",
        "manifest.json",
        "non-claims.md",
        "report.md"
    ]
    private static let optionalPackageFiles: Set<String> = ["remote-summary.json"]

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
        let output = outputDirectory.standardizedFileURL
        try prepareOutputDirectory(output, replace: options.replaceExisting)

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

        var includedFiles: [String] = []
        try writeMarkdown(reportMarkdown(localSummary: localSummary, remoteSummary: remoteSummary, options: options), named: "report.md", to: output, includedFiles: &includedFiles)
        try writeMarkdown(nonClaimsMarkdown(), named: "non-claims.md", to: output, includedFiles: &includedFiles)
        try writeJSON(localSummary, named: "local-summary.json", to: output, includedFiles: &includedFiles)
        if let remoteSummary {
            try writeJSON(remoteSummary, named: "remote-summary.json", to: output, includedFiles: &includedFiles)
        }

        let manifest = IssuePackageManifest(
            createdAt: options.createdAt,
            appVersion: options.appVersion,
            pathStyle: options.pathStyle,
            includedFiles: (includedFiles + ["manifest.json"]).sorted(),
            nonClaims: nonClaims
        )
        try writeJSON(manifest, named: "manifest.json", to: output, includedFiles: &includedFiles)
        return manifest
    }

    private static func prepareOutputDirectory(_ output: URL, replace: Bool) throws {
        let fileManager = FileManager.default
        guard !isProtectedOutputDirectory(output) else {
            throw IssuePackageExportError.protectedOutputDirectory(output.path)
        }

        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: output.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue else {
                throw IssuePackageExportError.outputExistsAndIsNotDirectory(output.path)
            }
            let outputValues = try output.resourceValues(forKeys: replacementResourceKeys)
            guard outputValues.isDirectory == true,
                  outputValues.isSymbolicLink != true,
                  outputValues.isPackage != true,
                  outputValues.isVolume != true else {
                throw IssuePackageExportError.unsafeReplacement(
                    output.path,
                    "the output itself must be an ordinary directory, not a symlink, package, or mount point"
                )
            }
            let existing = try fileManager.contentsOfDirectory(
                at: output,
                includingPropertiesForKeys: Array(replacementResourceKeys)
            )
            if !existing.isEmpty {
                guard replace else {
                    throw IssuePackageExportError.outputDirectoryNotEmpty(output.path)
                }
                let ownedFiles = try validatedOwnedFiles(in: output, entries: existing)
                for file in ownedFiles {
                    try validateRegularPackageFile(file, output: output)
                    try removeRegularPackageFile(file, output: output)
                }
            }
        }
        try fileManager.createDirectory(at: output, withIntermediateDirectories: true)
    }

    private static var replacementResourceKeys: Set<URLResourceKey> {
        [
            .isDirectoryKey,
            .isPackageKey,
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .isVolumeKey
        ]
    }

    private static func validatedOwnedFiles(in output: URL, entries: [URL]) throws -> [URL] {
        let manifestURL = output.appendingPathComponent("manifest.json")
        guard entries.contains(where: { $0.lastPathComponent == "manifest.json" }) else {
            throw IssuePackageExportError.unsafeReplacement(
                output.path,
                "a valid manifest.json sentinel is required before --replace can remove package files"
            )
        }
        try validateRegularPackageFile(manifestURL, output: output)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest: IssuePackageManifest
        do {
            manifest = try decoder.decode(IssuePackageManifest.self, from: Data(contentsOf: manifestURL))
        } catch {
            throw IssuePackageExportError.unsafeReplacement(
                output.path,
                "manifest.json is not a valid Ryddi issue-package manifest"
            )
        }

        let listedFiles = Set(manifest.includedFiles)
        let allowedFiles = requiredPackageFiles.union(optionalPackageFiles)
        guard listedFiles.count == manifest.includedFiles.count,
              requiredPackageFiles.isSubset(of: listedFiles),
              listedFiles.isSubset(of: allowedFiles) else {
            throw IssuePackageExportError.unsafeReplacement(
                output.path,
                "manifest.json contains an invalid issue-package file inventory"
            )
        }

        let existingNames = Set(entries.map(\.lastPathComponent))
        guard existingNames == listedFiles else {
            let unknown = existingNames.subtracting(listedFiles).sorted()
            let detail = unknown.isEmpty
                ? "existing package files do not match the manifest.json inventory"
                : "unowned entries are present: \(unknown.joined(separator: ", "))"
            throw IssuePackageExportError.unsafeReplacement(output.path, detail)
        }

        for entry in entries {
            try validateRegularPackageFile(entry, output: output)
        }
        return entries.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private static func validateRegularPackageFile(_ file: URL, output: URL) throws {
        let values: URLResourceValues
        do {
            values = try file.resourceValues(forKeys: replacementResourceKeys)
        } catch {
            throw IssuePackageExportError.unsafeReplacement(
                output.path,
                "could not inspect package-owned file \(file.lastPathComponent)"
            )
        }
        guard values.isRegularFile == true,
              values.isSymbolicLink != true,
              values.isDirectory != true,
              values.isPackage != true,
              values.isVolume != true else {
            throw IssuePackageExportError.unsafeReplacement(
                output.path,
                "package-owned entry is not a regular file: \(file.lastPathComponent)"
            )
        }
    }

    private static func removeRegularPackageFile(_ file: URL, output: URL) throws {
        let result = file.withUnsafeFileSystemRepresentation { path in
            guard let path else { return Int32(-1) }
            return unlink(path)
        }
        guard result == 0 else {
            let message = String(cString: strerror(errno))
            throw IssuePackageExportError.unsafeReplacement(
                output.path,
                "could not remove package-owned regular file \(file.lastPathComponent): \(message)"
            )
        }
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

    private static func writeMarkdown(_ markdown: String, named name: String, to directory: URL, includedFiles: inout [String]) throws {
        try markdown.write(to: directory.appendingPathComponent(name), atomically: true, encoding: .utf8)
        includedFiles.append(name)
    }

    private static func writeJSON<T: Encodable>(_ value: T, named name: String, to directory: URL, includedFiles: inout [String]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(value).write(to: directory.appendingPathComponent(name), options: .atomic)
        if name != "manifest.json" {
            includedFiles.append(name)
        }
    }
}
