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
    public let nonClaims: [String]

    public init(scan: RemoteScanReport, privacy: ReportPrivacyOptions, pathStyle: IssuePackagePathStyle, limit: Int = 20) {
        self.scanID = scan.id
        self.target = pathStyle == .redacted ? "<target redacted>" : (scan.target.alias ?? scan.target.input)
        self.host = pathStyle == .redacted ? "<host redacted>" : (scan.target.resolvedHost ?? "unknown")
        self.coverageLevel = scan.coverage.level
        self.findingCount = scan.findings.count
        self.totalFindingBytes = scan.findings.reduce(Int64(0)) { $0 + ($1.allocatedBytes ?? 0) }
        self.topFindings = scan.findings
            .sorted { ($0.allocatedBytes ?? 0) > ($1.allocatedBytes ?? 0) }
            .prefix(limit)
            .map {
                IssuePackageRemoteFindingSummary(
                    bucket: $0.bucket,
                    displayPath: privacy.displayPath($0.remotePath),
                    allocatedBytes: $0.allocatedBytes,
                    safetyClass: $0.safetyClass,
                    nextAction: $0.recommendedNextAction
                )
            }
        self.commandCards = scan.commandCards
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

    public var errorDescription: String? {
        switch self {
        case .outputExistsAndIsNotDirectory(let path):
            "Issue package output exists and is not a directory: \(path)"
        case .outputDirectoryNotEmpty(let path):
            "Issue package output directory is not empty; pass --replace to overwrite: \(path)"
        }
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
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: output.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue else {
                throw IssuePackageExportError.outputExistsAndIsNotDirectory(output.path)
            }
            let existing = try fileManager.contentsOfDirectory(atPath: output.path)
            if !existing.isEmpty {
                guard replace else {
                    throw IssuePackageExportError.outputDirectoryNotEmpty(output.path)
                }
                try fileManager.removeItem(at: output)
            }
        }
        try fileManager.createDirectory(at: output, withIntermediateDirectories: true)
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
