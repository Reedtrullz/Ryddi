import Foundation
import ReclaimerCore

@main
struct ReclaimerCLI {
    static func main() {
        do {
            try run(arguments: Array(CommandLine.arguments.dropFirst()))
        } catch {
            FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
            Foundation.exit(1)
        }
    }

    static func run(arguments: [String]) throws {
        guard let command = arguments.first else {
            printHelp()
            return
        }

        let args = Array(arguments.dropFirst())
        switch command {
        case "status":
            try status(args: args)
        case "overview":
            try overview(args: args)
        case "drilldown":
            try drilldown(args: args)
        case "scopes":
            try scopes(args: args)
        case "rules":
            try rules(args: args)
        case "report":
            try report(args: args)
        case "permissions":
            try permissions(args: args)
        case "active":
            try active(args: args)
        case "history":
            try history(args: args)
        case "duplicates":
            try duplicates(args: args)
        case "apps":
            try apps(args: args)
        case "agents":
            try agents(args: args)
        case "native":
            try native(args: args)
        case "containers":
            try containers(args: args)
        case "policy":
            try policy(args: args)
        case "scan":
            try scan(args: args)
        case "plan":
            try plan(args: args)
        case "plans":
            try plans(args: args)
        case "explain":
            try explain(args: args)
        case "execute":
            try execute(args: args)
        case "receipts":
            try receipts(args: args)
        case "recovery":
            try recovery(args: args)
        case "archive":
            try archive(args: args)
        case "schedule":
            try schedule(args: args)
        case "holding":
            try holding(args: args)
        case "help", "--help", "-h":
            printHelp()
        default:
            throw CLIError.message("Unknown command: \(command)")
        }
    }

    static func scan(args: [String]) throws {
        let options = ParsedOptions(args)
        let scanner = try FileScanner(ruleEngine: try options.ruleEngine(), openFileChecker: options.noLsof ? NoOpenFilesChecker() : LsofOpenFileChecker())
        let findings = scanner.scan(
            scopes: try options.scopes(includeUnavailable: options.includeMissingScopes),
            options: options.scanOptions(includeOpenFiles: options.includeOpenFiles)
        )
        let preparedFindings = options.prepare(findings)
        if options.json {
            printJSON(preparedFindings)
        } else {
            printFindings(preparedFindings, options: options)
        }
    }

    static func status(args: [String]) throws {
        let options = ParsedOptions(args)
        let path = options.values(after: "--path").first ?? "/System/Volumes/Data"
        let snapshot = DiskStatusReader().snapshot(for: URL(fileURLWithPath: path))
        if options.json {
            printJSON(snapshot)
        } else {
            printDiskStatus(snapshot)
        }
    }

    static func overview(args: [String]) throws {
        let options = ParsedOptions(args)
        let scopes = try options.scopes(includeUnavailable: true)
        let scanner = try FileScanner(ruleEngine: try options.ruleEngine(), openFileChecker: options.noLsof ? NoOpenFilesChecker() : LsofOpenFileChecker())
        let findings = scanner.scan(scopes: scopes, options: options.scanOptions(includeOpenFiles: options.includeOpenFiles))
        let overview = FindingAnalytics.overview(
            findings: findings,
            scopes: scopes,
            topLimit: options.limit,
            offenderSort: try options.topOffenderSort(),
            offenderGroup: try options.topOffenderGroup()
        )
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

    static func scopes(args: [String]) throws {
        if args.first == "saved" {
            try savedScopes(args: Array(args.dropFirst()))
            return
        }
        let options = ParsedOptions(args)
        let plan = try options.scopePlan(includeUnavailable: true)
        if options.json {
            printJSON(plan)
        } else {
            printScopePlan(plan)
        }
    }

    static func savedScopes(args: [String]) throws {
        guard let subcommand = args.first else {
            throw CLIError.message("scopes saved requires list, show, add, remove, export, or import")
        }
        let options = ParsedOptions(Array(args.dropFirst()))
        let store = SavedScopeSetStore()
        switch subcommand {
        case "list":
            let document = try store.loadDocument()
            if options.json {
                printJSON(document)
            } else {
                printSavedScopeSetDocument(document, path: store.scopeSetURL.path)
            }
        case "show":
            guard args.indices.contains(1), !args[1].hasPrefix("-") else {
                throw CLIError.message("scopes saved show requires a saved scope set name or id")
            }
            let set = try store.find(args[1])
            if options.json {
                printJSON(set)
            } else {
                printSavedScopeSet(set)
            }
        case "add":
            guard args.indices.contains(1), !args[1].hasPrefix("-") else {
                throw CLIError.message("scopes saved add requires a name and at least one --path")
            }
            let set = try store.upsert(name: args[1], paths: options.values(after: "--path"), summary: options.summary)
            if options.json {
                printJSON(set)
            } else {
                print("saved scope set: \(set.name)")
                printSavedScopeSet(set)
            }
        case "remove":
            guard args.indices.contains(1), !args[1].hasPrefix("-") else {
                throw CLIError.message("scopes saved remove requires a saved scope set name or id")
            }
            let document = try store.remove(reference: args[1])
            if options.json {
                printJSON(document)
            } else {
                print("removed saved scope set: \(args[1])")
                printSavedScopeSetDocument(document, path: store.scopeSetURL.path)
            }
        case "export":
            let document = try store.exportDocument()
            if let output = options.outputPath {
                let url = URL(fileURLWithPath: output).standardizedFileURL
                _ = try store.writeExport(document, to: url)
                FileHandle.standardError.write(Data("wrote saved scope sets export: \(url.path)\n".utf8))
            }
            if options.json || options.outputPath == nil {
                printJSON(document)
            } else {
                printSavedScopeSetDocument(document, path: store.scopeSetURL.path)
            }
        case "import":
            guard args.indices.contains(1), !args[1].hasPrefix("-") else {
                throw CLIError.message("scopes saved import requires a saved scope sets JSON path")
            }
            let result = try store.importDocument(from: URL(fileURLWithPath: args[1]).standardizedFileURL, merge: !options.replacePolicy)
            if options.json {
                printJSON(result)
            } else {
                printSavedScopeSetImportResult(result)
            }
        default:
            throw CLIError.message("Unknown scopes saved subcommand: \(subcommand)")
        }
    }

    static func rules(args: [String]) throws {
        if args.first == "user" {
            try rulesUser(args: Array(args.dropFirst()))
            return
        }
        let options = ParsedOptions(args)
        let catalog = try options.ruleEngine().catalog()
        if options.json {
            printJSON(catalog)
        } else {
            printRuleCatalog(catalog)
        }
    }

    static func rulesUser(args: [String]) throws {
        guard let subcommand = args.first else {
            throw CLIError.message("rules user requires list, preview, import, or export")
        }
        let options = ParsedOptions(Array(args.dropFirst()))
        let store = UserRulePackStore()
        switch subcommand {
        case "list":
            let document = try store.loadDocument()
            if options.json {
                printJSON(document)
            } else {
                printUserRulePackDocument(document, path: store.rulePackURL.path)
            }
        case "preview":
            guard args.indices.contains(1), !args[1].hasPrefix("-") else {
                throw CLIError.message("rules user preview requires a rule pack JSON path")
            }
            let sourceURL = URL(fileURLWithPath: args[1]).standardizedFileURL
            let preview = try store.preview(from: sourceURL)
            if options.json {
                printJSON(preview)
            } else {
                printUserRulePackPreview(preview)
            }
        case "import":
            guard args.indices.contains(1), !args[1].hasPrefix("-") else {
                throw CLIError.message("rules user import requires a rule pack JSON path")
            }
            let sourceURL = URL(fileURLWithPath: args[1]).standardizedFileURL
            let result = try store.importDocument(from: sourceURL, merge: !options.replacePolicy)
            if options.json {
                printJSON(result)
            } else {
                printUserRulePackImportResult(result)
            }
        case "export":
            let document = try store.exportDocument()
            if let output = options.outputPath {
                let url = URL(fileURLWithPath: output).standardizedFileURL
                _ = try store.writeExport(document, to: url)
                FileHandle.standardError.write(Data("wrote user rule pack export: \(url.path)\n".utf8))
            }
            if options.json || options.outputPath == nil {
                printJSON(document)
            } else {
                printUserRulePackDocument(document, path: store.rulePackURL.path)
            }
        default:
            throw CLIError.message("Unknown rules user subcommand: \(subcommand)")
        }
    }

    static func report(args: [String]) throws {
        let options = ParsedOptions(args)
        try options.validateReportPrivacyOptions()
        let scopes = try options.scopes(includeUnavailable: true)
        let scanner = try FileScanner(ruleEngine: try options.ruleEngine(), openFileChecker: options.noLsof ? NoOpenFilesChecker() : LsofOpenFileChecker())
        let findings = scanner.scan(scopes: scopes, options: options.scanOptions(includeOpenFiles: options.includeOpenFiles))
        let overview = FindingAnalytics.overview(findings: findings, scopes: scopes, topLimit: options.limit)
        let report = EvidenceReportBuilder.build(
            title: options.reportTitle,
            overview: overview,
            findings: findings,
            scopes: scopes,
            diskStatus: DiskStatusReader().snapshot(),
            userPathPolicy: options.userPathPolicy,
            topLimit: options.limit,
            privacy: options.reportPrivacy
        )

        if let output = options.outputPath {
            let url = URL(fileURLWithPath: output).standardizedFileURL
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try report.markdown.write(to: url, atomically: true, encoding: .utf8)
            FileHandle.standardError.write(Data("wrote evidence report: \(url.path)\n".utf8))
        }
        if options.saveReport {
            let url = try ReportStore().save(report: report)
            FileHandle.standardError.write(Data("saved evidence report: \(url.path)\n".utf8))
        }
        if options.json {
            printJSON(report)
        } else if options.outputPath == nil {
            print(report.markdown)
        }
    }

    static func permissions(args: [String]) throws {
        if args.first == "guide" {
            try permissionGuide(args: Array(args.dropFirst()))
            return
        }
        let options = ParsedOptions(args)
        let report = PermissionAdvisor.report(scopes: try options.scopes(includeUnavailable: true))
        if options.json {
            printJSON(report)
        } else {
            printPermissionAdvisorReport(report)
        }
    }

    static func permissionGuide(args: [String]) throws {
        let options = ParsedOptions(args)
        let report = PermissionAdvisor.report(scopes: try options.scopes(includeUnavailable: true))
        let walkthrough = PermissionWalkthroughBuilder.build(report: report)
        if let output = options.outputPath {
            let url = URL(fileURLWithPath: output).standardizedFileURL
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try walkthrough.markdown.write(to: url, atomically: true, encoding: .utf8)
            FileHandle.standardError.write(Data("wrote permission walkthrough: \(url.path)\n".utf8))
        }
        if options.json {
            printJSON(walkthrough)
        } else if options.outputPath == nil {
            print(walkthrough.markdown)
        }
    }

    static func active(args: [String]) throws {
        let options = ParsedOptions(args)
        let scopes = try options.scopes(includeUnavailable: true)
        let scanner = try FileScanner(ruleEngine: try options.ruleEngine(), openFileChecker: NoOpenFilesChecker())
        let findings = scanner.scan(scopes: scopes, options: options.scanOptions(includeOpenFiles: false))
        let report = ActiveFileReviewScanner(openFileChecker: LsofOpenFileChecker()).review(
            findings: options.prepare(findings),
            options: ActiveFileReviewOptions(limit: options.limit)
        )
        if options.saveAudit {
            let url = try AuditStore().save(activeFileReviewReport: report)
            FileHandle.standardError.write(Data("saved active-file report: \(url.path)\n".utf8))
        }
        if options.json {
            printJSON(report)
        } else {
            printActiveFileReviewReport(report)
        }
    }


    static func history(args: [String]) throws {
        guard let subcommand = args.first else {
            throw CLIError.message("history requires record, list, diff, or report")
        }
        let options = ParsedOptions(Array(args.dropFirst()))
        let store = ScanHistoryStore()
        switch subcommand {
        case "record":
            let scopes = try options.scopes(includeUnavailable: true)
            let scanner = try FileScanner(ruleEngine: try options.ruleEngine(), openFileChecker: options.noLsof ? NoOpenFilesChecker() : LsofOpenFileChecker())
            let findings = scanner.scan(scopes: scopes, options: options.scanOptions(includeOpenFiles: options.includeOpenFiles))
            let overview = FindingAnalytics.overview(findings: findings, scopes: scopes, topLimit: options.limit)
            let snapshot = FindingAnalytics.snapshot(from: overview)
            let url = try store.save(snapshot: snapshot)
            if options.json {
                printJSON(snapshot)
            } else {
                print("saved scan snapshot: \(url.path)")
                printSnapshot(snapshot)
            }
        case "list":
            let snapshots = store.recent(limit: options.limit)
            if options.json {
                printJSON(snapshots)
            } else {
                printSnapshots(snapshots)
            }
        case "diff":
            let snapshots = store.recent(limit: 2)
            guard snapshots.count == 2 else {
                throw CLIError.message("history diff requires at least two saved scan snapshots")
            }
            let deltas = FindingAnalytics.growthDeltas(
                previous: snapshots[1],
                current: snapshots[0],
                group: options.growthGroup
            )
            if options.json {
                printJSON(deltas)
            } else {
                printGrowthDeltas(deltas, group: options.growthGroup, current: snapshots[0], previous: snapshots[1], limit: options.limit)
            }
        case "report":
            try options.validateReportPrivacyOptions()
            let current: ScanSnapshot
            let previous: ScanSnapshot
            if options.currentSnapshotID != nil || options.previousSnapshotID != nil {
                guard let currentID = options.currentSnapshotID, let previousID = options.previousSnapshotID else {
                    throw CLIError.message("history report requires both --current-id and --previous-id when comparing explicit snapshots")
                }
                guard let foundCurrent = store.snapshot(id: currentID) else {
                    throw CLIError.message("No saved scan snapshot found for --current-id \(currentID)")
                }
                guard let foundPrevious = store.snapshot(id: previousID) else {
                    throw CLIError.message("No saved scan snapshot found for --previous-id \(previousID)")
                }
                current = foundCurrent
                previous = foundPrevious
            } else {
                let snapshots = store.recent(limit: 2)
                guard snapshots.count == 2 else {
                    throw CLIError.message("history report requires at least two saved scan snapshots")
                }
                current = snapshots[0]
                previous = snapshots[1]
            }
            let report = GrowthReportBuilder.build(
                title: options.growthReportTitle,
                previous: previous,
                current: current,
                group: options.growthGroup,
                limit: options.limit,
                privacy: options.reportPrivacy
            )
            if let output = options.outputPath {
                let url = URL(fileURLWithPath: output).standardizedFileURL
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try report.markdown.write(to: url, atomically: true, encoding: .utf8)
                FileHandle.standardError.write(Data("wrote growth report: \(url.path)\n".utf8))
            }
            if options.saveReport {
                let url = try ReportStore().save(growthReport: report)
                FileHandle.standardError.write(Data("saved growth report: \(url.path)\n".utf8))
            }
            if options.json {
                printJSON(report)
            } else if options.outputPath == nil {
                print(report.markdown)
            }
        default:
            throw CLIError.message("Unknown history subcommand: \(subcommand)")
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

    static func apps(args: [String]) throws {
        if args.first == "uninstall-preview" {
            try appUninstallPreview(args: Array(args.dropFirst()))
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
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try markdown.write(to: url, atomically: true, encoding: .utf8)
            FileHandle.standardError.write(Data("wrote app uninstall preview: \(url.path)\n".utf8))
        }
        if options.json {
            printJSON(preview)
        } else if options.outputPath == nil {
            printAppUninstallPreview(preview, options: options)
        }
    }

    static func agents(args: [String]) throws {
        let options = ParsedOptions(args)
        let scopes: [ScanScope]
        if options.hasCustomScopeSelection {
            scopes = try options.scopes(includeUnavailable: options.includeMissingScopes)
        } else {
            scopes = DefaultScopes.aiAgentStorage(includeUnavailable: options.includeMissingScopes)
        }
        let scanner = try FileScanner(ruleEngine: try options.ruleEngine(), openFileChecker: options.noLsof ? NoOpenFilesChecker() : LsofOpenFileChecker())
        let findings = scanner.scan(scopes: scopes, options: options.scanOptions(includeOpenFiles: false))
        let report = AgentStorageReviewBuilder.build(
            findings: options.prepare(findings),
            scopes: scopes,
            limit: options.limit
        )
        if options.json {
            printJSON(report)
        } else {
            printAgentStorageReview(report, options: options)
        }
    }

    static func native(args: [String]) throws {
        let options = ParsedOptions(args)
        let scanner = try FileScanner(ruleEngine: try options.ruleEngine(), openFileChecker: options.noLsof ? NoOpenFilesChecker() : LsofOpenFileChecker())
        let findings = scanner.scan(scopes: try options.scopes(), options: options.scanOptions(includeOpenFiles: false))
        let report = NativeToolGuidance.report(for: findings, ruleVersion: try options.ruleEngine().version)
        if options.saveAudit {
            let url = try AuditStore().save(nativeToolReport: report)
            FileHandle.standardError.write(Data("saved native-tool report: \(url.path)\n".utf8))
        }
        if options.json {
            printJSON(report)
        } else {
            printNativeToolReport(report, options: options)
        }
    }

    static func containers(args: [String]) throws {
        let options = ParsedOptions(args)
        let report = ContainerInventoryScanner(timeout: options.timeoutSeconds).inspect()
        if options.saveAudit {
            let url = try AuditStore().save(containerInventoryReport: report)
            FileHandle.standardError.write(Data("saved container inventory report: \(url.path)\n".utf8))
        }
        if options.json {
            printJSON(report)
        } else {
            printContainerInventoryReport(report, options: options)
        }
    }

    static func policy(args: [String]) throws {
        guard let subcommand = args.first else {
            throw CLIError.message("policy requires list, protect, exclude, remove, export, or import")
        }
        let options = ParsedOptions(Array(args.dropFirst()))
        let store = UserPathPolicyStore()
        switch subcommand {
        case "list":
            let policy = store.load()
            if options.json {
                printJSON(policy)
            } else {
                printUserPathPolicy(policy)
            }
        case "protect", "exclude":
            guard args.indices.contains(1), !args[1].hasPrefix("-") else {
                throw CLIError.message("policy \(subcommand) requires a path")
            }
            let kind: UserPathPolicyKind = subcommand == "protect" ? .protect : .exclude
            let policy = try store.add(path: args[1], kind: kind, reason: options.reason)
            if options.json {
                printJSON(policy)
            } else {
                print("saved \(kind.label): \(UserPathPolicy.standardizedPath(args[1]))")
                printUserPathPolicy(policy)
            }
        case "remove":
            guard args.indices.contains(1), !args[1].hasPrefix("-") else {
                throw CLIError.message("policy remove requires a path")
            }
            let kind = options.policyKind
            let policy = try store.remove(path: args[1], kind: kind)
            if options.json {
                printJSON(policy)
            } else {
                print("removed policy entries for: \(UserPathPolicy.standardizedPath(args[1]))")
                printUserPathPolicy(policy)
            }
        case "export":
            let document = store.exportDocument()
            if let output = options.outputPath {
                let url = URL(fileURLWithPath: output).standardizedFileURL
                _ = try store.writeExport(document, to: url)
                FileHandle.standardError.write(Data("wrote user path policy export: \(url.path)\n".utf8))
            }
            if options.json || options.outputPath == nil {
                printJSON(document)
            } else {
                printPolicyExportSummary(document)
            }
        case "import":
            guard args.indices.contains(1), !args[1].hasPrefix("-") else {
                throw CLIError.message("policy import requires a policy JSON path")
            }
            let sourceURL = URL(fileURLWithPath: args[1]).standardizedFileURL
            let result = try store.importDocument(from: sourceURL, merge: !options.replacePolicy)
            if options.json {
                printJSON(result)
            } else {
                printPolicyImportResult(result)
            }
        default:
            throw CLIError.message("Unknown policy subcommand: \(subcommand)")
        }
    }

    static func plan(args: [String]) throws {
        let options = ParsedOptions(args)
        try options.validateReportPrivacyOptions()
        let scanner = try FileScanner(ruleEngine: try options.ruleEngine(), openFileChecker: options.noLsof ? NoOpenFilesChecker() : LsofOpenFileChecker())
        let findings = scanner.scan(scopes: try options.scopes(), options: options.scanOptions(includeOpenFiles: false))
        let builder = PlanBuilder(openFileChecker: options.noLsof ? NoOpenFilesChecker() : LsofOpenFileChecker())
        let plan = builder.buildPlan(from: findings, mode: options.reviewAll ? .reviewAll : .autoSafeOnly)
        if options.saveAudit {
            let url = try AuditStore().save(plan: plan)
            FileHandle.standardError.write(Data("saved plan: \(url.path)\n".utf8))
        }
        if options.outputPath != nil || options.saveReport {
            let report = ReclaimPlanReportBuilder.build(
                title: options.planReportTitle,
                plan: plan,
                itemLimit: options.limit,
                privacy: options.reportPrivacy
            )
            if let output = options.outputPath {
                let url = URL(fileURLWithPath: output).standardizedFileURL
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try report.markdown.write(to: url, atomically: true, encoding: .utf8)
                FileHandle.standardError.write(Data("wrote plan report: \(url.path)\n".utf8))
            }
            if options.saveReport {
                let url = try ReportStore().save(planReport: report)
                FileHandle.standardError.write(Data("saved plan report: \(url.path)\n".utf8))
            }
        }
        if options.json {
            printJSON(plan)
        } else if options.outputPath == nil {
            printPlan(plan)
        }
    }

    static func plans(args: [String]) throws {
        let subcommand = args.first ?? "list"
        let options = ParsedOptions(Array(args.dropFirst()))
        try options.validateReportPrivacyOptions()
        let store = AuditStore()
        switch subcommand {
        case "list":
            let plans = store.recentPlans(limit: options.limit)
            if options.json {
                printJSON(plans)
            } else {
                printPlans(plans)
            }
        case "export":
            let plan = options.planID.flatMap { store.plan(id: $0) }
                ?? store.recentPlans(limit: 1).first
            guard let plan else {
                throw CLIError.message("No saved plan found. Run plan --save-audit first, or pass --id for an existing plan.")
            }
            let report = ReclaimPlanReportBuilder.build(
                title: options.planReportTitle,
                plan: plan,
                itemLimit: options.limit,
                privacy: options.reportPrivacy
            )
            if let output = options.outputPath {
                let url = URL(fileURLWithPath: output).standardizedFileURL
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try report.markdown.write(to: url, atomically: true, encoding: .utf8)
                FileHandle.standardError.write(Data("wrote plan report: \(url.path)\n".utf8))
            }
            if options.saveReport {
                let url = try ReportStore().save(planReport: report)
                FileHandle.standardError.write(Data("saved plan report: \(url.path)\n".utf8))
            }
            if options.json {
                printJSON(report)
            } else if options.outputPath == nil {
                print(report.markdown)
            }
        default:
            throw CLIError.message("Unknown plans subcommand: \(subcommand)")
        }
    }

    static func explain(args: [String]) throws {
        guard let path = args.first, !path.hasPrefix("-") else {
            throw CLIError.message("explain requires a path")
        }
        let options = ParsedOptions(args)
        let scanner = try FileScanner(ruleEngine: try options.ruleEngine(), openFileChecker: options.noLsof ? NoOpenFilesChecker() : LsofOpenFileChecker())
        let scope = ScanScope(name: "Explain", root: URL(fileURLWithPath: path).standardizedFileURL)
        let findings = scanner.scan(scopes: [scope], options: options.scanOptions(includeOpenFiles: true))
        guard let finding = findings.first else {
            throw CLIError.message("No finding produced for \(path)")
        }
        if options.json {
            printJSON(finding)
        } else {
            printFindingDetail(finding)
        }
    }

    static func execute(args: [String]) throws {
        let options = ParsedOptions(args)
        if options.yes && options.noLsof && !options.dryRun {
            throw CLIError.message("--no-lsof is only allowed for dry-run planning; execute --yes requires open-file checks.")
        }
        let scanner = try FileScanner(ruleEngine: try options.ruleEngine(), openFileChecker: options.noLsof ? NoOpenFilesChecker() : LsofOpenFileChecker())
        let findings = scanner.scan(scopes: try options.scopes(), options: options.scanOptions(includeOpenFiles: false))
        let builder = PlanBuilder(openFileChecker: options.noLsof ? NoOpenFilesChecker() : LsofOpenFileChecker())
        let plan = builder.buildPlan(from: findings, mode: options.reviewAll ? .reviewAll : .autoSafeOnly)
        let receipt = ReclaimerExecutor(
            openFileChecker: options.noLsof ? NoOpenFilesChecker() : LsofOpenFileChecker(),
            configuration: ExecutorConfiguration(userPathPolicy: options.userPathPolicy)
        )
            .execute(
                plan: plan,
                mode: options.dryRun ? .dryRun : .perform,
                ruleVersion: try options.ruleEngine().version,
                userConfirmed: options.yes
            )
        if options.saveAudit {
            let url = try AuditStore().save(receipt: receipt)
            FileHandle.standardError.write(Data("saved receipt: \(url.path)\n".utf8))
        }
        if options.json {
            printJSON(receipt)
        } else {
            printReceipt(receipt)
        }
    }

    static func receipts(args: [String]) throws {
        let subcommand = args.first ?? "list"
        let options = ParsedOptions(Array(args.dropFirst()))
        try options.validateReportPrivacyOptions()
        let store = AuditStore()
        switch subcommand {
        case "list":
            let receipts = store.recentReceipts(limit: options.limit)
            if options.json {
                printJSON(receipts)
            } else {
                printReceipts(receipts)
            }
        case "export":
            let receipt = options.receiptID.flatMap { store.receipt(id: $0) }
                ?? store.recentReceipts(limit: 1).first
            guard let receipt else {
                throw CLIError.message("No saved receipt found. Run execute --dry-run --save-audit first, or pass --id for an existing receipt.")
            }
            let report = ExecutionReceiptReportBuilder.build(
                title: options.receiptReportTitle,
                receipt: receipt,
                privacy: options.reportPrivacy
            )
            if let output = options.outputPath {
                let url = URL(fileURLWithPath: output).standardizedFileURL
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try report.markdown.write(to: url, atomically: true, encoding: .utf8)
                FileHandle.standardError.write(Data("wrote receipt report: \(url.path)\n".utf8))
            }
            if options.saveReport {
                let url = try ReportStore().save(executionReceiptReport: report)
                FileHandle.standardError.write(Data("saved receipt report: \(url.path)\n".utf8))
            }
            if options.json {
                printJSON(report)
            } else if options.outputPath == nil {
                print(report.markdown)
            }
        default:
            throw CLIError.message("Unknown receipts subcommand: \(subcommand)")
        }
    }

    static func recovery(args: [String]) throws {
        let subcommand = (args.first?.hasPrefix("-") ?? true) ? "list" : (args.first ?? "list")
        let options = ParsedOptions(subcommand == "list" && !(args.first?.hasPrefix("-") ?? false) ? Array(args.dropFirst()) : args)
        switch subcommand {
        case "list":
            let report = RecoveryCenter.build(limit: options.limit)
            if options.json {
                printJSON(report)
            } else {
                printRecoveryCenter(report)
            }
        case "restore":
            guard args.indices.contains(1), !args[1].hasPrefix("-") else {
                throw CLIError.message("recovery restore requires a holding item id")
            }
            let rawID = args[1].hasPrefix("holding:")
                ? String(args[1].dropFirst("holding:".count))
                : args[1]
            let destination = options.value(after: "--to").map { URL(fileURLWithPath: $0).standardizedFileURL }
            let restored = try HoldingStore().restore(id: rawID, to: destination)
            print("restored: \(restored.path)")
        default:
            throw CLIError.message("Unknown recovery subcommand: \(subcommand)")
        }
    }

    static func archive(args: [String]) throws {
        var archiveArgs = args
        if !archiveArgs.contains("--review-all") {
            archiveArgs.append("--review-all")
        }
        try plan(args: archiveArgs)
    }

    static func schedule(args: [String]) throws {
        guard let subcommand = args.first else {
            throw CLIError.message("schedule requires install, uninstall, or status")
        }
        let manager = LaunchAgentManager()
        switch subcommand {
        case "install":
            let cli = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL.path
            let options = ParsedOptions(args)
            let url = try manager.install(cliPath: cli, schedule: ScheduleConfiguration(hour: options.hour, minute: options.minute))
            print("installed launch agent plist: \(url.path)")
            if args.contains("--load") {
                try manager.load()
                print("loaded launch agent")
            } else {
                print("load with: launchctl bootstrap gui/$(id -u) \(url.path)")
            }
        case "uninstall":
            if args.contains("--unload") {
                try? manager.unload()
            }
            try manager.uninstall()
            print("removed launch agent plist if present")
        case "status":
            let path = manager.installedPath()
            print(FileManager.default.fileExists(atPath: path.path) ? "installed: \(path.path)" : "not installed")
        default:
            throw CLIError.message("Unknown schedule subcommand: \(subcommand)")
        }
    }

    static func holding(args: [String]) throws {
        guard let subcommand = args.first else {
            throw CLIError.message("holding requires list, restore, or expire")
        }
        let options = ParsedOptions(args)
        let store = HoldingStore()
        switch subcommand {
        case "list":
            let items = store.list()
            if options.json {
                printJSON(items)
            } else {
                printHeldItems(items)
            }
        case "restore":
            guard args.indices.contains(1), !args[1].hasPrefix("-") else {
                throw CLIError.message("holding restore requires a held item id")
            }
            let destination = options.value(after: "--to").map { URL(fileURLWithPath: $0).standardizedFileURL }
            let restored = try store.restore(id: args[1], to: destination)
            print("restored: \(restored.path)")
        case "expire":
            let days = Double(options.value(after: "--older-than-days") ?? "") ?? 30
            guard days >= 0 else {
                throw CLIError.message("--older-than-days must be zero or greater")
            }
            let cutoff = Date().addingTimeInterval(-days * 24 * 60 * 60)
            let expired = try store.expire(olderThan: cutoff, dryRun: !options.yes)
            if options.yes {
                print("expired \(expired.count) held item(s)")
            } else {
                print("would expire \(expired.count) held item(s); pass --yes to remove")
                printHeldItems(expired)
            }
        default:
            throw CLIError.message("Unknown holding subcommand: \(subcommand)")
        }
    }

    static func printHelp() {
        print(
            """
            Ryddi

            Commands:
              status [--json] [--path PATH]
              scopes [--json] [--preset developer|general|all] [--path PATH ...] [--scope-set NAME_OR_ID]
              scopes saved list [--json]
              scopes saved show NAME_OR_ID [--json]
              scopes saved add NAME --path PATH ... [--summary TEXT] [--json]
              scopes saved remove NAME_OR_ID [--json]
              scopes saved export [--json] [--output PATH]
              scopes saved import PATH [--json] [--replace]
              scan [--json] [--preset developer|general|all] [--path PATH ...] [--scope-set NAME_OR_ID] [--min-size BYTES] [--max-depth N] [--include-open-files]
                   [--sort size|logical|age|risk|category|scope] [--group category|safety|scope]
                   [--review large|old|all] [--limit N] [--include-missing-scopes] [--ignore-user-policy] [--include-user-rules]
              overview [--json] [--preset developer|general|all] [--path PATH ...] [--scope-set NAME_OR_ID] [--limit N]
                       [--sort size|logical|reclaim|age|risk|category|safety|scope|owner|action]
                       [--group none|category|safety|owner|scope|action]
                       [--save-history] [--ignore-user-policy] [--include-user-rules]
              drilldown [--json] [--preset developer|general|all] [--path PATH ...] [--scope-set NAME_OR_ID] [--min-size BYTES] [--max-depth N]
                        [--tree-depth N] [--limit N] [--include-missing-scopes] [--ignore-user-policy] [--include-user-rules]
              rules [--json] [--include-user-rules]
              rules user list [--json]
              rules user preview PATH [--json]
              rules user import PATH [--json] [--replace]
              rules user export [--json] [--output PATH]
              report [--json] [--preset developer|general|all] [--path PATH ...] [--scope-set NAME_OR_ID] [--limit N] [--output PATH] [--save-report]
                     [--title TEXT] [--path-style full|home-relative|redacted] [--redact-user-text]
                     [--include-missing-scopes] [--ignore-user-policy] [--include-user-rules]
              permissions [--json] [--preset developer|general|all] [--path PATH ...] [--scope-set NAME_OR_ID] [--include-missing-scopes]
              permissions guide [--json] [--preset developer|general|all] [--path PATH ...] [--scope-set NAME_OR_ID] [--output PATH] [--include-missing-scopes]
              active [--json] [--preset developer|general|all] [--path PATH ...] [--scope-set NAME_OR_ID] [--min-size BYTES] [--max-depth N] [--limit N] [--save-audit] [--include-user-rules]
              history record [--json] [--preset developer|general|all] [--path PATH ...] [--scope-set NAME_OR_ID] [--limit N]
              history list [--json] [--limit N]
              history diff [--json] [--group category|safety|scope] [--limit N]
              history report [--json] [--group category|safety|scope] [--limit N]
                             [--current-id ID --previous-id ID] [--output PATH] [--save-report]
                             [--title TEXT] [--path-style full|home-relative|redacted] [--redact-user-text]
              duplicates [--json] --path PATH ... [--min-size BYTES] [--max-depth N] [--limit N]
                         [--max-files N] [--include-preserve] [--skip-hidden] [--show-excluded]
              apps [--json] [--path APP_ROOT ...] [--home HOME] [--min-size BYTES] [--limit N]
                   [--include-system-apps] [--no-orphans] [--show-excluded]
              apps uninstall-preview [--json] (--app PATH | --bundle-id ID | --name NAME)
                   [--path APP_ROOT ...] [--home HOME] [--min-size BYTES] [--limit N] [--output PATH]
                   [--save-audit] [--path-style full|home-relative|redacted] [--redact-user-text]
              agents [--json] [--path PATH ...] [--scope-set NAME_OR_ID] [--min-size BYTES] [--max-depth N] [--limit N]
                     [--include-missing-scopes] [--ignore-user-policy] [--include-user-rules]
              native [--json] [--preset developer|general|all] [--path PATH ...] [--scope-set NAME_OR_ID] [--limit N] [--save-audit] [--include-user-rules]
              containers [--json] [--limit N] [--timeout SECONDS] [--save-audit]
              policy list [--json]
              policy protect PATH [--reason TEXT]
              policy exclude PATH [--reason TEXT]
              policy remove PATH [--kind protect|exclude]
              policy export [--json] [--output PATH]
              policy import PATH [--json] [--replace]
              plan [--json] [--preset developer|general|all] [--path PATH ...] [--scope-set NAME_OR_ID] [--review-all] [--save-audit] [--ignore-user-policy] [--include-user-rules]
                   [--output PATH] [--save-report] [--title TEXT]
                   [--path-style full|home-relative|redacted] [--redact-user-text]
              plans list [--json] [--limit N]
              plans export [--json] [--id ID] [--output PATH] [--save-report] [--title TEXT]
                           [--path-style full|home-relative|redacted] [--redact-user-text]
              explain PATH [--json] [--include-user-rules]
              execute --dry-run [--json] [--preset developer|general|all] [--path PATH ...] [--scope-set NAME_OR_ID] [--save-audit] [--ignore-user-policy] [--include-user-rules]
              execute --yes [--preset developer|general|all] [--path PATH ...] [--scope-set NAME_OR_ID] [--review-all] [--save-audit] [--ignore-user-policy] [--include-user-rules]
              receipts list [--json] [--limit N]
              receipts export [--json] [--id ID] [--output PATH] [--save-report] [--title TEXT]
                              [--path-style full|home-relative|redacted] [--redact-user-text]
              recovery [list] [--json] [--limit N]
              recovery restore HOLDING_ID [--to PATH]
              archive [--json] [--preset developer|general|all] [--path PATH ...] [--scope-set NAME_OR_ID]   # review/compression-oriented plan only
              schedule install [--hour H] [--minute M] [--load]
              schedule uninstall [--unload]
              schedule status
              holding list [--json]
              holding restore ID [--to PATH]
              holding expire [--older-than-days N] [--yes]

            Defaults use --preset developer. Use --preset general for ordinary Mac cleanup review roots
            or --preset all for general plus developer/agent storage. Use saved scope sets for repeatable
            custom roots. User rule packs are local and opt-in
            per scan with --include-user-rules. Execution is dry-run unless --yes is supplied.
            """
        )
    }
}

struct ParsedOptions {
    let args: [String]

    init(_ args: [String]) {
        self.args = args
    }

    var json: Bool { args.contains("--json") }
    var dryRun: Bool { args.contains("--dry-run") || !args.contains("--yes") }
    var yes: Bool { args.contains("--yes") }
    var reviewAll: Bool { args.contains("--review-all") }
    var saveAudit: Bool { args.contains("--save-audit") }
    var saveHistory: Bool { args.contains("--save-history") }
    var saveReport: Bool { args.contains("--save-report") }
    var includeOpenFiles: Bool { args.contains("--include-open-files") }
    var includeMissingScopes: Bool { args.contains("--include-missing-scopes") }
    var noLsof: Bool { args.contains("--no-lsof") }
    var hasPath: Bool { !values(after: "--path").isEmpty }
    var hasCustomScopeSelection: Bool { hasPath || scopeSetReference != nil }
    var includePreserve: Bool { args.contains("--include-preserve") }
    var showExcluded: Bool { args.contains("--show-excluded") }
    var includeSystemApps: Bool { args.contains("--include-system-apps") }
    var includeOrphans: Bool { !args.contains("--no-orphans") }
    var ignoreUserPolicy: Bool { args.contains("--ignore-user-policy") }
    var includeUserRules: Bool { args.contains("--include-user-rules") }
    var replacePolicy: Bool { args.contains("--replace") }
    var hour: Int { Int(value(after: "--hour") ?? "") ?? 9 }
    var minute: Int { Int(value(after: "--minute") ?? "") ?? 30 }
    var limit: Int { max(1, Int(value(after: "--limit") ?? "") ?? 80) }
    var drilldownDepth: Int { max(0, Int(value(after: "--tree-depth") ?? value(after: "--max-depth") ?? "") ?? 3) }
    var presetName: String { value(after: "--preset") ?? ScanScopePreset.developer.rawValue }
    var sort: String { value(after: "--sort") ?? "size" }
    var group: String? { value(after: "--group") }
    var growthGroup: GrowthGroup { GrowthGroup(rawValue: group ?? "category") ?? .category }
    var review: String { value(after: "--review") ?? "all" }
    var largeThreshold: Int64 { Int64(value(after: "--large-threshold") ?? "") ?? 5_000_000_000 }
    var oldDays: Int { Int(value(after: "--old-days") ?? "") ?? 180 }
    var maxFilesToHash: Int { max(1, Int(value(after: "--max-files") ?? "") ?? 5_000) }
    var reason: String? { value(after: "--reason") }
    var summary: String? { value(after: "--summary") }
    var outputPath: String? { value(after: "--output") }
    var reportTitle: String { value(after: "--title") ?? "Ryddi Evidence Report" }
    var planReportTitle: String { value(after: "--title") ?? "Ryddi Plan Report" }
    var receiptReportTitle: String { value(after: "--title") ?? "Ryddi Receipt Report" }
    var growthReportTitle: String { value(after: "--title") ?? "Ryddi Growth Report" }
    var appUninstallPreviewTitle: String { value(after: "--title") ?? "Ryddi App Uninstall Preview" }
    var planID: String? { value(after: "--id") }
    var receiptID: String? { value(after: "--id") }
    var currentSnapshotID: String? { value(after: "--current-id") }
    var previousSnapshotID: String? { value(after: "--previous-id") }
    var scopeSetReference: String? { value(after: "--scope-set") }
    var reportPrivacy: ReportPrivacyOptions {
        ReportPrivacyOptions(pathStyle: reportPathStyle, redactUserText: args.contains("--redact-user-text"))
    }
    var reportPathStyle: ReportPathStyle {
        if args.contains("--redact-paths") {
            return .redacted
        }
        if args.contains("--home-relative") {
            return .homeRelative
        }
        if let raw = value(after: "--path-style"), let style = ReportPathStyle(rawValue: raw) {
            return style
        }
        return .full
    }
    var policyKind: UserPathPolicyKind? {
        switch value(after: "--kind") {
        case "protect": .protect
        case "exclude": .exclude
        case nil: nil
        default: nil
        }
    }
    var timeoutSeconds: TimeInterval {
        let value = Double(value(after: "--timeout") ?? "") ?? 5
        return max(1, min(value, 60))
    }

    func values(after flag: String) -> [String] {
        var values: [String] = []
        var index = 0
        while index < args.count {
            guard args[index] == flag else {
                index += 1
                continue
            }
            index += 1
            while index < args.count, !args[index].hasPrefix("--") {
                values.append(args[index])
                index += 1
            }
        }
        return values
    }

    func value(after flag: String) -> String? {
        guard let index = args.firstIndex(of: flag), args.indices.contains(index + 1) else { return nil }
        return args[index + 1]
    }

    func validateReportPrivacyOptions() throws {
        if let raw = value(after: "--path-style"), ReportPathStyle(rawValue: raw) == nil {
            let allowed = ReportPathStyle.allCases.map(\.rawValue).joined(separator: ", ")
            throw CLIError.message("--path-style must be one of: \(allowed)")
        }
    }

    func scopePreset() throws -> ScanScopePreset {
        guard let preset = ScanScopePreset(rawValue: presetName) else {
            let allowed = ScanScopePreset.allCases.map(\.rawValue).joined(separator: ", ")
            throw CLIError.message("--preset must be one of: \(allowed)")
        }
        return preset
    }

    func topOffenderSort() throws -> TopOffenderSort {
        guard let offenderSort = TopOffenderSort.parse(sort) else {
            let allowed = (["size"] + TopOffenderSort.allCases.map(\.rawValue)).joined(separator: ", ")
            throw CLIError.message("--sort must be one of: \(allowed)")
        }
        return offenderSort
    }

    func topOffenderGroup() throws -> TopOffenderGroup {
        guard let raw = group else { return .none }
        guard let offenderGroup = TopOffenderGroup(rawValue: raw) else {
            let allowed = TopOffenderGroup.allCases.map(\.rawValue).joined(separator: ", ")
            throw CLIError.message("--group must be one of: \(allowed)")
        }
        return offenderGroup
    }

    func scopePlan(includeUnavailable: Bool = false) throws -> ScanScopePlan {
        let paths = values(after: "--path")
        if !paths.isEmpty {
            let scopes = paths.map {
                let url = URL(fileURLWithPath: $0).standardizedFileURL
                return ScanScope(name: url.lastPathComponent, root: url)
            }
            return DefaultScopes.customPlan(scopes: scopes)
        }
        if let scopeSetReference {
            return try SavedScopeSetStore().plan(reference: scopeSetReference)
        }
        return DefaultScopes.plan(for: try scopePreset(), includeUnavailable: includeUnavailable)
    }

    func scopes(includeUnavailable: Bool = false) throws -> [ScanScope] {
        try scopePlan(includeUnavailable: includeUnavailable).scopes
    }

    func scanOptions(includeOpenFiles: Bool) -> ScanOptions {
        let minSize = Int64(value(after: "--min-size") ?? "") ?? 1_000_000
        let maxDepth = Int(value(after: "--max-depth") ?? "") ?? 2
        return ScanOptions(
            minimumFindingSize: minSize,
            maximumFindingDepth: maxDepth,
            measurementDepth: maxDepth + 4,
            includeOpenFileStatus: includeOpenFiles,
            largeFileThreshold: largeThreshold,
            oldFileAgeDays: oldDays,
            userPathPolicy: userPathPolicy
        )
    }

    func ruleEngine() throws -> RuleEngine {
        try RuleEngine.bundled(includingUserRules: includeUserRules)
    }

    var userPathPolicy: UserPathPolicy {
        ignoreUserPolicy ? .empty : UserPathPolicyStore().load()
    }

    var duplicateOptions: DuplicateReviewOptions {
        let minSize = Int64(value(after: "--min-size") ?? "") ?? 1_000_000
        let maxDepth = Int(value(after: "--max-depth") ?? "") ?? 6
        return DuplicateReviewOptions(
            minimumFileSize: minSize,
            maximumDepth: maxDepth,
            maximumFilesToHash: maxFilesToHash,
            includeHidden: !args.contains("--skip-hidden"),
            includePreserveByDefault: includePreserve
        )
    }

    var appReviewOptions: AppReviewOptions {
        let minSize = Int64(value(after: "--min-size") ?? "") ?? 1_000_000
        let home = value(after: "--home").map { URL(fileURLWithPath: $0).standardizedFileURL }
            ?? FileManager.default.homeDirectoryForCurrentUser
        let roots = values(after: "--path").map { URL(fileURLWithPath: $0).standardizedFileURL }
        return AppReviewOptions(
            appRoots: roots.isEmpty ? nil : roots,
            home: home,
            includeSystemApplications: includeSystemApps,
            includeOrphanCandidates: includeOrphans,
            minimumRelatedSize: minSize
        )
    }

    var appUninstallSelector: AppUninstallSelector {
        AppUninstallSelector(
            appPath: value(after: "--app"),
            bundleIdentifier: value(after: "--bundle-id"),
            displayName: value(after: "--name")
        )
    }

    func prepare(_ findings: [Finding]) -> [Finding] {
        let filtered = findings.filter { finding in
            switch review {
            case "large":
                finding.ruleMatches.contains { $0.ruleID == "dynamic.large-item.review" }
            case "old":
                finding.ruleMatches.contains { $0.ruleID == "dynamic.old-item.review" }
            default:
                true
            }
        }
        return filtered.sorted { lhs, rhs in
            switch sort {
            case "logical":
                return sort(lhs.logicalSize, rhs.logicalSize, lhs.path, rhs.path)
            case "age":
                return sort(Int64(lhs.ageInDays() ?? -1), Int64(rhs.ageInDays() ?? -1), lhs.path, rhs.path)
            case "risk":
                if lhs.safetyClass.riskRank == rhs.safetyClass.riskRank {
                    return lhs.allocatedSize > rhs.allocatedSize
                }
                return lhs.safetyClass.riskRank < rhs.safetyClass.riskRank
            case "category":
                if lhs.primaryCategory == rhs.primaryCategory {
                    return lhs.allocatedSize > rhs.allocatedSize
                }
                return lhs.primaryCategory < rhs.primaryCategory
            case "scope":
                if lhs.scopeName == rhs.scopeName {
                    return lhs.allocatedSize > rhs.allocatedSize
                }
                return lhs.scopeName < rhs.scopeName
            default:
                return sort(lhs.allocatedSize, rhs.allocatedSize, lhs.path, rhs.path)
            }
        }
    }

    private func sort(_ lhsValue: Int64, _ rhsValue: Int64, _ lhsPath: String, _ rhsPath: String) -> Bool {
        if lhsValue == rhsValue {
            return lhsPath < rhsPath
        }
        return lhsValue > rhsValue
    }
}

enum CLIError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let message): message
        }
    }
}

func printJSON<T: Encodable>(_ value: T) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    let data = try! encoder.encode(value)
    print(String(data: data, encoding: .utf8)!)
}

func printScopePlan(_ plan: ScanScopePlan) {
    print("Ryddi scan scopes")
    print("Mode: \(plan.label)")
    print(plan.summary)
    print("Scopes: \(plan.scopes.count)")
    print("\nRoots")
    for scope in plan.scopes {
        print("- \(scope.name): \(scope.root.path)")
    }
    print("\nNon-claims")
    for note in plan.nonClaims {
        print("- \(note)")
    }
}

func printSavedScopeSetDocument(_ document: SavedScopeSetDocument, path: String) {
    print("Ryddi saved scope sets")
    print("Path: \(path)")
    print("Sets: \(document.sets.count)")
    if document.sets.isEmpty {
        print("No saved scope sets yet. Use `reclaimer scopes saved add NAME --path PATH`.")
    } else {
        print("\nSets")
        for set in document.sets {
            print("- \(set.name) (\(set.scopes.count) root(s), id \(set.id))")
            if let summary = set.summary {
                print("  \(summary)")
            }
        }
    }
    print("\nNon-claims")
    for note in document.nonClaims {
        print("- \(note)")
    }
}

func printSavedScopeSet(_ set: SavedScopeSet) {
    print("Saved scope set: \(set.name)")
    print("ID: \(set.id)")
    if let summary = set.summary {
        print(summary)
    }
    print("Created: \(set.createdAt.formatted())")
    print("Updated: \(set.updatedAt.formatted())")
    print("Roots: \(set.scopes.count)")
    for scope in set.scopes {
        print("- \(scope.name): \(scope.root.path)")
    }
    print("\nNon-claims")
    for note in SavedScopeSetDocument.defaultNonClaims {
        print("- \(note)")
    }
}

func printSavedScopeSetImportResult(_ result: SavedScopeSetImportResult) {
    print("Imported saved scope sets")
    print("Mode: \(result.mode)")
    print("Source: \(result.sourcePath)")
    print("Destination: \(result.scopeSetPath)")
    print("Imported: \(result.importedSetCount)")
    print("Final: \(result.finalSetCount)")
    print("\nNon-claims")
    for note in result.nonClaims {
        print("- \(note)")
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
        "\(pad("Reclaim", 11)) \(pad("Allocated", 11)) \(pad("Age", 6)) \(pad("Confidence", 12)) \(pad("Safety", 22)) \(pad("Category", 18)) \(pad("Owner", 16)) \(pad("Action", 16)) Path"
    )
    for row in rows {
        let age = row.ageDays.map { "\($0)d" } ?? "-"
        print(
            "\(pad(ByteFormat.string(row.estimatedImmediateReclaim), 11)) \(pad(ByteFormat.string(row.allocatedSize), 11)) \(pad(age, 6)) \(pad(row.confidence.label, 12)) \(pad(row.safetyClass.label, 22)) \(pad(row.category, 18)) \(pad(row.ownerName, 16)) \(pad(row.actionKind.label, 16)) \(row.path)"
        )
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

func printRuleCatalog(_ catalog: RuleCatalogReport) {
    print("Ryddi rule catalog")
    print("Generated: \(catalog.generatedAt.formatted())")
    print("Rule version: \(catalog.ruleVersion)")
    print("Rules: \(catalog.ruleCount)")
    print("User rules: \(catalog.userRuleCount)")

    print("\nBy safety")
    for summary in catalog.safetySummaries {
        print("- \(pad(summary.name, 22)) \(summary.count) rule(s)")
    }

    print("\nBy category")
    for summary in catalog.categorySummaries.prefix(12) {
        print("- \(pad(summary.name, 22)) \(summary.count) rule(s)")
    }

    for section in catalog.sections where !section.rules.isEmpty {
        print("\n\(section.title)")
        print(section.guidance)
        for rule in section.rules {
            print("- \(rule.id): \(rule.title)")
            print("  Category: \(rule.category)")
            print("  Source: \(rule.source)")
            print("  Action: \(rule.actionKind.label)")
            if !rule.matchHints.isEmpty {
                print("  Match: \(rule.matchHints.joined(separator: ", "))")
            }
            if !rule.conditions.isEmpty {
                print("  Conditions: \(rule.conditions.joined(separator: " | "))")
            }
            if let recovery = rule.recovery, !recovery.isEmpty {
                print("  Recovery: \(recovery)")
            }
        }
    }

    print("\nNon-claims")
    for note in catalog.nonClaims {
        print("- \(note)")
    }
}

func printUserRulePackDocument(_ document: UserRulePackDocument, path: String) {
    print("Ryddi user rule pack")
    print("Path: \(path)")
    print("Schema: \(document.schemaVersion)")
    print("Rules: \(document.rules.count)")
    if document.rules.isEmpty {
        print("No local user rules are installed.")
    } else {
        for rule in document.rules {
            print("- \(rule.id): \(rule.title)")
            print("  Category: \(rule.category)")
            print("  Safety: \(rule.safetyClass.label)")
            print("  Action: \(rule.actionKind.label)")
            print("  Match: \(rule.match.catalogSummary)")
        }
    }
    print("\nNon-claims")
    for note in document.nonClaims {
        print("- \(note)")
    }
}

func printUserRulePackPreview(_ preview: UserRulePackPreview) {
    print("Ryddi user rule pack preview")
    print("Source: \(preview.sourcePath)")
    print("Destination: \(preview.rulePackPath)")
    print("Importable: \(preview.isImportable ? "yes" : "no")")
    print("Rules: \(preview.ruleCount), accepted: \(preview.acceptedRuleCount), rejected: \(preview.rejectedRuleCount)")
    printUserRulePackIssues(preview.issues)
    print("\nNon-claims")
    for note in preview.nonClaims {
        print("- \(note)")
    }
}

func printUserRulePackImportResult(_ result: UserRulePackImportResult) {
    print("Ryddi user rule pack import")
    print("Source: \(result.sourcePath)")
    print("Stored: \(result.rulePackPath)")
    print("Mode: \(result.mode)")
    print("Imported rules: \(result.importedRuleCount)")
    print("Final rules: \(result.finalRuleCount)")
    print("Included by default: \(result.includedByDefault ? "yes" : "no")")
    printUserRulePackIssues(result.issues)
    print("\nNon-claims")
    for note in result.nonClaims {
        print("- \(note)")
    }
}

func printUserRulePackIssues(_ issues: [UserRulePackValidationIssue]) {
    if issues.isEmpty {
        print("Validation: no issues")
        return
    }
    print("\nValidation")
    for issue in issues {
        let scope = issue.ruleID.map { " \($0)" } ?? ""
        print("- \(issue.severity.rawValue)\(scope): \(issue.message)")
    }
}

private extension RuleMatchSpec {
    var catalogSummary: String {
        var hints: [String] = []
        hints += containsAny.map { "contains: \($0)" }
        hints += suffixAny.map { "suffix: \($0)" }
        hints += basenameAny.map { "basename: \($0)" }
        hints += pathExtensionAny.map { "extension: \($0)" }
        return hints.isEmpty ? "none" : hints.sorted().joined(separator: ", ")
    }
}

func printDiskStatus(_ snapshot: DiskStatusSnapshot) {
    print("Ryddi disk status")
    print("Generated: \(snapshot.createdAt.formatted())")
    print("Path: \(snapshot.path)")
    if let volumeName = snapshot.volumeName {
        print("Volume: \(volumeName)")
    }
    print("Pressure: \(snapshot.pressure.label)")
    print("Free: \(snapshot.statusLine)")
    if let totalBytes = snapshot.totalBytes {
        print("Total: \(ByteFormat.string(totalBytes))")
    }
    if let freeBytes = snapshot.freeBytes {
        print("Filesystem free: \(ByteFormat.string(freeBytes))")
    }
    print("Notes")
    for note in snapshot.notes {
        print("- \(note)")
    }
}

func printPermissionAdvisorReport(_ report: PermissionAdvisorReport) {
    print("Ryddi permission advisor")
    print("Generated: \(report.createdAt.formatted())")
    print("Coverage: \(report.coverageLevel.label)")
    print("Readable scopes: \(report.readableCount)/\(report.totalCount)")
    print("Denied: \(report.deniedCount)")
    print("Missing: \(report.missingCount)")
    print("Unknown: \(report.unknownCount)")
    print("Full Disk Access settings: \(report.fullDiskAccessSettingsURL)")

    print("\nRecommended actions")
    for action in report.recommendedActions {
        print("- \(action)")
    }

    if !report.unavailableScopes.isEmpty {
        print("\nUnavailable scopes")
        for scope in report.unavailableScopes {
            print("- \(scope.permissionState.rawValue): \(scope.name) - \(scope.path)")
            print("  \(scope.message)")
        }
    }

    print("\nNon-claims")
    for note in report.nonClaims {
        print("- \(note)")
    }
}

func printActiveFileReviewReport(_ report: ActiveFileReviewReport) {
    print("Ryddi active-file review")
    print("Generated: \(report.createdAt.formatted())")
    print("Candidates: \(report.candidateCount)")
    print("Checked: \(report.checkedCount)\(report.truncated ? " (limited)" : "")")
    print("Open: \(report.openCount)")
    print("Check failed: \(report.failedCheckCount)")
    print("Blocked bytes: \(ByteFormat.string(report.totalBlockedBytes))")

    if report.items.isEmpty {
        print("\nNo open-handle blockers found in the checked cleanup candidates.")
    } else {
        print("\nOpen-handle blockers")
        print("\(pad("State", 13)) \(pad("Bytes", 11)) \(pad("Safety", 22)) \(pad("Processes", 36)) Path")
        for item in report.items {
            let processes: String
            if !item.processSummary.isEmpty {
                processes = item.processSummary.joined(separator: ", ")
            } else if let failure = item.checkFailed {
                processes = failure
            } else {
                processes = "-"
            }
            print("\(pad(item.state.label, 13)) \(pad(ByteFormat.string(item.finding.allocatedSize), 11)) \(pad(item.finding.safetyClass.label, 22)) \(pad(processes, 36)) \(item.finding.path)")
            for line in item.guidance.prefix(2) {
                print("  - \(line)")
            }
        }
    }

    print("\nNon-claims")
    for note in report.nonClaims {
        print("- \(note)")
    }
}

func printSnapshots(_ snapshots: [ScanSnapshot]) {
    if snapshots.isEmpty {
        print("No saved scan snapshots.")
        return
    }
    print("\(pad("Created", 22)) \(pad("Allocated", 12)) \(pad("Logical", 12)) \(pad("Findings", 10)) ID")
    for snapshot in snapshots {
        print("\(pad(snapshot.createdAt.formatted(), 22)) \(pad(ByteFormat.string(snapshot.totalAllocatedSize), 12)) \(pad(ByteFormat.string(snapshot.totalLogicalSize), 12)) \(pad("\(snapshot.findingCount)", 10)) \(snapshot.id)")
    }
}

func printSnapshot(_ snapshot: ScanSnapshot) {
    print("Created: \(snapshot.createdAt.formatted())")
    print("Allocated scanned: \(ByteFormat.string(snapshot.totalAllocatedSize))")
    print("Logical scanned: \(ByteFormat.string(snapshot.totalLogicalSize))")
    print("Findings: \(snapshot.findingCount)")
    print("Top categories:")
    for category in snapshot.categorySummaries.prefix(8) {
        print("- \(pad(category.name, 22)) \(pad(ByteFormat.string(category.allocatedSize), 10)) \(category.count) item(s)")
    }
}

func printGrowthDeltas(
    _ deltas: [BucketGrowthDelta],
    group: GrowthGroup,
    current: ScanSnapshot,
    previous: ScanSnapshot,
    limit: Int
) {
    print("Growth since previous scan")
    print("Group: \(group.label)")
    print("Previous: \(previous.createdAt.formatted())")
    print("Current: \(current.createdAt.formatted())")
    print("\(pad("Delta", 12)) \(pad("Current", 12)) \(pad("Previous", 12)) \(pad("Items", 10)) Name")
    for delta in deltas.prefix(limit) {
        let sign = delta.deltaAllocatedSize > 0 ? "+" : ""
        let deltaText = sign + ByteFormat.string(delta.deltaAllocatedSize)
        print("\(pad(deltaText, 12)) \(pad(ByteFormat.string(delta.currentAllocatedSize), 12)) \(pad(ByteFormat.string(delta.previousAllocatedSize), 12)) \(pad("\(delta.currentCount)", 10)) \(delta.name)")
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
            print("  - \(ByteFormat.string(item.allocatedSize)) \(item.safetyClass.label) \(item.category) \(modified) \(item.path)")
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

func printPlan(_ plan: ReclaimPlan) {
    print("Plan \(plan.id)")
    print("Expected immediate reclaim: \(ByteFormat.string(plan.expectedImmediateReclaim))")
    for line in plan.dryRunSummary {
        print(line)
    }
}

func printPlans(_ plans: [ReclaimPlan]) {
    if plans.isEmpty {
        print("No saved plans.")
        return
    }
    print("\(pad("Created", 22)) \(pad("Mode", 12)) \(pad("Items", 8)) \(pad("Selected", 9)) \(pad("Reclaim", 12)) Plan")
    for plan in plans {
        let selected = plan.items.filter(\.selected).count
        print(
            "\(pad(plan.createdAt.formatted(date: .numeric, time: .shortened), 22)) \(pad(plan.mode, 12)) \(pad("\(plan.items.count)", 8)) \(pad("\(selected)", 9)) \(pad(ByteFormat.string(plan.expectedImmediateReclaim), 12)) \(plan.id)"
        )
    }
}

func printFindingDetail(_ finding: Finding) {
    print("\(finding.displayName)")
    print("Path: \(finding.path)")
    print("Size: \(ByteFormat.string(finding.allocatedSize)) allocated, \(ByteFormat.string(finding.logicalSize)) logical")
    print("Safety: \(finding.safetyClass.label)")
    print("Action: \(finding.actionKind.label)")
    if let open = finding.openFileStatus {
        print("Open handles: \(open.isOpen ? open.processSummary.joined(separator: ", ") : "none")")
    }
    print("Evidence:")
    for evidence in finding.evidence {
        print("- \(evidence.message)")
    }
    let guidance = CleanupGuidance.commands(for: finding)
    if !guidance.isEmpty {
        print("Native guidance:")
        for line in guidance {
            print("- \(line)")
        }
    }
}

func printNativeToolReport(_ report: NativeToolReport, options: ParsedOptions) {
    print("Native tool report \(report.id)")
    print("Rule version: \(report.ruleVersion)")
    print("Previewed native-tool bytes: \(ByteFormat.string(report.totalBytesUnderNativeReview))")
    if report.receipts.isEmpty {
        print("No native-tool cleanup candidates found.")
    }
    for receipt in report.receipts.prefix(options.limit) {
        print("\n\(receipt.displayName)")
        print("Path: \(receipt.findingPath)")
        print("Category: \(receipt.category)")
        print("Status: \(receipt.status)")
        print("Size under review: \(ByteFormat.string(receipt.allocatedSize))")
        print(receipt.message)
        for command in receipt.commands {
            let review = command.requiresReview ? "review first" : "inspect"
            print("- [\(command.risk.label), \(review)] \(command.command)")
            print("  \(command.purpose)")
            print("  Expected effect: \(command.expectedEffect)")
        }
    }
    if report.receipts.count > options.limit {
        print("\n... \(report.receipts.count - options.limit) more native-tool candidate(s)")
    }
    if !report.nonClaims.isEmpty {
        print("\nNon-claims")
        for note in report.nonClaims {
            print("- \(note)")
        }
    }
}

func printContainerInventoryReport(_ report: ContainerInventoryReport, options: ParsedOptions) {
    print("Container inventory \(report.id)")
    print("Generated: \(report.createdAt.formatted())")
    print("Docker: \(report.docker.status.state.label) - \(report.docker.status.message)")
    if let reclaimable = report.dockerReclaimableBytes {
        print("Docker native reclaimable estimate: \(ByteFormat.string(reclaimable))")
    }

    if !report.docker.storage.isEmpty {
        print("\nDocker storage")
        print("\(pad("Type", 16)) \(pad("Total", 8)) \(pad("Active", 8)) \(pad("Size", 12)) Reclaimable")
        for bucket in report.docker.storage {
            print("\(pad(bucket.type, 16)) \(pad(bucket.total.map(String.init) ?? "-", 8)) \(pad(bucket.active.map(String.init) ?? "-", 8)) \(pad(bucket.sizeText, 12)) \(bucket.reclaimableText)")
        }
    }

    if !report.docker.contexts.isEmpty {
        print("\nDocker contexts")
        for context in report.docker.contexts.prefix(options.limit) {
            let current = context.isCurrent ? "current" : "available"
            print("- \(context.name) (\(current)) \(context.endpoint ?? "")")
        }
    }

    if !report.docker.containers.isEmpty {
        print("\nDocker containers")
        for container in report.docker.containers.prefix(options.limit) {
            print("- \(container.name) \(container.status) \(container.sizeText)")
        }
    }

    if !report.docker.images.isEmpty {
        print("\nDocker images")
        for image in report.docker.images.prefix(options.limit) {
            print("- \(image.repository):\(image.tag) \(image.sizeText)")
        }
    }

    if !report.docker.volumes.isEmpty {
        print("\nDocker volumes")
        for volume in report.docker.volumes.prefix(options.limit) {
            print("- \(volume.name) \(volume.driver) \(volume.scope)")
        }
    }

    print("\nColima: \(report.colima.status.state.label) - \(report.colima.status.message)")
    if !report.colima.profiles.isEmpty {
        print("\nColima profiles")
        for profile in report.colima.profiles.prefix(options.limit) {
            let details = [
                profile.status,
                profile.runtime,
                profile.architecture,
                profile.cpu.map { "\($0) CPU" },
                profile.memory,
                profile.disk
            ]
            .compactMap { $0 }
            .joined(separator: ", ")
            print("- \(profile.name): \(details)")
        }
    }

    print("\nRead-only commands")
    for command in (report.docker.commands + report.colima.commands).prefix(options.limit) {
        let code = command.exitCode.map { "\($0)" } ?? "-"
        print("- [\(command.status), exit \(code)] \(command.command)")
        if let error = command.launchError {
            print("  \(error)")
        } else if let stderr = command.stderrPreview.first {
            print("  \(stderr)")
        }
    }

    print("\nNotes")
    for note in report.notes {
        print("- \(note)")
    }

    print("\nNon-claims")
    for note in report.nonClaims {
        print("- \(note)")
    }
}

func printUserPathPolicy(_ policy: UserPathPolicy) {
    print("Ryddi user path policy")
    if policy.rules.isEmpty {
        print("No user exclusions or protections configured.")
        return
    }
    for kind in UserPathPolicyKind.allCases {
        let rules = policy.rules(kind: kind)
        guard !rules.isEmpty else { continue }
        print("\n\(kind.label)")
        for rule in rules {
            let reason = rule.reason.map { " - \($0)" } ?? ""
            print("- \(rule.path)\(reason)")
        }
    }
}

func printPolicyExportSummary(_ document: UserPathPolicyDocument) {
    print("Ryddi user path policy export")
    print("Rules: \(document.rules.count)")
    print("Schema: \(document.schemaVersion)")
    print("\nNon-claims")
    for note in document.nonClaims {
        print("- \(note)")
    }
}

func printPolicyImportResult(_ result: UserPathPolicyImportResult) {
    print("Imported user path policy")
    print("Mode: \(result.mode)")
    print("Source: \(result.sourcePath)")
    print("Policy file: \(result.policyPath)")
    print("Imported rules: \(result.importedRuleCount)")
    print("Final rules: \(result.finalRuleCount)")
    print("")
    printUserPathPolicy(result.policy)
    print("\nNon-claims")
    for note in result.nonClaims {
        print("- \(note)")
    }
}

func printReceipt(_ receipt: ExecutionReceipt) {
    print("Receipt \(receipt.id)")
    for action in receipt.actions {
        print("[\(action.status)] \(action.action.label): \(action.path) - \(action.message)")
    }
}

func printReceipts(_ receipts: [ExecutionReceipt]) {
    if receipts.isEmpty {
        print("No saved receipts.")
        return
    }
    print("\(pad("Created", 22)) \(pad("Mode", 8)) \(pad("Actions", 8)) \(pad("Dry-run", 8)) \(pad("Done", 6)) \(pad("Skipped", 8)) \(pad("Errors", 7)) Receipt")
    for receipt in receipts {
        let dryRun = receipt.actions.filter { $0.status == "dry-run" }.count
        let done = receipt.actions.filter { $0.status == "done" }.count
        let skipped = receipt.actions.filter { $0.status == "skipped" }.count
        let errors = receipt.actions.filter { $0.status == "error" }.count + receipt.errors.count
        print(
            "\(pad(receipt.createdAt.formatted(date: .numeric, time: .shortened), 22)) \(pad(receipt.mode, 8)) \(pad("\(receipt.actions.count)", 8)) \(pad("\(dryRun)", 8)) \(pad("\(done)", 6)) \(pad("\(skipped)", 8)) \(pad("\(errors)", 7)) \(receipt.id)"
        )
    }
}

func printRecoveryCenter(_ report: RecoveryCenterReport) {
    print("Ryddi recovery center")
    print("Generated: \(report.generatedAt.formatted())")
    print("Items: \(report.itemCount)")
    print("Restorable with Ryddi: \(report.restorableCount) item(s), \(ByteFormat.string(report.restorableBytes))")

    if !report.stateSummaries.isEmpty {
        print("\nBy recovery state")
        for summary in report.stateSummaries {
            print("- \(pad(summary.state.label, 26)) \(pad(ByteFormat.string(summary.bytes), 10)) \(summary.count) item(s)")
        }
    }

    if report.items.isEmpty {
        print("\nNo holding items or saved receipt actions were found.")
    } else {
        print("\nItems")
        print("\(pad("State", 26)) \(pad("Bytes", 11)) \(pad("Action", 16)) Path")
        for item in report.items {
            let action = item.actionKind?.label ?? "-"
            let path = item.originalPath ?? item.currentPath ?? "-"
            print("\(pad(item.state.label, 26)) \(pad(ByteFormat.string(item.bytes), 11)) \(pad(action, 16)) \(path)")
            if let holdingID = item.holdingID {
                print("  Restore: reclaimer recovery restore \(holdingID)")
            }
            for guidance in item.guidance.prefix(2) {
                print("  - \(guidance)")
            }
        }
    }

    print("\nNon-claims")
    for note in report.nonClaims {
        print("- \(note)")
    }
}

func printHeldItems(_ items: [HeldItem]) {
    if items.isEmpty {
        print("No held items.")
        return
    }
    for item in items {
        let heldAt = item.heldAt?.formatted() ?? "unknown date"
        let original = item.originalPath ?? "unknown original path"
        print("\(ByteFormat.string(item.allocatedSize).padding(toLength: 10, withPad: " ", startingAt: 0)) \(item.id)")
        print("  Held: \(item.heldPath)")
        print("  Original: \(original)")
        print("  Date: \(heldAt)")
    }
}

func pad(_ value: String, _ length: Int) -> String {
    if value.count >= length {
        return String(value.prefix(max(0, length - 1))) + " "
    }
    return value.padding(toLength: length, withPad: " ", startingAt: 0)
}
