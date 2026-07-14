import Foundation
import ReclaimerCore

extension ReclaimerCLI {
    static func overview(args: [String]) throws {
        let options = ParsedOptions(args)
        let scopes = try options.scopes(includeUnavailable: true)
        let scanner = try FileScanner(ruleEngine: try options.ruleEngine(), openFileChecker: options.noLsof ? NoOpenFilesChecker() : LsofOpenFileChecker())
        let result = scanner.scanWithCoverage(scopes: scopes, options: options.scanOptions(includeOpenFiles: options.includeOpenFiles))
        let overview = FindingAnalytics.overview(
            findings: result.findings,
            scopes: scopes,
            topLimit: options.limit,
            offenderSort: try options.topOffenderSort(),
            offenderGroup: try options.topOffenderGroup(),
            scopeAccessSummaries: result.coverage.scopeAccessSummaries
        ).withScanCoverage(result.coverage)
        if options.saveHistory {
            let url = try ScanHistoryStore().save(overview: overview)
            FileHandle.standardError.write(Data("saved scan snapshot: \(url.path)\n".utf8))
        }
        if options.json {
            printJSON(overview)
        } else {
            printOverview(overview)
        }
    }

    static func queues(args: [String]) throws {
        let options = ParsedOptions(args)
        let scopes = try options.scopes(includeUnavailable: true)
        let scanner = try FileScanner(ruleEngine: try options.ruleEngine(), openFileChecker: options.noLsof ? NoOpenFilesChecker() : LsofOpenFileChecker())
        let findings = scanner.scan(scopes: scopes, options: options.scanOptions(includeOpenFiles: options.includeOpenFiles))
        if let queueID = try options.reviewQueueID() {
            let detailReport = FindingAnalytics.reviewQueueDetailReport(
                findings: findings,
                queueID: queueID,
                limit: options.limit
            )
            if options.json {
                printJSON(detailReport)
            } else {
                printReviewQueueDetailReport(detailReport)
            }
            return
        }
        let report = FindingAnalytics.reviewQueueReport(
            findings: findings,
            limitPerQueue: options.limit
        )
        if options.json {
            printJSON(report)
        } else {
            printReviewQueueReport(report)
        }
    }

    static func large(args: [String]) throws {
        let options = ParsedOptions(args)
        let scopes = try options.scopes(includeUnavailable: true)
        let scanner = try FileScanner(ruleEngine: try options.ruleEngine(), openFileChecker: options.noLsof ? NoOpenFilesChecker() : LsofOpenFileChecker())
        let findings = scanner.scan(scopes: scopes, options: options.scanOptions(includeOpenFiles: options.includeOpenFiles))
        let report = FindingAnalytics.largeOldReviewReport(
            findings: findings,
            mode: try options.largeOldReviewMode(),
            sort: try options.topOffenderSort(),
            limit: options.limit
        )
        if options.json {
            printJSON(report)
        } else {
            printLargeOldReviewReport(report)
        }
    }

    static func drilldown(args: [String]) throws {
        let options = ParsedOptions(args)
        let scopes = try options.scopes(includeUnavailable: options.includeMissingScopes)
        let scanner = try FileScanner(ruleEngine: try options.ruleEngine(), openFileChecker: options.noLsof ? NoOpenFilesChecker() : LsofOpenFileChecker())
        let findings = scanner.scan(scopes: scopes, options: options.scanOptions(includeOpenFiles: false))
        let report = DiskDrillDownBuilder.build(
            findings: options.prepare(findings),
            scopes: scopes,
            maxDepth: options.drilldownDepth,
            childLimit: options.limit
        )
        if options.json {
            printJSON(report)
        } else {
            printDiskDrillDown(report)
        }
    }

    static func duplicates(args: [String]) throws {
        let options = ParsedOptions(args)
        guard options.hasPath else {
            throw CLIError.message("duplicates requires at least one explicit --path because it hashes file contents locally.")
        }
        let report = try DuplicateReviewScanner()
            .scan(scopes: try options.scopes(), options: options.duplicateOptions)
        if options.json {
            printJSON(report)
        } else {
            printDuplicateReview(report, options: options)
        }
    }

    static func downloads(args: [String]) throws {
        let options = ParsedOptions(args)
        let root = options.value(after: "--path")
            .map { URL(fileURLWithPath: $0).standardizedFileURL }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
        let measurementDepth = max(0, Int(options.value(after: "--max-depth") ?? "") ?? 6)
        let report = DownloadsReviewScanner().review(
            options: DownloadsReviewOptions(
                root: root,
                limit: options.limit,
                oldDays: options.oldDays,
                measurementDepth: measurementDepth,
                includeHidden: options.args.contains("--include-hidden")
            )
        )
        if options.saveAudit {
            let url = try AuditStore().save(downloadsReviewReport: report)
            FileHandle.standardError.write(Data("saved downloads review report: \(url.path)\n".utf8))
        }
        if options.json {
            printJSON(report)
        } else {
            printDownloadsReview(report, options: options)
        }
    }

    static func browsers(args: [String]) throws {
        let options = ParsedOptions(args)
        let home = options.value(after: "--home")
            .map { URL(fileURLWithPath: $0).standardizedFileURL }
            ?? FileManager.default.homeDirectoryForCurrentUser
        let roots = options.values(after: "--path").map { URL(fileURLWithPath: $0).standardizedFileURL }
        let measurementDepth = max(0, Int(options.value(after: "--max-depth") ?? "") ?? 7)
        let report = BrowserCacheReviewScanner().review(
            options: BrowserCacheReviewOptions(
                home: home,
                roots: roots.isEmpty ? nil : roots,
                limit: options.limit,
                measurementDepth: measurementDepth,
                includeMissingRoots: options.includeMissingScopes
            )
        )
        if options.saveAudit {
            let url = try AuditStore().save(browserCacheReviewReport: report)
            FileHandle.standardError.write(Data("saved browser cache review report: \(url.path)\n".utf8))
        }
        if options.json {
            printJSON(report)
        } else {
            printBrowserCacheReview(report, options: options)
        }
    }

    static func packages(args: [String]) throws {
        if args.first == "lane" {
            try packageLane(args: Array(args.dropFirst()))
            return
        }
        let options = ParsedOptions(args)
        let home = options.value(after: "--home")
            .map { URL(fileURLWithPath: $0).standardizedFileURL }
            ?? FileManager.default.homeDirectoryForCurrentUser
        let roots = options.values(after: "--path").map { URL(fileURLWithPath: $0).standardizedFileURL }
        let measurementDepth = max(0, Int(options.value(after: "--max-depth") ?? "") ?? 7)
        let report = PackageCacheReviewScanner().review(
            options: PackageCacheReviewOptions(
                home: home,
                roots: roots.isEmpty ? nil : roots,
                limit: options.limit,
                measurementDepth: measurementDepth,
                includeMissingRoots: options.includeMissingScopes
            )
        )
        if options.saveAudit {
            let url = try AuditStore().save(packageCacheReviewReport: report)
            FileHandle.standardError.write(Data("saved package cache review report: \(url.path)\n".utf8))
        }
        if options.json {
            printJSON(report)
        } else {
            printPackageCacheReview(report, options: options)
        }
    }

    static func packageLane(args: [String]) throws {
        let options = ParsedOptions(args)
        let home = options.value(after: "--home")
            .map { URL(fileURLWithPath: $0).standardizedFileURL }
            ?? FileManager.default.homeDirectoryForCurrentUser
        let roots = options.values(after: "--path").map { URL(fileURLWithPath: $0).standardizedFileURL }
        let measurementDepth = max(0, Int(options.value(after: "--max-depth") ?? "") ?? 7)
        let review = PackageCacheReviewScanner().review(
            options: PackageCacheReviewOptions(
                home: home,
                roots: roots.isEmpty ? nil : roots,
                limit: options.limit,
                measurementDepth: measurementDepth,
                includeMissingRoots: options.includeMissingScopes
            )
        )
        let lane = PackageReclaimLaneBuilder.build(from: review)
        if options.json {
            printJSON(lane)
        } else {
            printPackageReclaimLane(lane)
        }
    }

    static func projects(args: [String]) throws {
        if args.first == "policy" {
            try projectDependencyPolicy(args: Array(args.dropFirst()))
            return
        }
        let options = ParsedOptions(args)
        let home = options.value(after: "--home")
            .map { URL(fileURLWithPath: $0).standardizedFileURL }
            ?? FileManager.default.homeDirectoryForCurrentUser
        let roots = options.values(after: "--path").map { URL(fileURLWithPath: $0).standardizedFileURL }
        let measurementDepth = max(0, Int(options.value(after: "--max-depth") ?? "") ?? 8)
        let searchDepth = max(0, Int(options.value(after: "--search-depth") ?? "") ?? 6)
        let report = ProjectDependencyReviewScanner().review(
            options: ProjectDependencyReviewOptions(
                home: home,
                roots: roots.isEmpty ? nil : roots,
                limit: options.limit,
                oldDays: options.oldDays,
                maximumSearchDepth: searchDepth,
                measurementDepth: measurementDepth,
                includeMissingRoots: options.includeMissingScopes,
                includeVCSStatus: options.includeVCSStatus,
                projectPolicy: ProjectDependencyPolicyStore().load(),
                includePolicySkippedProjects: options.includePolicySkippedProjects
            )
        )
        if options.saveAudit {
            let url = try AuditStore().save(projectDependencyReviewReport: report)
            FileHandle.standardError.write(Data("saved project dependency review report: \(url.path)\n".utf8))
        }
        if options.json {
            printJSON(report)
        } else {
            printProjectDependencyReview(report, options: options)
        }
    }

    static func projectDependencyPolicy(args: [String]) throws {
        guard let subcommand = args.first else {
            throw CLIError.message("projects policy requires list, review, preserve, skip-review, remove, export, or import")
        }
        let options = ParsedOptions(Array(args.dropFirst()))
        let store = ProjectDependencyPolicyStore()
        switch subcommand {
        case "list":
            let policy = store.load()
            if options.json {
                printJSON(policy)
            } else {
                printProjectDependencyPolicy(policy)
            }
        case "review", "preserve", "skip-review", "skip":
            guard args.indices.contains(1), !args[1].hasPrefix("-") else {
                throw CLIError.message("projects policy \(subcommand) requires a project root path")
            }
            let decision: ProjectDependencyPolicyDecision
            switch subcommand {
            case "review": decision = .review
            case "preserve": decision = .preserve
            case "skip-review", "skip": decision = .skipReview
            default: decision = .review
            }
            let policy = try store.set(
                projectRootPath: args[1],
                projectName: options.value(after: "--name"),
                decision: decision,
                reason: options.reason
            )
            if options.json {
                printJSON(policy)
            } else {
                print("saved \(decision.label): \(ProjectDependencyPolicy.standardizedPath(args[1]))")
                printProjectDependencyPolicy(policy)
            }
        case "set":
            guard args.indices.contains(1), !args[1].hasPrefix("-") else {
                throw CLIError.message("projects policy set requires a project root path")
            }
            guard let decision = options.projectDependencyPolicyDecision else {
                throw CLIError.message("projects policy set requires --decision review|preserve|skip-review")
            }
            let policy = try store.set(
                projectRootPath: args[1],
                projectName: options.value(after: "--name"),
                decision: decision,
                reason: options.reason
            )
            if options.json {
                printJSON(policy)
            } else {
                print("saved \(decision.label): \(ProjectDependencyPolicy.standardizedPath(args[1]))")
                printProjectDependencyPolicy(policy)
            }
        case "remove":
            guard args.indices.contains(1), !args[1].hasPrefix("-") else {
                throw CLIError.message("projects policy remove requires a project root path")
            }
            let policy = try store.remove(projectRootPath: args[1])
            if options.json {
                printJSON(policy)
            } else {
                print("removed project dependency policy for: \(ProjectDependencyPolicy.standardizedPath(args[1]))")
                printProjectDependencyPolicy(policy)
            }
        case "export":
            let document = store.exportDocument()
            if let output = options.outputPath {
                let url = URL(fileURLWithPath: output).standardizedFileURL
                _ = try store.writeExport(document, to: url)
                FileHandle.standardError.write(Data("wrote project dependency policy export: \(url.path)\n".utf8))
            }
            if options.json || options.outputPath == nil {
                printJSON(document)
            } else {
                printProjectDependencyPolicyExportSummary(document)
            }
        case "import":
            guard args.indices.contains(1), !args[1].hasPrefix("-") else {
                throw CLIError.message("projects policy import requires a policy JSON path")
            }
            let sourceURL = URL(fileURLWithPath: args[1]).standardizedFileURL
            let result = try store.importDocument(from: sourceURL, merge: !options.replacePolicy)
            if options.json {
                printJSON(result)
            } else {
                printProjectDependencyPolicyImportResult(result)
            }
        default:
            throw CLIError.message("Unknown projects policy subcommand: \(subcommand)")
        }
    }

    static func deviceBackups(args: [String]) throws {
        let options = ParsedOptions(args)
        let home = options.value(after: "--home")
            .map { URL(fileURLWithPath: $0).standardizedFileURL }
            ?? FileManager.default.homeDirectoryForCurrentUser
        let root = options.value(after: "--path")
            .map { URL(fileURLWithPath: $0).standardizedFileURL }
        let measurementDepth = max(0, Int(options.value(after: "--max-depth") ?? "") ?? 12)
        let report = DeviceBackupReviewScanner().review(
            options: DeviceBackupReviewOptions(
                home: home,
                root: root,
                limit: options.limit,
                oldDays: options.oldDays,
                measurementDepth: measurementDepth
            )
        )
        if options.saveAudit {
            let url = try AuditStore().save(deviceBackupReviewReport: report)
            FileHandle.standardError.write(Data("saved device backup review report: \(url.path)\n".utf8))
        }
        if options.json {
            printJSON(report)
        } else {
            printDeviceBackupReview(report, options: options)
        }
    }

    static func xcode(args: [String]) throws {
        let options = ParsedOptions(args)
        let home = options.value(after: "--home")
            .map { URL(fileURLWithPath: $0).standardizedFileURL }
            ?? FileManager.default.homeDirectoryForCurrentUser
        let roots = options.values(after: "--path").map { URL(fileURLWithPath: $0).standardizedFileURL }
        let measurementDepth = max(0, Int(options.value(after: "--max-depth") ?? "") ?? 10)
        let report = XcodeReviewScanner().review(
            options: XcodeReviewOptions(
                home: home,
                roots: roots.isEmpty ? nil : roots,
                limit: options.limit,
                oldDays: options.oldDays,
                measurementDepth: measurementDepth,
                includeMissingRoots: options.includeMissingScopes
            )
        )
        if options.saveAudit {
            let url = try AuditStore().save(xcodeReviewReport: report)
            FileHandle.standardError.write(Data("saved Xcode review report: \(url.path)\n".utf8))
        }
        if options.json {
            printJSON(report)
        } else {
            printXcodeReview(report, options: options)
        }
    }

    static func trash(args: [String]) throws {
        let options = ParsedOptions(args)
        let root = options.value(after: "--path")
            .map { URL(fileURLWithPath: $0).standardizedFileURL }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
        let measurementDepth = max(0, Int(options.value(after: "--max-depth") ?? "") ?? 8)
        let report = TrashReviewScanner().review(
            options: TrashReviewOptions(
                root: root,
                limit: options.limit,
                measurementDepth: measurementDepth
            )
        )
        if options.saveAudit {
            let url = try AuditStore().save(trashReviewReport: report)
            FileHandle.standardError.write(Data("saved trash review report: \(url.path)\n".utf8))
        }
        if options.json {
            printJSON(report)
        } else {
            printTrashReview(report, options: options)
        }
    }

    static func apps(args: [String]) throws {
        if args.first == "uninstall-preview" {
            try appUninstallPreview(args: Array(args.dropFirst()))
            return
        }
        if args.first == "uninstall" {
            try appUninstall(args: Array(args.dropFirst()))
            return
        }
        let options = ParsedOptions(args)
        let report = try AppReviewScanner().scan(options: options.appReviewOptions)
        if options.json {
            printJSON(report)
        } else {
            printAppReview(report, options: options)
        }
    }

    static func appUninstallPreview(args: [String]) throws {
        let options = ParsedOptions(args)
        try options.validateReportPrivacyOptions()
        let report = try AppReviewScanner().scan(options: options.appReviewOptions)
        let preview = try AppUninstallPreviewBuilder.build(report: report, selector: options.appUninstallSelector)
        if options.saveAudit {
            let url = try AuditStore().save(appUninstallPreview: preview)
            FileHandle.standardError.write(Data("saved app uninstall preview: \(url.path)\n".utf8))
        }
        if let output = options.outputPath {
            let markdown = AppUninstallPreviewMarkdownBuilder.build(
                preview: preview,
                title: options.appUninstallPreviewTitle,
                itemLimit: options.limit,
                privacy: options.reportPrivacy
            )
            let url = URL(fileURLWithPath: output).standardizedFileURL
            try SafeFileOutput.write(markdown, to: url)
            FileHandle.standardError.write(Data("wrote app uninstall preview: \(url.path)\n".utf8))
        }
        if options.json {
            printJSON(preview)
        } else if options.outputPath == nil {
            printAppUninstallPreview(preview, options: options)
        }
    }

    static func appUninstall(args: [String]) throws {
        let options = ParsedOptions(args)
        guard options.dryRun else {
            throw CLIError.message("apps uninstall is dry-run only because app-bundle Trash cannot be bound to the verified bundle. Run --dry-run for evidence, then remove the selected app manually in Finder.")
        }
        let appReviewOptions = options.appReviewOptions
        let report = try AppReviewScanner().scan(options: appReviewOptions)
        let preview = try AppUninstallPreviewBuilder.build(report: report, selector: options.appUninstallSelector)
        let auditStore = AuditStore()
        let receipt = AppUninstallExecutor(
            openFileChecker: options.noLsof && options.dryRun ? NoOpenFilesChecker() : LsofOpenFileChecker(),
            configuration: AppUninstallExecutorConfiguration(
                userPathPolicy: options.userPathPolicy,
                allowedAppRoots: appReviewOptions.appRoots
            )
        )
            .execute(
                preview: preview,
                mode: options.dryRun ? .dryRun : .perform,
                userConfirmed: options.yes
            )
        if options.saveAudit {
            let previewURL = try auditStore.save(appUninstallPreview: preview)
            let receiptURL = try auditStore.save(appUninstallReceipt: receipt)
            FileHandle.standardError.write(Data("saved app uninstall preview: \(previewURL.path)\n".utf8))
            FileHandle.standardError.write(Data("saved app uninstall receipt: \(receiptURL.path)\n".utf8))
        }
        if options.json {
            printJSON(receipt)
        } else {
            printAppUninstallReceipt(receipt)
        }
    }

    static func agents(args: [String]) throws {
        if args.first == "retention-plan" {
            try agentRetentionPlan(args: Array(args.dropFirst()))
            return
        }
        if args.first == "retention" {
            try agentRetention(args: Array(args.dropFirst()))
            return
        }
        let options = ParsedOptions(args)
        let report = try agentStorageReview(options: options)
        if options.json {
            printJSON(report)
        } else {
            printAgentStorageReview(report, options: options)
        }
    }

    static func agentRetention(args: [String]) throws {
        let options = ParsedOptions(args)
        let review = try agentStorageReview(options: options)
        let report = AgentRetentionBuilder.build(
            review: review,
            profile: try options.agentRetentionProfile(),
            limit: options.limit
        )
        if options.json {
            printJSON(report)
        } else {
            printAgentRetentionReport(report, options: options)
        }
    }

    static func agentRetentionPlan(args: [String]) throws {
        let options = ParsedOptions(args)
        let source = try agentStorageFindings(options: options)
        let preparedFindings = options.prepare(source.findings)
        let review = AgentStorageReviewBuilder.build(
            findings: preparedFindings,
            scopes: source.scopes,
            limit: options.limit
        )
        let retention = AgentRetentionBuilder.build(
            review: review,
            profile: try options.agentRetentionProfile(),
            limit: options.limit
        )
        let preview = AgentRetentionPlanBuilder.build(report: retention, matchingFindings: preparedFindings)
        if options.json {
            printJSON(preview)
        } else {
            printAgentRetentionPlanPreview(preview)
        }
    }

    private static func agentStorageReview(options: ParsedOptions) throws -> AgentStorageReview {
        let source = try agentStorageFindings(options: options)
        let report = AgentStorageReviewBuilder.build(
            findings: options.prepare(source.findings),
            scopes: source.scopes,
            limit: options.limit
        )
        return report
    }

    private static func agentStorageFindings(options: ParsedOptions) throws -> (findings: [Finding], scopes: [ScanScope]) {
        let scopes: [ScanScope]
        if options.hasCustomScopeSelection {
            scopes = try options.scopes(includeUnavailable: options.includeMissingScopes)
        } else {
            scopes = DefaultScopes.aiAgentStorage(includeUnavailable: options.includeMissingScopes)
        }
        let scanner = try FileScanner(ruleEngine: try options.ruleEngine(), openFileChecker: options.noLsof ? NoOpenFilesChecker() : LsofOpenFileChecker())
        let findings = scanner.scan(scopes: scopes, options: options.scanOptions(includeOpenFiles: false))
        return (findings, scopes)
    }
}

func printFindings(_ findings: [Finding], options: ParsedOptions) {
    let limited = Array(findings.prefix(options.limit))
    if let group = options.group {
        let groups = Dictionary(grouping: limited) { finding -> String in
            switch group {
            case "safety": finding.safetyClass.label
            case "scope": finding.scopeName
            default: finding.primaryCategory
            }
        }
        for key in groups.keys.sorted() {
            let items = groups[key] ?? []
            let total = items.reduce(0) { $0 + $1.allocatedSize }
            print("\n\(key) - \(items.count) item(s), \(ByteFormat.string(total))")
            printFindingRows(items)
        }
    } else {
        printFindingRows(limited)
    }
    if findings.count > options.limit {
        print("... \(findings.count - options.limit) more findings")
    }
}

func printFindingRows(_ findings: [Finding]) {
    print(
        "\(pad("Allocated", 11)) \(pad("Logical", 11)) \(pad("Age", 6)) \(pad("Safety", 22)) \(pad("Category", 18)) \(pad("Action", 16)) Path"
    )
    for finding in findings {
        let age = finding.ageInDays().map { "\($0)d" } ?? "-"
        print(
            "\(pad(ByteFormat.string(finding.allocatedSize), 11)) \(pad(ByteFormat.string(finding.logicalSize), 11)) \(pad(age, 6)) \(pad(finding.safetyClass.label, 22)) \(pad(finding.primaryCategory, 18)) \(pad(finding.actionKind.label, 16)) \(finding.path)"
        )
    }
}

func printOverview(_ overview: ScanOverview) {
    print("Ryddi overview")
    print("Generated: \(overview.generatedAt.formatted())")
    if let coverage = overview.scanCoverage {
        print("Scan coverage: \(coverage.state.label) (\(coverage.measuredItemCount)/\(coverage.requestedItemBudget) measured, \(coverage.skippedItemCount) skipped)")
        print("Coverage note: \(coverage.nonClaim)")
    }
    print("Findings: \(overview.findingCount)")
    print("Allocated scanned: \(ByteFormat.string(overview.totalAllocatedSize))")
    print("Logical scanned: \(ByteFormat.string(overview.totalLogicalSize))")
    print("Auto-safe bytes: \(ByteFormat.string(overview.expectedAutoSafeBytes))")
    print("Review bytes: \(ByteFormat.string(overview.reviewBytes))")
    print("Protected bytes: \(ByteFormat.string(overview.protectedBytes))")

    print("\nPermission coverage")
    for scope in overview.scopeSummaries {
        print("- \(scope.permissionState.rawValue): \(scope.name) - \(scope.path)")
    }

    print("\nBy category")
    for summary in overview.categorySummaries.prefix(12) {
        print("- \(pad(summary.name, 22)) \(pad(ByteFormat.string(summary.allocatedSize), 10)) \(summary.count) item(s)")
    }

    print("\nBy owner")
    for summary in overview.ownerSummaries.prefix(12) {
        let reclaim = summary.isReclaimable ? "reclaimable" : "review"
        print("- \(pad(summary.ownerName, 22)) \(pad(ByteFormat.string(summary.allocatedSize), 10)) \(pad(summary.dominantCategory, 18)) \(reclaim)")
    }

    print("\nVisual map nodes")
    for node in overview.mapNodes.prefix(10) {
        let reclaim = node.isReclaimable ? "reclaimable" : "review"
        print("- \(pad(node.name, 22)) \(pad(ByteFormat.string(node.allocatedSize), 10)) \(reclaim)")
    }

    print("\nTop offenders")
    printTopOffenderTable(overview.topOffenderTable)

    print("\nAPFS/accounting notes")
    for note in overview.accountingNotes {
        print("- \(note)")
    }
}

func printTopOffenderTable(_ table: TopOffenderTable) {
    print("Sort: \(table.sort.label); group: \(table.group.label); rows: \(table.rowCount)/\(table.limit)")
    print("Estimated immediate reclaim: \(ByteFormat.string(table.estimatedImmediateReclaim))")
    if table.rows.isEmpty {
        print("No top offender rows matched the current scan.")
    } else if table.group == .none {
        printTopOffenderRows(table.rows)
    } else {
        for section in table.sections {
            print(
                "\n\(section.title) - \(section.count) item(s), \(ByteFormat.string(section.allocatedSize)) allocated, \(ByteFormat.string(section.estimatedImmediateReclaim)) reclaim"
            )
            printTopOffenderRows(section.rows)
        }
    }

    print("\nTop-offender non-claims")
    for note in table.nonClaims {
        print("- \(note)")
    }
}

func printTopOffenderRows(_ rows: [TopOffenderRow]) {
    print(
        "\(pad("Reclaim", 11)) \(pad("Allocated", 11)) \(pad("Age", 6)) \(pad("Confidence", 12)) \(pad("Safety", 22)) \(pad("Category", 18)) \(pad("Owner", 16)) \(pad("Next", 18)) Path"
    )
    for row in rows {
        let age = row.ageDays.map { "\($0)d" } ?? "-"
        print(
            "\(pad(ByteFormat.string(row.estimatedImmediateReclaim), 11)) \(pad(ByteFormat.string(row.allocatedSize), 11)) \(pad(age, 6)) \(pad(row.confidence.label, 12)) \(pad(row.safetyClass.label, 22)) \(pad(row.category, 18)) \(pad(row.ownerName, 16)) \(pad(row.nextAction.label, 18)) \(row.path)"
        )
    }
}

func printReviewQueueReport(_ report: ReviewQueueReport) {
    print("Ryddi review queues")
    print("Generated: \(report.generatedAt.formatted())")
    print("Findings queued: \(report.totalCount)")
    print("Allocated queued: \(ByteFormat.string(report.totalAllocatedSize))")
    print("Estimated immediate reclaim: \(ByteFormat.string(report.estimatedImmediateReclaim))")

    print("\nQueues")
    print("\(pad("Queue", 22)) \(pad("Items", 7)) \(pad("Allocated", 11)) \(pad("Reclaim", 11)) \(pad("Risk", 22)) \(pad("Dominant", 18)) Action")
    for queue in report.queues {
        let risk = queue.highestRiskClass?.label ?? "-"
        let action = queue.dominantAction?.label ?? "-"
        print("\(pad(queue.title, 22)) \(pad("\(queue.count)", 7)) \(pad(ByteFormat.string(queue.allocatedSize), 11)) \(pad(ByteFormat.string(queue.estimatedImmediateReclaim), 11)) \(pad(risk, 22)) \(pad(queue.dominantCategory, 18)) \(action)")
        print("  \(queue.guidance)")
    }

    for queue in report.queues where !queue.rows.isEmpty {
        print("\n\(queue.title) examples")
        printTopOffenderRows(queue.rows)
    }

    print("\nQueue non-claims")
    for note in report.nonClaims {
        print("- \(note)")
    }
}

func printReviewQueueDetailReport(_ report: ReviewQueueDetailReport) {
    print("Ryddi review queue: \(report.title)")
    print("Generated: \(report.generatedAt.formatted())")
    print("Queue ID: \(report.queueID.rawValue)")
    print("Findings queued: \(report.count)")
    print("Rows shown: \(report.rowCount)/\(report.limit)")
    print("Allocated queued: \(ByteFormat.string(report.allocatedSize))")
    print("Logical queued: \(ByteFormat.string(report.logicalSize))")
    print("Estimated immediate reclaim: \(ByteFormat.string(report.estimatedImmediateReclaim))")
    print("Highest risk: \(report.highestRiskClass?.label ?? "-")")
    print("Dominant category: \(report.dominantCategory)")
    print("Dominant action: \(report.dominantAction?.label ?? "-")")
    print("\nGuidance")
    print("- \(report.guidance)")

    print("\nRows")
    if report.rows.isEmpty {
        print("No findings are currently in this queue.")
    } else {
        printTopOffenderRows(report.rows)
    }

    print("\nQueue non-claims")
    for note in report.nonClaims {
        print("- \(note)")
    }
}

func printLargeOldReviewReport(_ report: LargeOldReviewReport) {
    print("Ryddi large & old file review")
    print("Generated: \(report.generatedAt.formatted())")
    print("Mode: \(report.mode.label)")
    print("Findings: \(report.totalCount)")
    print("Large: \(report.largeCount)")
    print("Old: \(report.oldCount)")
    print("Large and old: \(report.largeAndOldCount)")
    print("Allocated: \(ByteFormat.string(report.totalAllocatedSize))")
    print("Logical: \(ByteFormat.string(report.totalLogicalSize))")
    print("Review-required bytes: \(ByteFormat.string(report.reviewRequiredBytes))")
    print("Protected bytes: \(ByteFormat.string(report.protectedBytes))")
    print("Estimated immediate reclaim: \(ByteFormat.string(report.estimatedImmediateReclaim))")

    if !report.kindSummaries.isEmpty {
        print("\nBy signal")
        for summary in report.kindSummaries {
            print("- \(summary.name): \(summary.count) item(s), \(ByteFormat.string(summary.allocatedSize))")
        }
    }

    if !report.categorySummaries.isEmpty {
        print("\nTop categories")
        for summary in report.categorySummaries.prefix(8) {
            print("- \(summary.name): \(summary.count) item(s), \(ByteFormat.string(summary.allocatedSize))")
        }
    }

    if !report.safetySummaries.isEmpty {
        print("\nSafety")
        for summary in report.safetySummaries {
            print("- \(summary.name): \(summary.count) item(s), \(ByteFormat.string(summary.allocatedSize))")
        }
    }

    if !report.rows.isEmpty {
        print("\nReview rows")
        printTopOffenderRows(report.rows.map(\.row))
    }

    print("\nLarge & old non-claims")
    for note in report.nonClaims {
        print("- \(note)")
    }
}

func printArchiveReviewReport(_ report: ArchiveReviewReport) {
    print("Ryddi archive candidate review")
    print("Generated: \(report.createdAt.formatted())")
    print("Mode: \(report.mode.label)")
    print("Candidates: \(report.candidateCount)")
    print("Rows shown: \(report.rowCount)/\(report.limit)")
    print("Allocated under review: \(ByteFormat.string(report.totalAllocatedSize))")
    print("Archive candidate bytes: \(ByteFormat.string(report.archiveCandidateBytes))")
    print("Trash-review bytes: \(ByteFormat.string(report.trashReviewBytes))")
    print("Cleanup-plan bytes: \(ByteFormat.string(report.cleanupPlanBytes))")
    print("Keep/manual bytes: \(ByteFormat.string(report.keepBytes))")
    print("Blocked bytes: \(ByteFormat.string(report.blockedBytes))")

    if !report.recommendationSummaries.isEmpty {
        print("\nRecommendations")
        for summary in report.recommendationSummaries {
            print("- \(summary.name): \(summary.count) item(s), \(ByteFormat.string(summary.allocatedSize))")
        }
    }

    if !report.categorySummaries.isEmpty {
        print("\nTop categories")
        for summary in report.categorySummaries.prefix(8) {
            print("- \(summary.name): \(summary.count) item(s), \(ByteFormat.string(summary.allocatedSize))")
        }
    }

    if !report.rows.isEmpty {
        print("\nCandidate checklist")
        print("\(pad("Recommendation", 17)) \(pad("Size", 11)) \(pad("Age", 6)) \(pad("Safety", 22)) Path")
        for row in report.rows {
            let age = row.ageDays.map { "\($0)d" } ?? "-"
            print("\(pad(row.recommendation.label, 17)) \(pad(ByteFormat.string(row.allocatedSize), 11)) \(pad(age, 6)) \(pad(row.safetyClass.label, 22)) \(row.path)")
            print("  \(row.rationale)")
            print("  \(row.suggestedAction)")
        }
    }

    print("\nArchive review non-claims")
    for note in report.nonClaims {
        print("- \(note)")
    }
}

func printDiskDrillDown(_ report: DiskDrillDownReport) {
    print("Ryddi disk drill-down")
    print("Generated: \(report.generatedAt.formatted())")
    print("Scanned roots: \(report.scannedRoots.count)")
    print("Nodes: \(report.nodeCount)")
    print("Allocated scanned: \(ByteFormat.string(report.totalAllocatedSize))")
    print("Logical scanned: \(ByteFormat.string(report.totalLogicalSize))")
    print("Tree depth: \(report.maxDepth)")
    print("Child limit: \(report.childLimit)")

    print("\nHierarchy")
    if report.rootNodes.isEmpty {
        print("No drill-down nodes were produced for the current scan.")
    } else {
        for node in report.rootNodes {
            printDiskDrillDownNode(node)
        }
    }

    print("\nNon-claims")
    for note in report.nonClaims {
        print("- \(note)")
    }
}

func printDiskDrillDownNode(_ node: DiskDrillDownNode, indent: String = "") {
    let owner = node.ownerHint.map { " \($0)" } ?? ""
    let path = node.depth == 0 ? node.path : node.displayName
    print("\(indent)- \(ByteFormat.string(node.allocatedSize)) \(node.safetyClass.label) \(node.category)\(owner) \(path)")
    if node.omittedChildCount > 0 {
        print("\(indent)  ... \(node.omittedChildCount) more child item(s), \(ByteFormat.string(node.omittedAllocatedSize))")
    }
    for child in node.children {
        printDiskDrillDownNode(child, indent: indent + "  ")
    }
}

func printDuplicateReview(_ report: DuplicateReview, options: ParsedOptions) {
    print("Ryddi duplicate review")
    print("Generated: \(report.createdAt.formatted())")
    print("Scanned roots: \(report.scannedRoots.count)")
    print("Duplicate groups: \(report.groups.count)")
    print("Duplicate files: \(report.duplicateFileCount)")
    print("Apparent duplicate bytes: \(ByteFormat.string(report.apparentDuplicateBytes))")
    print("\nNotes")
    for note in report.notes {
        print("- \(note)")
    }

    if report.groups.isEmpty {
        print("\nNo duplicate groups found with the current options.")
    } else {
        print("\nGroups")
        print("\(pad("Apparent", 12)) \(pad("Files", 7)) \(pad("Each", 12)) \(pad("Safety", 22)) \(pad("Category", 18)) ID")
        for group in report.groups.prefix(options.limit) {
            let safety = group.files.map(\.safetyClass).max { $0.riskRank < $1.riskRank } ?? .reviewRequired
            let category = Dictionary(grouping: group.files, by: \.category)
                .max { lhs, rhs in lhs.value.count < rhs.value.count }?.key ?? "Unmatched"
            print("\(pad(ByteFormat.string(group.apparentDuplicateBytes), 12)) \(pad("\(group.files.count)", 7)) \(pad(ByteFormat.string(group.logicalSize), 12)) \(pad(safety.label, 22)) \(pad(category, 18)) \(group.id)")
            for file in group.files.prefix(8) {
                let modified = file.modificationDate?.formatted(date: .numeric, time: .omitted) ?? "-"
                print("  - \(ByteFormat.string(file.allocatedSize)) \(file.safetyClass.label) \(modified) \(file.path)")
            }
            if group.files.count > 8 {
                print("  ... \(group.files.count - 8) more file(s)")
            }
            for note in group.notes.prefix(1) {
                print("  note: \(note)")
            }
        }
        if report.groups.count > options.limit {
            print("... \(report.groups.count - options.limit) more duplicate group(s)")
        }
    }

    if options.showExcluded, !report.skipped.isEmpty {
        print("\nExcluded or skipped")
        for line in report.skipped.prefix(options.limit) {
            print("- \(line)")
        }
        if report.skipped.count > options.limit {
            print("... \(report.skipped.count - options.limit) more skipped item(s)")
        }
    }
}

func printAppReview(_ report: AppReviewReport, options: ParsedOptions) {
    print("Ryddi apps & leftovers review")
    print("Generated: \(report.createdAt.formatted())")
    print("App roots: \(report.appRoots.count)")
    print("Installed apps: \(report.installedApps.count)")
    print("Installed app groups: \(report.installedAppGroups.count)")
    print("Orphan candidate groups: \(report.orphanGroups.count)")
    print("Review bytes: \(ByteFormat.string(report.reviewBytes))")
    print("\nNotes")
    for note in report.notes {
        print("- \(note)")
    }

    print("\nInstalled apps with related files")
    if report.installedAppGroups.isEmpty {
        print("No installed-app related files matched the current size threshold.")
    } else {
        printAppGroups(report.installedAppGroups, options: options)
    }

    print("\nOrphan candidates")
    if report.orphanGroups.isEmpty {
        print("No orphan candidate groups matched the current options.")
    } else {
        printAppGroups(report.orphanGroups, options: options)
    }

    if options.showExcluded, !report.skipped.isEmpty {
        print("\nExcluded or skipped")
        for line in report.skipped.prefix(options.limit) {
            print("- \(line)")
        }
        if report.skipped.count > options.limit {
            print("... \(report.skipped.count - options.limit) more skipped item(s)")
        }
    }
}

func printAppGroups(_ groups: [AppReviewGroup], options: ParsedOptions) {
    print("\(pad("Bytes", 12)) \(pad("Items", 7)) \(pad("Safety", 22)) \(pad("Owner", 28)) Identifier")
    for group in groups.prefix(options.limit) {
        let identifier = group.bundleIdentifier ?? group.id
        print("\(pad(ByteFormat.string(group.totalAllocatedSize), 12)) \(pad("\(group.items.count)", 7)) \(pad(group.highestRiskClass.label, 22)) \(pad(group.ownerName, 28)) \(identifier)")
        if let appPath = group.appPath {
            print("  app: \(appPath)")
        }
        for item in group.items.prefix(6) {
            let modified = item.modificationDate?.formatted(date: .numeric, time: .omitted) ?? "-"
            print("  - \(ByteFormat.string(item.allocatedSize)) \(item.safetyClass.label) \(item.category) \(modified) \(item.nextAction.label) \(item.path)")
        }
        if group.items.count > 6 {
            print("  ... \(group.items.count - 6) more item(s)")
        }
        for note in group.notes.prefix(1) {
            print("  note: \(note)")
        }
    }
    if groups.count > options.limit {
        print("... \(groups.count - options.limit) more app group(s)")
    }
}

func printAppUninstallPreview(_ preview: AppUninstallPreview, options: ParsedOptions) {
    print("Ryddi app uninstall preview \(preview.id)")
    print("Generated: \(preview.createdAt.formatted())")
    print("App: \(preview.selectedApp.displayName)")
    if let bundleIdentifier = preview.selectedApp.bundleIdentifier {
        print("Bundle id: \(bundleIdentifier)")
    }
    print("Bundle path: \(preview.bundleCandidate.path)")
    print("Bundle action: \(preview.bundleCandidate.actionKind.label) / \(preview.bundleCandidate.disposition.label)")
    print("Explicit Trash preview bytes: \(ByteFormat.string(preview.explicitTrashPreviewBytes))")
    print("Related review bytes: \(ByteFormat.string(preview.relatedReviewBytes))")
    print("Total bytes under review: \(ByteFormat.string(preview.totalBytesUnderReview))")

    print("\nBundle guidance")
    for line in preview.bundleCandidate.guidance {
        print("- \(line)")
    }

    print("\nRelated files")
    if preview.relatedItems.isEmpty {
        print("No related support files matched the current app-review threshold.")
    } else {
        print("\(pad("Bytes", 12)) \(pad("Safety", 22)) \(pad("Action", 16)) \(pad("Category", 18)) Path")
        for item in preview.relatedItems.prefix(options.limit) {
            print("\(pad(ByteFormat.string(item.allocatedSize), 12)) \(pad(item.safetyClass.label, 22)) \(pad(item.actionKind.label, 16)) \(pad(item.category, 18)) \(item.path)")
        }
        if preview.relatedItems.count > options.limit {
            print("... \(preview.relatedItems.count - options.limit) more related item(s)")
        }
    }

    print("\nNotes")
    for note in preview.notes {
        print("- \(note)")
    }

    print("\nNon-claims")
    for note in preview.nonClaims {
        print("- \(note)")
    }
}

func printAppUninstallReceipt(_ receipt: AppUninstallExecutionReceipt) {
    print("Ryddi app uninstall receipt \(receipt.id)")
    print("Generated: \(receipt.createdAt.formatted())")
    print("Mode: \(receipt.mode)")
    print("Status: \(receipt.status)")
    print("App: \(receipt.appDisplayName)")
    if let bundleIdentifier = receipt.bundleIdentifier {
        print("Bundle id: \(bundleIdentifier)")
    }
    print("Bundle path: \(receipt.bundlePath)")
    print("Action: \(receipt.actionKind.label) / \(receipt.disposition.label)")
    print("Selected bundle bytes: \(ByteFormat.string(receipt.selectedBundleBytes))")
    print("Related review bytes untouched: \(ByteFormat.string(receipt.relatedReviewBytes))")
    print("Message: \(receipt.message)")
    if let resultingTrashPath = receipt.resultingTrashPath {
        print("Trash path: \(resultingTrashPath)")
    }
    if !receipt.errors.isEmpty {
        print("\nErrors")
        for error in receipt.errors {
            print("- \(error)")
        }
    }
    print("\nNon-claims")
    for note in receipt.nonClaims {
        print("- \(note)")
    }
}

func printAgentStorageReview(_ report: AgentStorageReview, options: ParsedOptions) {
    print("Ryddi AI agent storage review")
    print("Generated: \(report.createdAt.formatted())")
    print("Scanned roots: \(report.scannedRoots.count)")
    print("Agent items: \(report.itemCount)")
    print("Allocated reviewed: \(ByteFormat.string(report.totalBytes))")
    print("Reclaimable cache: \(ByteFormat.string(report.reclaimableBytes))")
    print("Protected/history: \(ByteFormat.string(report.protectedBytes))")

    print("\nBy bucket")
    if report.bucketSummaries.isEmpty {
        print("No agent storage matched the current roots.")
    } else {
        for summary in report.bucketSummaries {
            print("- \(pad(summary.bucket.label, 20)) \(pad(ByteFormat.string(summary.bytes), 10)) \(summary.count) item(s)")
            print("  \(summary.bucket.guidance)")
        }
    }

    if !report.ownerSummaries.isEmpty {
        print("\nBy owner")
        print("\(pad("Owner", 14)) \(pad("Bytes", 11)) \(pad("Reclaim", 11)) \(pad("Protected", 11)) Dominant bucket")
        for summary in report.ownerSummaries.prefix(options.limit) {
            print("\(pad(summary.owner, 14)) \(pad(ByteFormat.string(summary.bytes), 11)) \(pad(ByteFormat.string(summary.reclaimableBytes), 11)) \(pad(ByteFormat.string(summary.protectedBytes), 11)) \(summary.dominantBucket.label)")
        }
    }

    if !report.items.isEmpty {
        print("\nItems")
        print("\(pad("Bytes", 11)) \(pad("Owner", 12)) \(pad("Bucket", 20)) \(pad("Safety", 22)) \(pad("Action", 16)) Path")
        for item in report.items.prefix(options.limit) {
            print("\(pad(ByteFormat.string(item.allocatedSize), 11)) \(pad(item.owner, 12)) \(pad(item.bucket.label, 20)) \(pad(item.safetyClass.label, 22)) \(pad(item.actionKind.label, 16)) \(item.path)")
            if let firstGuidance = item.guidance.first {
                print("  - \(firstGuidance)")
            }
            if let firstRule = item.ruleIDs.first {
                print("  rule: \(firstRule)")
            }
        }
    }

    print("\nNon-claims")
    for note in report.nonClaims {
        print("- \(note)")
    }
}

func printAgentRetentionReport(_ report: AgentRetentionReport, options: ParsedOptions) {
    print("Ryddi AI agent retention report")
    print("Generated: \(report.createdAt.formatted())")
    print("Profile: \(report.profile.label)")
    print(report.profileSummary)
    print("Reviewed items: \(report.reviewedItemCount)")
    print("Allocated reviewed: \(ByteFormat.string(report.totalBytes))")
    print("Cleanup candidates: \(ByteFormat.string(report.cleanupCandidateBytes))")
    print("Compression candidates: \(ByteFormat.string(report.compressionCandidateBytes))")
    print("Protected: \(ByteFormat.string(report.protectedBytes))")

    print("\nBy recommendation")
    if report.summaries.isEmpty {
        print("No agent retention recommendations matched the current roots.")
    } else {
        for summary in report.summaries {
            print("- \(pad(summary.recommendation.label, 22)) \(pad(ByteFormat.string(summary.bytes), 10)) \(summary.count) item(s)")
        }
    }

    if !report.recommendations.isEmpty {
        print("\nRecommendations")
        print("\(pad("Bytes", 11)) \(pad("Owner", 12)) \(pad("Recommendation", 22)) \(pad("Bucket", 20)) \(pad("Age", 8)) Path")
        for row in report.recommendations.prefix(options.limit) {
            let age = row.ageDays.map { "\($0)d" } ?? "unknown"
            print("\(pad(ByteFormat.string(row.allocatedSize), 11)) \(pad(row.owner, 12)) \(pad(row.recommendation.label, 22)) \(pad(row.bucket.label, 20)) \(pad(age, 8)) \(row.path)")
            print("  - \(row.reason)")
            if let firstStep = row.nextSteps.first {
                print("  next: \(firstStep)")
            }
        }
    }

    print("\nNon-claims")
    for note in report.nonClaims {
        print("- \(note)")
    }
}

func printAgentRetentionPlanPreview(_ preview: AgentRetentionPlanPreview) {
    print("Ryddi AI agent retention plan preview")
    print("Generated: \(preview.generatedAt.formatted())")
    print("Selected bytes: \(ByteFormat.string(preview.selectedBytes))")
    print("Protected bytes: \(ByteFormat.string(preview.protectedBytes))")
    print("Review bytes: \(ByteFormat.string(preview.reviewBytes))")
    print("Plan items: \(preview.plan.items.count)")

    if preview.plan.items.isEmpty {
        print("\nNo retention-eligible agent findings entered the cleanup preview plan.")
    } else {
        print("\nPreview plan")
        for item in preview.plan.items {
            let marker = item.selected ? "selected" : "blocked"
            print("- \(marker): \(ByteFormat.string(item.finding.allocatedSize)) \(item.finding.path)")
            for condition in item.conditions where !condition.isSatisfied {
                print("  blocked: \(condition.kind.label) - \(condition.message)")
            }
        }
    }

    if !preview.protectedReasons.isEmpty {
        print("\nProtected/review reasons")
        for reason in preview.protectedReasons.prefix(12) {
            print("- \(reason)")
        }
    }

    print("\nNon-claims")
    for note in preview.nonClaims {
        print("- \(note)")
    }
}

func printDownloadsReview(_ report: DownloadsReviewReport, options: ParsedOptions) {
    print("Ryddi Downloads review")
    print("Generated: \(report.createdAt.formatted())")
    print("Root: \(report.rootPath)")
    print("Permission: \(report.permissionState.rawValue)")
    print("Items measured: \(report.itemCount)")
    print("Allocated in Downloads: \(ByteFormat.string(report.totalAllocatedSize))")
    print("Review candidates: \(ByteFormat.string(report.reviewCandidateBytes))")
    print("Installers/apps: \(ByteFormat.string(report.installerBytes))")
    print("Archives: \(ByteFormat.string(report.archiveBytes))")
    print("Old candidates: \(ByteFormat.string(report.oldCandidateBytes))")

    if !report.notes.isEmpty {
        print("\nNotes")
        for note in report.notes {
            print("- \(note)")
        }
    }

    if !report.kindSummaries.isEmpty {
        print("\nBy kind")
        for summary in report.kindSummaries {
            print("- \(pad(summary.kind.label, 18)) \(pad(ByteFormat.string(summary.allocatedSize), 10)) \(summary.itemCount) item(s)")
        }
    }

    if !report.workflowSummaries.isEmpty {
        print("\nBy workflow")
        for summary in report.workflowSummaries {
            print("- \(pad(summary.workflow.label, 18)) \(pad(ByteFormat.string(summary.allocatedSize), 10)) \(summary.itemCount) item(s)")
        }
    }

    if report.largestItems.isEmpty {
        print("\nNo Downloads items found at the configured root.")
    } else {
        print("\nLargest Downloads items")
        print("\(pad("Allocated", 11)) \(pad("Kind", 18)) \(pad("Workflow", 16)) \(pad("Next", 18)) \(pad("Age", 8)) \(pad("Modified", 12)) Path")
        for item in report.largestItems.prefix(options.limit) {
            let modified = item.modificationDate?.formatted(date: .numeric, time: .omitted) ?? "unknown"
            let age = item.ageDays.map { "\($0)d" } ?? "unknown"
            print("\(pad(ByteFormat.string(item.allocatedSize), 11)) \(pad(item.kind.label, 18)) \(pad(item.workflow.label, 16)) \(pad(item.nextAction.label, 18)) \(pad(age, 8)) \(pad(modified, 12)) \(item.path)")
            print("  - \(item.recommendation)")
            if let step = item.workflowSteps.first {
                print("  workflow: \(step)")
            }
            if let guidance = item.guidance.first {
                print("  next: \(guidance)")
            }
        }
    }

    print("\nGuidance")
    for line in report.guidance {
        print("- \(line)")
    }

    print("\nNon-claims")
    for note in report.nonClaims {
        print("- \(note)")
    }
}

func printBrowserCacheReview(_ report: BrowserCacheReviewReport, options: ParsedOptions) {
    print("Ryddi Browser Cache review")
    print("Generated: \(report.createdAt.formatted())")
    print("Cache roots: \(report.rootSummaries.count)")
    print("Items measured: \(report.itemCount)")
    print("Candidate cache bytes: \(ByteFormat.string(report.candidateBytes))")
    print("Allocated cache bytes: \(ByteFormat.string(report.totalAllocatedSize))")
    print("Logical cache bytes: \(ByteFormat.string(report.totalLogicalSize))")

    if !report.browserSummaries.isEmpty {
        print("\nBy browser")
        for summary in report.browserSummaries {
            print("- \(pad(summary.name, 14)) \(pad(ByteFormat.string(summary.allocatedSize), 10)) \(summary.itemCount) item(s)")
        }
    }

    if !report.kindSummaries.isEmpty {
        print("\nBy cache kind")
        for summary in report.kindSummaries {
            print("- \(pad(summary.name, 22)) \(pad(ByteFormat.string(summary.allocatedSize), 10)) \(summary.itemCount) item(s)")
        }
    }

    if !report.runtimeSummaries.isEmpty {
        print("\nBrowser runtime status")
        for summary in report.runtimeSummaries {
            print("- \(pad(summary.browser.label, 12)) \(summary.state.label)")
            if !summary.matchedProcessNames.isEmpty {
                print("  processes: \(summary.matchedProcessNames.joined(separator: ", "))")
            }
            print("  \(summary.note)")
            if let firstGuidance = summary.guidance.first {
                print("  guidance: \(firstGuidance)")
            }
        }
    }

    print("\nCache roots")
    if report.rootSummaries.isEmpty {
        print("No browser cache roots were inspected.")
    } else {
        for root in report.rootSummaries {
            print("- \(root.browser.label): \(root.permissionState.rawValue), \(ByteFormat.string(root.allocatedSize)), \(root.itemCount) item(s)")
            print("  \(root.rootPath)")
            print("  \(root.note)")
        }
    }

    if report.largestItems.isEmpty {
        print("\nNo browser cache items found in readable cache roots.")
    } else {
        print("\nLargest browser cache items")
        print("\(pad("Allocated", 11)) \(pad("Browser", 12)) \(pad("Kind", 20)) \(pad("Modified", 12)) Path")
        for item in report.largestItems.prefix(options.limit) {
            let modified = item.modificationDate?.formatted(date: .numeric, time: .omitted) ?? "unknown"
            print("\(pad(ByteFormat.string(item.allocatedSize), 11)) \(pad(item.browser.label, 12)) \(pad(item.kind.label, 20)) \(pad(modified, 12)) \(item.path)")
            print("  - \(item.recommendation)")
        }
    }

    print("\nProtected profile roots")
    for profile in report.protectedProfileRoots {
        print("- \(profile.browser.label): \(profile.permissionState.rawValue) - \(profile.path)")
        print("  \(profile.note)")
    }

    print("\nGuidance")
    for line in report.guidance {
        print("- \(line)")
    }

    print("\nNon-claims")
    for note in report.nonClaims {
        print("- \(note)")
    }
}

func printPackageCacheReview(_ report: PackageCacheReviewReport, options: ParsedOptions) {
    print("Ryddi Package Cache review")
    print("Generated: \(report.createdAt.formatted())")
    print("Cache roots: \(report.rootSummaries.count)")
    print("Items measured: \(report.itemCount)")
    print("Candidate cache bytes: \(ByteFormat.string(report.candidateBytes))")
    print("Allocated cache bytes: \(ByteFormat.string(report.totalAllocatedSize))")
    print("Logical cache bytes: \(ByteFormat.string(report.totalLogicalSize))")

    if !report.managerSummaries.isEmpty {
        print("\nBy package manager")
        for summary in report.managerSummaries {
            print("- \(pad(summary.name, 14)) \(pad(ByteFormat.string(summary.allocatedSize), 10)) \(summary.itemCount) item(s)")
        }
    }

    if !report.kindSummaries.isEmpty {
        print("\nBy cache kind")
        for summary in report.kindSummaries {
            print("- \(pad(summary.name, 20)) \(pad(ByteFormat.string(summary.allocatedSize), 10)) \(summary.itemCount) item(s)")
        }
    }

    print("\nCache roots")
    if report.rootSummaries.isEmpty {
        print("No package cache roots were inspected.")
    } else {
        for root in report.rootSummaries {
            print("- \(root.manager.label): \(root.permissionState.rawValue), \(ByteFormat.string(root.allocatedSize)), \(root.itemCount) item(s)")
            print("  \(root.rootPath)")
            print("  \(root.nativeCleanupHint)")
            print("  \(root.note)")
        }
    }

    if report.largestItems.isEmpty {
        print("\nNo package cache items found in readable cache roots.")
    } else {
        print("\nLargest package cache items")
        print("\(pad("Allocated", 11)) \(pad("Manager", 12)) \(pad("Kind", 18)) \(pad("Modified", 12)) Path")
        for item in report.largestItems.prefix(options.limit) {
            let modified = item.modificationDate?.formatted(date: .numeric, time: .omitted) ?? "unknown"
            print("\(pad(ByteFormat.string(item.allocatedSize), 11)) \(pad(item.manager.label, 12)) \(pad(item.kind.label, 18)) \(pad(modified, 12)) \(item.path)")
            print("  - \(item.recommendation)")
        }
    }

    print("\nProtected package-manager config/auth paths")
    for protectedRoot in report.protectedConfigRoots {
        print("- \(protectedRoot.manager.label): \(protectedRoot.permissionState.rawValue) - \(protectedRoot.path)")
        print("  \(protectedRoot.note)")
    }

    print("\nGuidance")
    for line in report.guidance {
        print("- \(line)")
    }

    print("\nNon-claims")
    for note in report.nonClaims {
        print("- \(note)")
    }
}

func printPackageReclaimLane(_ report: PackageReclaimLaneReport) {
    print("Ryddi Package Cache preview lane")
    print("Generated: \(report.generatedAt.formatted())")
    print("Previewed package-cache bytes: \(ByteFormat.string(report.totalPreviewBytes))")

    if report.managerReports.isEmpty {
        print("\nNo package manager cache summaries were found.")
    } else {
        print("\nNative preview lanes")
        for manager in report.managerReports {
            print("- \(manager.managerName): \(ByteFormat.string(manager.cacheBytes))")
            print("  \(manager.explanation)")
            if manager.previewCommand.isEmpty {
                print("  preview: manual review")
            } else {
                print("  preview: \(shellCommand(manager.previewCommand))")
            }
            if manager.cleanupCommand.isEmpty {
                print("  cleanup: no allowlisted cleanup command")
            } else {
                print("  cleanup: \(shellCommand(manager.cleanupCommand))")
            }
            for card in manager.commandCards {
                let review = card.review == .manualReview ? "manual-review" : "safe-action"
                print("  card: \(card.title) [\(card.role.rawValue), \(review), dry-run: \(card.dryRunSupport.rawValue)]")
                print("    \(shellCommand(card.argv))")
                print("    \(card.note)")
            }
        }
    }

    print("\nNon-claims")
    for note in report.nonClaims {
        print("- \(note)")
    }
}

private func shellCommand(_ command: [String]) -> String {
    command.map { part in
        if part.rangeOfCharacter(from: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "'\""))) == nil {
            return part
        }
        return "'" + part.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
    .joined(separator: " ")
}

func printProjectDependencyReview(_ report: ProjectDependencyReviewReport, options: ParsedOptions) {
    print("Ryddi Project Dependencies review")
    print("Generated: \(report.createdAt.formatted())")
    print("Project roots: \(report.rootSummaries.count)")
    print("Candidates found: \(report.largestItems.count)")
    print("Items measured: \(report.itemCount)")
    print("Candidate bytes: \(ByteFormat.string(report.candidateBytes))")
    print("Rebuildable-after-review bytes: \(ByteFormat.string(report.rebuildableBytes))")
    print("Review-required bytes: \(ByteFormat.string(report.reviewRequiredBytes))")
    print("Allocated project dependency bytes: \(ByteFormat.string(report.totalAllocatedSize))")
    print("Logical project dependency bytes: \(ByteFormat.string(report.totalLogicalSize))")
    if report.workspaceRootCount > 0 || !report.workspaceSummaries.isEmpty {
        print("Workspace roots detected: \(report.workspaceRootCount)")
    }
    if options.includeVCSStatus || !report.vcsSummaries.isEmpty {
        print("Projects with local VCS changes: \(report.projectsWithDirtyVCSCount)")
    }

    if !report.ecosystemSummaries.isEmpty {
        print("\nBy ecosystem")
        for summary in report.ecosystemSummaries {
            print("- \(pad(summary.name, 16)) \(pad(ByteFormat.string(summary.allocatedSize), 10)) \(summary.itemCount) item(s)")
        }
    }

    if !report.kindSummaries.isEmpty {
        print("\nBy dependency kind")
        for summary in report.kindSummaries {
            print("- \(pad(summary.name, 24)) \(pad(ByteFormat.string(summary.allocatedSize), 10)) \(summary.itemCount) item(s)")
        }
    }

    if !report.toolSummaries.isEmpty {
        print("\nBy detected project tool")
        for summary in report.toolSummaries {
            print("- \(pad(summary.name, 18)) \(pad(ByteFormat.string(summary.allocatedSize), 10)) \(summary.itemCount) item(s)")
        }
    }

    if !report.scriptSummaries.isEmpty {
        print("\nBy package.json script")
        for summary in report.scriptSummaries.prefix(options.limit) {
            print("- \(pad(summary.name, 18)) \(pad(ByteFormat.string(summary.allocatedSize), 10)) \(summary.itemCount) item(s)")
        }
    }

    if !report.scriptRiskSummaries.isEmpty {
        print("\nBy package.json script risk")
        for summary in report.scriptRiskSummaries {
            print("- \(pad(summary.name, 28)) \(pad(ByteFormat.string(summary.allocatedSize), 10)) \(summary.itemCount) item(s)")
        }
    }

    if !report.workspaceSummaries.isEmpty {
        print("\nBy workspace")
        for summary in report.workspaceSummaries.prefix(options.limit) {
            print("- \(pad(summary.name, 28)) \(pad(ByteFormat.string(summary.allocatedSize), 10)) \(summary.itemCount) item(s)")
        }
    }

    if !report.vcsSummaries.isEmpty {
        print("\nBy VCS state")
        for summary in report.vcsSummaries {
            print("- \(pad(summary.name, 18)) \(pad(ByteFormat.string(summary.allocatedSize), 10)) \(summary.itemCount) item(s)")
        }
    }

    if !report.policySummaries.isEmpty {
        print("\nBy saved project policy")
        for summary in report.policySummaries {
            print("- \(pad(summary.name, 22)) \(pad(ByteFormat.string(summary.allocatedSize), 10)) \(summary.itemCount) item(s)")
        }
    }

    print("\nProject roots")
    if report.rootSummaries.isEmpty {
        print("No project roots were inspected.")
    } else {
        for root in report.rootSummaries {
            print("- \(root.permissionState.rawValue), \(ByteFormat.string(root.allocatedSize)), \(root.candidateCount) candidate(s), \(root.itemCount) measured item(s)")
            print("  \(root.rootPath)")
            print("  \(root.note)")
        }
    }

    if report.largestItems.isEmpty {
        print("\nNo project dependency candidates found in readable roots.")
    } else {
        print("\nLargest project dependency items")
        print("\(pad("Allocated", 11)) \(pad("Ecosystem", 14)) \(pad("Kind", 22)) \(pad("VCS", 18)) \(pad("Age", 8)) Path")
        for item in report.largestItems.prefix(options.limit) {
            let age = item.ageDays.map { "\($0)d" } ?? "unknown"
            print("\(pad(ByteFormat.string(item.allocatedSize), 11)) \(pad(item.ecosystem.label, 14)) \(pad(item.kind.label, 22)) \(pad(item.vcsInfo.state.label, 18)) \(pad(age, 8)) \(item.path)")
            print("  project: \(item.projectName)")
            print("  vcs: \(item.vcsInfo.summary)")
            if item.toolingInfo.toolName != nil {
                print("  tool: \(item.toolingInfo.toolLabel)\(item.toolingInfo.toolSource.map { " from \($0)" } ?? "")")
            }
            if !item.toolingInfo.packageScripts.isEmpty {
                print("  scripts: \(item.toolingInfo.packageScripts.prefix(12).joined(separator: ", "))")
            }
            if !item.toolingInfo.scriptReviews.isEmpty {
                for review in item.toolingInfo.scriptReviews.prefix(4) {
                    let hintState = review.isCommandHintEligible ? "hint eligible" : "manual review"
                    print("  script review: \(review.name) [\(review.risk.label), \(hintState)] \(review.commandPreview)")
                }
            }
            if item.workspaceInfo.isWorkspace {
                print("  workspace: \(item.workspaceInfo.label)")
                if let rootPath = item.workspaceInfo.rootPath {
                    print("  workspace root: \(rootPath)")
                }
                if !item.workspaceInfo.packagePatterns.isEmpty {
                    print("  workspace packages: \(item.workspaceInfo.packagePatterns.prefix(12).joined(separator: ", "))")
                }
            }
            if let decision = item.projectPolicyDecision {
                let reason = item.projectPolicyReason.map { " - \($0)" } ?? ""
                print("  policy: \(decision.label)\(reason)")
            }
            print("  - \(item.recommendation)")
            if !item.commandHints.isEmpty {
                for command in item.commandHints.prefix(3) {
                    print("  command hint: \(command.command) - \(command.purpose)")
                    if let workingDirectory = command.workingDirectory {
                        print("    cwd: \(workingDirectory)")
                    }
                    if let context = command.context {
                        print("    context: \(context)")
                    }
                }
            }
            if let guidance = item.guidance.first {
                print("  next: \(guidance)")
            }
        }
    }

    print("\nProtected project files")
    if report.protectedProjectRoots.isEmpty {
        print("No protected project roots were inferred from candidates.")
    } else {
        for protectedRoot in report.protectedProjectRoots {
            let manifests = protectedRoot.manifestHints.isEmpty ? "no standard manifest" : protectedRoot.manifestHints.joined(separator: ", ")
            print("- \(protectedRoot.projectName): \(manifests)")
            print("  \(protectedRoot.projectRootPath)")
            if protectedRoot.toolingInfo.toolName != nil {
                print("  tool: \(protectedRoot.toolingInfo.toolLabel)\(protectedRoot.toolingInfo.toolSource.map { " from \($0)" } ?? "")")
            }
            if !protectedRoot.toolingInfo.packageScripts.isEmpty {
                print("  scripts: \(protectedRoot.toolingInfo.packageScripts.prefix(12).joined(separator: ", "))")
            }
            if !protectedRoot.toolingInfo.scriptReviews.isEmpty {
                for review in protectedRoot.toolingInfo.scriptReviews.prefix(4) {
                    let hintState = review.isCommandHintEligible ? "hint eligible" : "manual review"
                    print("  script review: \(review.name) [\(review.risk.label), \(hintState)] \(review.commandPreview)")
                }
            }
            if protectedRoot.workspaceInfo.isWorkspace {
                print("  workspace: \(protectedRoot.workspaceInfo.label)")
                if let rootPath = protectedRoot.workspaceInfo.rootPath {
                    print("  workspace root: \(rootPath)")
                }
            }
            print("  vcs: \(protectedRoot.vcsInfo.state.label) - \(protectedRoot.vcsInfo.summary)")
            if let decision = protectedRoot.projectPolicyDecision {
                let reason = protectedRoot.projectPolicyReason.map { " - \($0)" } ?? ""
                print("  policy: \(decision.label)\(reason)")
            }
            print("  \(protectedRoot.note)")
        }
    }

    print("\nSkipped by saved project policy")
    if report.policySkippedProjects.isEmpty {
        print("No projects were skipped by saved Project Dependencies policy.")
    } else {
        for project in report.policySkippedProjects {
            let manifests = project.manifestHints.isEmpty ? "no standard manifest" : project.manifestHints.joined(separator: ", ")
            let reason = project.reason.map { " - \($0)" } ?? ""
            print("- \(project.projectName): \(project.decision.label)\(reason)")
            print("  \(project.projectRootPath)")
            if let workspace = project.workspaceInfo, workspace.isWorkspace {
                print("  workspace: \(workspace.label)")
            }
            print("  \(manifests)")
            print("  \(project.note)")
        }
    }

    print("\nGuidance")
    for line in report.guidance {
        print("- \(line)")
    }

    print("\nNon-claims")
    for note in report.nonClaims {
        print("- \(note)")
    }
}

func printDeviceBackupReview(_ report: DeviceBackupReviewReport, options: ParsedOptions) {
    print("Ryddi Device Backups review")
    print("Generated: \(report.createdAt.formatted())")
    print("Root: \(report.rootPath)")
    print("Permission: \(report.permissionState.rawValue)")
    print("Backups measured: \(report.backupCount)")
    print("Items measured: \(report.itemCount)")
    print("Allocated in device backups: \(ByteFormat.string(report.totalAllocatedSize))")
    print("Logical in device backups: \(ByteFormat.string(report.totalLogicalSize))")
    print("Old-backup review bytes: \(ByteFormat.string(report.staleBackupBytes))")
    print("Encrypted backup bytes: \(ByteFormat.string(report.encryptedBackupBytes))")
    print("Backups missing parsed metadata: \(report.missingMetadataCount)")

    if !report.notes.isEmpty {
        print("\nNotes")
        for note in report.notes {
            print("- \(note)")
        }
    }

    if !report.encryptionSummaries.isEmpty {
        print("\nBy encryption state")
        for summary in report.encryptionSummaries {
            print("- \(pad(summary.name, 15)) \(pad(ByteFormat.string(summary.allocatedSize), 10)) \(summary.backupCount) backup(s)")
        }
    }

    if !report.metadataSummaries.isEmpty {
        print("\nBy metadata state")
        for summary in report.metadataSummaries {
            print("- \(pad(summary.name, 12)) \(pad(ByteFormat.string(summary.allocatedSize), 10)) \(summary.backupCount) backup(s)")
        }
    }

    if report.largestBackups.isEmpty {
        print("\nNo device backups found at the configured root.")
    } else {
        print("\nLargest device backups")
        print("\(pad("Allocated", 11)) \(pad("Encryption", 15)) \(pad("Metadata", 12)) \(pad("Age", 8)) \(pad("Last backup", 12)) Name")
        for backup in report.largestBackups.prefix(options.limit) {
            let lastBackup = backup.lastBackupDate?.formatted(date: .numeric, time: .omitted) ?? "unknown"
            let age = backup.ageDays.map { "\($0)d" } ?? "unknown"
            print("\(pad(ByteFormat.string(backup.allocatedSize), 11)) \(pad(backup.encryptionState.label, 15)) \(pad(backup.metadataState.label, 12)) \(pad(age, 8)) \(pad(lastBackup, 12)) \(backup.displayName)")
            print("  path: \(backup.path)")
            print("  - \(backup.recommendation)")
            if let guidance = backup.guidance.first {
                print("  next: \(guidance)")
            }
        }
    }

    print("\nGuidance")
    for line in report.guidance {
        print("- \(line)")
    }

    print("\nNon-claims")
    for note in report.nonClaims {
        print("- \(note)")
    }
}

func printXcodeReview(_ report: XcodeReviewReport, options: ParsedOptions) {
    print("Ryddi Xcode review")
    print("Generated: \(report.createdAt.formatted())")
    print("Xcode roots: \(report.rootSummaries.count)")
    print("Items measured: \(report.itemCount)")
    print("Allocated Xcode bytes: \(ByteFormat.string(report.totalAllocatedSize))")
    print("Logical Xcode bytes: \(ByteFormat.string(report.totalLogicalSize))")
    print("Rebuildable cache bytes: \(ByteFormat.string(report.rebuildableCacheBytes))")
    print("Review-required bytes: \(ByteFormat.string(report.reviewRequiredBytes))")
    print("Simulator-state bytes: \(ByteFormat.string(report.simulatorStateBytes))")

    if !report.kindSummaries.isEmpty {
        print("\nBy Xcode kind")
        for summary in report.kindSummaries {
            print("- \(pad(summary.name, 22)) \(pad(ByteFormat.string(summary.allocatedSize), 10)) \(summary.itemCount) item(s)")
        }
    }

    print("\nXcode roots")
    if report.rootSummaries.isEmpty {
        print("No Xcode roots were inspected.")
    } else {
        for root in report.rootSummaries {
            print("- \(root.kind.label): \(root.permissionState.rawValue), \(ByteFormat.string(root.allocatedSize)), \(root.itemCount) item(s)")
            print("  \(root.rootPath)")
            print("  \(root.nativeCleanupHint)")
            print("  \(root.note)")
        }
    }

    if report.largestItems.isEmpty {
        print("\nNo Xcode items found in readable roots.")
    } else {
        print("\nLargest Xcode items")
        print("\(pad("Allocated", 11)) \(pad("Kind", 22)) \(pad("Age", 8)) \(pad("Modified", 12)) Path")
        for item in report.largestItems.prefix(options.limit) {
            let modified = item.modificationDate?.formatted(date: .numeric, time: .omitted) ?? "unknown"
            let age = item.ageDays.map { "\($0)d" } ?? "unknown"
            print("\(pad(ByteFormat.string(item.allocatedSize), 11)) \(pad(item.kind.label, 22)) \(pad(age, 8)) \(pad(modified, 12)) \(item.path)")
            print("  - \(item.recommendation)")
            if let guidance = item.guidance.first {
                print("  next: \(guidance)")
            }
        }
    }

    print("\nProtected Xcode developer state")
    for protectedRoot in report.protectedStateRoots {
        print("- \(protectedRoot.permissionState.rawValue) - \(protectedRoot.path)")
        print("  \(protectedRoot.note)")
    }

    print("\nGuidance")
    for line in report.guidance {
        print("- \(line)")
    }

    print("\nNon-claims")
    for note in report.nonClaims {
        print("- \(note)")
    }
}

func printTrashReview(_ report: TrashReviewReport, options: ParsedOptions) {
    print("Ryddi Trash review")
    print("Generated: \(report.createdAt.formatted())")
    print("Root: \(report.rootPath)")
    print("Permission: \(report.permissionState.rawValue)")
    print("Items measured: \(report.itemCount)")
    print("Allocated in Trash: \(ByteFormat.string(report.totalAllocatedSize))")
    print("Logical in Trash: \(ByteFormat.string(report.totalLogicalSize))")

    if !report.notes.isEmpty {
        print("\nNotes")
        for note in report.notes {
            print("- \(note)")
        }
    }

    if report.largestItems.isEmpty {
        print("\nNo Trash items found at the configured root.")
    } else {
        print("\nLargest Trash items")
        print("\(pad("Allocated", 11)) \(pad("Logical", 11)) \(pad("Items", 8)) \(pad("Next", 18)) \(pad("Modified", 12)) Path")
        for item in report.largestItems.prefix(options.limit) {
            let modified = item.modificationDate?.formatted(date: .numeric, time: .omitted) ?? "unknown"
            print("\(pad(ByteFormat.string(item.allocatedSize), 11)) \(pad(ByteFormat.string(item.logicalSize), 11)) \(pad("\(item.itemCount)", 8)) \(pad(item.nextAction.label, 18)) \(pad(modified, 12)) \(item.path)")
            if let guidance = item.guidance.first {
                print("  - \(guidance)")
            }
        }
    }

    print("\nGuidance")
    for line in report.guidance {
        print("- \(line)")
    }

    print("\nNon-claims")
    for note in report.nonClaims {
        print("- \(note)")
    }
}
