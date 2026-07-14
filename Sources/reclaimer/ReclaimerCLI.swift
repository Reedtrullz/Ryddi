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
        case "release-trust":
            try releaseTrust(args: args)
        case "trust":
            try trust(args: args)
        case "dogfood":
            try dogfood(args: args)
        case "overview":
            try overview(args: args)
        case "queues":
            try queues(args: args)
        case "large":
            try large(args: args)
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
        case "audit":
            try audit(args: args)
        case "duplicates":
            try duplicates(args: args)
        case "downloads":
            try downloads(args: args)
        case "browsers":
            try browsers(args: args)
        case "packages":
            try packages(args: args)
        case "projects":
            try projects(args: args)
        case "device-backups":
            try deviceBackups(args: args)
        case "xcode":
            try xcode(args: args)
        case "trash":
            try trash(args: args)
        case "apps":
            try apps(args: args)
        case "agents":
            try agents(args: args)
        case "native":
            try native(args: args)
        case "containers":
            try containers(args: args)
        case "remote":
            try remote(args: args)
        case "issue":
            try issue(args: args)
        case "policy":
            try policy(args: args)
        case "scan":
            try scan(args: args)
        case "session":
            try session(args: args)
        case "actions":
            try actions(args: args)
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
        let ruleEngine = try options.ruleEngine()
        let scopePlan = try options.scopePlan(includeUnavailable: options.includeMissingScopes)
        let preset: ScanScopePreset
        if let scopePlanPreset = scopePlan.preset {
            preset = scopePlanPreset
        } else {
            preset = try options.scopePreset()
        }
        let scopes = scopePlan.scopes
        let scanner = try FileScanner(ruleEngine: ruleEngine, openFileChecker: options.noLsof ? NoOpenFilesChecker() : LsofOpenFileChecker())
        let scanOptions = options.scanOptions(includeOpenFiles: options.includeOpenFiles)
        let findings = scanner.scan(
            scopes: scopes,
            options: scanOptions
        )
        let preparedFindings = options.prepare(findings)
        let session = ScanSessionEvidenceBuilder.scannedSession(
            appVersion: "reclaimer-cli",
            ruleVersion: ruleEngine.version,
            preset: preset,
            scopes: scopes,
            userPathPolicy: scanOptions.userPathPolicy,
            findings: preparedFindings
        )
        try AuditStore().saveScanSession(session)
        if options.json {
            try printJSON(preparedFindings)
        } else {
            printFindings(preparedFindings, options: options)
        }
    }

    static func session(args: [String]) throws {
        guard let subcommand = args.first else {
            throw CLIError.message("session requires latest or explain")
        }
        let options = ParsedOptions(Array(args.dropFirst()))
        let store = AuditStore()
        switch subcommand {
        case "latest":
            let session = try store.latestScanSession()
            if options.json {
                try printJSON(session)
            } else {
                printLatestScanSession(session)
            }
        case "explain":
            let session = try store.latestScanSession()
            if options.json {
                try printJSON(session)
            } else {
                printScanSessionExplanation(session)
            }
        default:
            throw CLIError.message("Unknown session subcommand: \(subcommand)")
        }
    }

    static func actions(args: [String]) throws {
        let options = ParsedOptions(args)
        let store = AuditStore()
        let scanSessions = try store.listScanSessionsResult(limit: 1)
        let report = ActionCenterBuilder.build(input: ActionCenterInput(
            permissionReport: PermissionAdvisor.report(scopes: try options.scopes(includeUnavailable: true)),
            latestScanSession: scanSessions.sessions.first,
            findings: [],
            currentPlan: store.recentPlans(limit: 1).first,
            latestExecutionReceipt: store.recentReceipts(limit: 1).first,
            activeFileReviewReport: store.recentActiveFileReviewReports(limit: 1).first,
            browserCacheReport: store.recentBrowserCacheReviewReports(limit: 1).first,
            packageCacheReport: store.recentPackageCacheReviewReports(limit: 1).first,
            latestNativeToolExecutionReceipt: store.recentNativeToolExecutionReceipts(limit: 1).first,
            sessionHistoryWarnings: scanSessions.warnings
        ))
        if options.json {
            try printJSON(report)
        } else {
            printActionCenter(report)
        }
    }

    static func status(args: [String]) throws {
        let options = ParsedOptions(args)
        let path = options.values(after: "--path").first ?? "/System/Volumes/Data"
        let snapshot = DiskStatusReader().snapshot(for: URL(fileURLWithPath: path))
        if options.json {
            try printJSON(snapshot)
        } else {
            printDiskStatus(snapshot)
        }
    }

    static func releaseTrust(args: [String]) throws {
        let options = ParsedOptions(args)
        let evidence = ReleaseTrustEvidenceLoader.load(path: options.releaseManifestPath)
        if options.json {
            try printJSON(evidence)
        } else {
            printReleaseTrustEvidence(evidence)
        }
    }

    static func trust(args: [String]) throws {
        let options = ParsedOptions(args)
        let scopes = try options.scopes(includeUnavailable: true)
        let scanner = try FileScanner(ruleEngine: try options.ruleEngine(), openFileChecker: NoOpenFilesChecker())
        let result = scanner.scanWithCoverage(scopes: scopes, options: options.scanOptions(includeOpenFiles: false))
        let findings = result.findings
        let overview = FindingAnalytics.overview(
            findings: findings,
            scopes: scopes,
            topLimit: options.limit,
            scopeAccessSummaries: result.coverage.scopeAccessSummaries
        )
        let store = AuditStore()
        let report = TrustReadinessBuilder.build(
            diskStatus: DiskStatusReader().snapshot(),
            permissionSummary: PermissionAdvisor.report(scopeSummaries: overview.scopeSummaries),
            findings: findings,
            latestPlan: store.recentPlans(limit: 1).first,
            latestReceipt: store.recentReceipts(limit: 1).first,
            automationInstalled: FileManager.default.fileExists(atPath: LaunchAgentManager().installedPath().path),
            signingState: ProcessInfo.processInfo.environment["RYDDI_SIGNING_STATE"] ?? "CLI/source runtime; verify distributed app with release manifest",
            releaseTrustEvidence: ReleaseTrustEvidenceLoader.load(path: options.releaseManifestPath),
            scanCoverage: result.coverage
        )
        if options.json {
            try printJSON(report)
        } else {
            printTrustReadiness(report)
        }
    }

    static func scopes(args: [String]) throws {
        if args.first == "templates" {
            try scopeTemplates(args: Array(args.dropFirst()))
            return
        }
        if args.first == "saved" {
            try savedScopes(args: Array(args.dropFirst()))
            return
        }
        let options = ParsedOptions(args)
        let plan = try options.scopePlan(includeUnavailable: true)
        if options.json {
            try printJSON(plan)
        } else {
            printScopePlan(plan)
        }
    }

    static func scopeTemplates(args: [String]) throws {
        let subcommand = args.first ?? "list"
        let options = ParsedOptions(Array(args.dropFirst()))
        switch subcommand {
        case "list":
            let templates = ScopeTemplateCatalog.all(includeUnavailable: options.includeMissingScopes)
            if options.json {
                try printJSON(templates)
            } else {
                printScopeTemplates(templates)
            }
        case "show":
            guard args.indices.contains(1), !args[1].hasPrefix("-") else {
                throw CLIError.message("scopes templates show requires a template id or name")
            }
            let template = try ScopeTemplateCatalog.find(args[1], includeUnavailable: true)
            if options.json {
                try printJSON(template)
            } else {
                printScopeTemplate(template)
            }
        case "save":
            guard args.indices.contains(1), !args[1].hasPrefix("-") else {
                throw CLIError.message("scopes templates save requires a template id or name")
            }
            let template = try ScopeTemplateCatalog.find(args[1], includeUnavailable: true)
            let name = options.value(after: "--name") ?? template.name
            let summary = options.summary ?? template.summary
            let set = try SavedScopeSetStore().upsert(
                name: name,
                paths: template.scopes.map(\.root.path),
                summary: summary
            )
            if options.json {
                try printJSON(set)
            } else {
                print("saved scope set from template: \(template.name)")
                printSavedScopeSet(set)
            }
        default:
            throw CLIError.message("Unknown scopes templates subcommand: \(subcommand)")
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
                try printJSON(document)
            } else {
                printSavedScopeSetDocument(document, path: store.scopeSetURL.path)
            }
        case "show":
            guard args.indices.contains(1), !args[1].hasPrefix("-") else {
                throw CLIError.message("scopes saved show requires a saved scope set name or id")
            }
            let set = try store.find(args[1])
            if options.json {
                try printJSON(set)
            } else {
                printSavedScopeSet(set)
            }
        case "add":
            guard args.indices.contains(1), !args[1].hasPrefix("-") else {
                throw CLIError.message("scopes saved add requires a name and at least one --path")
            }
            let set = try store.upsert(name: args[1], paths: options.values(after: "--path"), summary: options.summary)
            if options.json {
                try printJSON(set)
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
                try printJSON(document)
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
                try printJSON(document)
            } else {
                printSavedScopeSetDocument(document, path: store.scopeSetURL.path)
            }
        case "import":
            guard args.indices.contains(1), !args[1].hasPrefix("-") else {
                throw CLIError.message("scopes saved import requires a saved scope sets JSON path")
            }
            let result = try store.importDocument(from: URL(fileURLWithPath: args[1]).standardizedFileURL, merge: !options.replacePolicy)
            if options.json {
                try printJSON(result)
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
            try printJSON(catalog)
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
                try printJSON(document)
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
                try printJSON(preview)
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
                try printJSON(result)
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
                try printJSON(document)
            } else {
                printUserRulePackDocument(document, path: store.rulePackURL.path)
            }
        default:
            throw CLIError.message("Unknown rules user subcommand: \(subcommand)")
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
            try printJSON(report)
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
            try SafeFileOutput.write(walkthrough.markdown, to: url)
            FileHandle.standardError.write(Data("wrote permission walkthrough: \(url.path)\n".utf8))
        }
        if options.json {
            try printJSON(walkthrough)
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
            try printJSON(report)
        } else {
            printActiveFileReviewReport(report)
        }
    }


    static func native(args: [String]) throws {
        if args.first == "homebrew" {
            try nativeHomebrew(args: Array(args.dropFirst()))
            return
        }
        if args.first == "run" {
            try nativeRun(args: Array(args.dropFirst()))
            return
        }
        if args.first == "receipts" {
            try nativeReceipts(args: Array(args.dropFirst()))
            return
        }
        let options = ParsedOptions(args)
        let scanner = try FileScanner(ruleEngine: try options.ruleEngine(), openFileChecker: options.noLsof ? NoOpenFilesChecker() : LsofOpenFileChecker())
        let findings = scanner.scan(scopes: try options.scopes(), options: options.scanOptions(includeOpenFiles: false))
        let report = NativeToolGuidance.report(for: findings, ruleVersion: try options.ruleEngine().version)
        if options.saveAudit {
            let url = try AuditStore().save(nativeToolReport: report)
            FileHandle.standardError.write(Data("saved native-tool report: \(url.path)\n".utf8))
        }
        if options.json {
            try printJSON(report)
        } else {
            printNativeToolReport(report, options: options)
        }
    }

    static func nativeHomebrew(args: [String]) throws {
        guard args.first == "cleanup" else {
            throw CLIError.message("native homebrew requires cleanup")
        }
        let options = ParsedOptions(Array(args.dropFirst()))
        let mode: SafeActionExecutionMode = options.dryRun ? .dryRun : .perform
        let ruleVersion = try options.ruleEngine().version
        let findingPath = options.nativeFindingPath ?? NativeActionReceiptBridge.defaultHomebrewFindingPath
        let executor = NativeActionExecutor(
            configuration: NativeActionExecutionConfiguration(timeout: options.timeoutSeconds)
        )
        let previewEvidence: NativeActionReceipt?
        let receipt: NativeActionReceipt
        if mode == .perform {
            let preview = executor.previewHomebrewCleanup(
                ruleVersion: ruleVersion,
                findingPath: findingPath
            )
            previewEvidence = preview.receipt
            receipt = executor.performHomebrewCleanup(
                using: preview,
                userConfirmed: options.yes,
                ruleVersion: ruleVersion,
                findingPath: findingPath
            )
        } else {
            previewEvidence = nil
            receipt = executor.executeHomebrewCleanup(mode: .dryRun, userConfirmed: false)
        }
        if options.saveAudit {
            if let previewEvidence {
                let previewReceipt = NativeActionReceiptBridge.nativeToolExecutionReceipt(
                    from: previewEvidence,
                    ruleVersion: ruleVersion,
                    findingPath: findingPath,
                    userConfirmed: false
                )
                let previewURL = try AuditStore().save(nativeToolExecutionReceipt: previewReceipt)
                FileHandle.standardError.write(Data("saved same-process Homebrew preview receipt: \(previewURL.path)\n".utf8))
            }
            let executionReceipt = NativeActionReceiptBridge.nativeToolExecutionReceipt(
                from: receipt,
                ruleVersion: ruleVersion,
                findingPath: findingPath,
                userConfirmed: options.yes
            )
            let url = try AuditStore().save(nativeToolExecutionReceipt: executionReceipt)
            FileHandle.standardError.write(Data("saved native-tool execution receipt: \(url.path)\n".utf8))
        }
        if options.json {
            try printJSON(receipt)
        } else {
            printNativeActionReceipt(receipt)
        }
        try requireSuccessfulHomebrewReceipt(receipt)
    }

    static func nativeRun(args: [String]) throws {
        let options = ParsedOptions(args)
        guard let commandID = options.commandID else {
            throw CLIError.message("native run requires --command-id COMMAND_ID")
        }
        let ruleEngine = try options.ruleEngine()
        let scanner = try FileScanner(ruleEngine: ruleEngine, openFileChecker: options.noLsof ? NoOpenFilesChecker() : LsofOpenFileChecker())
        let findings = scanner.scan(scopes: try options.scopes(), options: options.scanOptions(includeOpenFiles: false))
        let report = NativeToolGuidance.report(for: findings, ruleVersion: ruleEngine.version)
        guard let selection = NativeToolExecutor.selection(
            in: report,
            commandID: commandID,
            findingPath: options.nativeFindingPath
        ) else {
            throw CLIError.message("No native-tool command matched --command-id \(commandID). Run reclaimer native to inspect available command ids.")
        }
        if let maintenanceAction = NativeMaintenanceAction(rawValue: commandID) {
            let executor = NativeMaintenanceExecutor(
                configuration: NativeActionExecutionConfiguration(timeout: options.timeoutSeconds)
            )
            let preview = executor.preview(
                action: maintenanceAction,
                findingPath: selection.receipt.findingPath,
                ruleVersion: ruleEngine.version
            )
            let maintenanceReceipt = options.dryRun
                ? preview.receipt
                : executor.perform(
                    using: preview,
                    userConfirmed: options.yes,
                    findingPath: selection.receipt.findingPath,
                    ruleVersion: ruleEngine.version
                )
            if options.saveAudit {
                let canonical = NativeMaintenanceReceiptBridge.nativeToolExecutionReceipt(
                    from: maintenanceReceipt,
                    action: maintenanceAction,
                    ruleVersion: ruleEngine.version,
                    findingPath: selection.receipt.findingPath,
                    category: selection.receipt.category,
                    userConfirmed: options.yes
                )
                let url = try AuditStore().save(nativeToolExecutionReceipt: canonical)
                FileHandle.standardError.write(Data("saved native maintenance receipt: \(url.path)\n".utf8))
            }
            if options.json {
                try printJSON(maintenanceReceipt)
            } else {
                printNativeActionReceipt(maintenanceReceipt)
            }
            try requireSuccessfulNativeMaintenanceReceipt(maintenanceReceipt)
            return
        }
        let previewEvidence: NativeToolExecutionReceipt?
        let receipt: NativeToolExecutionReceipt
        if !options.dryRun, commandID == "brew.cleanup" {
            let executor = NativeActionExecutor(
                configuration: NativeActionExecutionConfiguration(timeout: options.timeoutSeconds)
            )
            let preview = executor.previewHomebrewCleanup(
                ruleVersion: ruleEngine.version,
                findingPath: selection.receipt.findingPath
            )
            previewEvidence = NativeActionReceiptBridge.nativeToolExecutionReceipt(
                from: preview.receipt,
                ruleVersion: ruleEngine.version,
                findingPath: selection.receipt.findingPath,
                category: selection.receipt.category,
                userConfirmed: false
            )
            let actionReceipt = executor.performHomebrewCleanup(
                using: preview,
                userConfirmed: options.yes,
                ruleVersion: ruleEngine.version,
                findingPath: selection.receipt.findingPath
            )
            receipt = NativeActionReceiptBridge.nativeToolExecutionReceipt(
                from: actionReceipt,
                ruleVersion: ruleEngine.version,
                findingPath: selection.receipt.findingPath,
                category: selection.receipt.category,
                userConfirmed: options.yes
            )
        } else {
            previewEvidence = nil
            receipt = NativeToolExecutor(
                configuration: NativeToolExecutionConfiguration(timeout: options.timeoutSeconds)
            ).execute(
                selection: selection,
                mode: options.dryRun ? .dryRun : .perform,
                ruleVersion: ruleEngine.version,
                userConfirmed: options.yes
            )
        }
        if options.saveAudit {
            if let previewEvidence {
                let previewURL = try AuditStore().save(nativeToolExecutionReceipt: previewEvidence)
                FileHandle.standardError.write(Data("saved same-process Homebrew preview receipt: \(previewURL.path)\n".utf8))
            }
            let url = try AuditStore().save(nativeToolExecutionReceipt: receipt)
            FileHandle.standardError.write(Data("saved native-tool execution receipt: \(url.path)\n".utf8))
        }
        if options.json {
            try printJSON(receipt)
        } else {
            printNativeToolExecutionReceipt(receipt)
        }
        try requireSuccessfulNativeToolReceipt(receipt)
    }

    private static func requireSuccessfulHomebrewReceipt(_ receipt: NativeActionReceipt) throws {
        guard receipt.exitCode == 0, receipt.skippedReason == nil else {
            let reason: String
            if let skippedReason = receipt.skippedReason {
                reason = skippedReason
            } else if let exitCode = receipt.exitCode {
                reason = "Homebrew exited with status \(exitCode)."
            } else {
                reason = "Homebrew did not produce a successful exit status."
            }
            throw CLIError.message("Homebrew command failed: \(reason)")
        }
    }

    private static func requireSuccessfulNativeToolReceipt(_ receipt: NativeToolExecutionReceipt) throws {
        guard receipt.status != "failed" else {
            let detail = receipt.errors.isEmpty ? receipt.message : receipt.errors.joined(separator: " ")
            throw CLIError.message("Native command failed: \(detail)")
        }
    }

    private static func requireSuccessfulNativeMaintenanceReceipt(_ receipt: NativeActionReceipt) throws {
        guard receipt.exitCode == 0, receipt.skippedReason == nil else {
            let detail = receipt.skippedReason ?? "Command exited with status \(receipt.exitCode.map(String.init) ?? "unknown")."
            throw CLIError.message("Native maintenance command failed: \(detail)")
        }
    }

    static func nativeReceipts(args: [String]) throws {
        let subcommand = args.first ?? "list"
        let options = ParsedOptions(Array(args.dropFirst()))
        try options.validateReportPrivacyOptions()
        let store = AuditStore()
        switch subcommand {
        case "list":
            let receipts = store.recentNativeToolExecutionReceipts(limit: options.limit)
            if options.json {
                try printJSON(receipts)
            } else {
                printNativeToolExecutionReceipts(receipts)
            }
        case "export":
            let receipt = options.receiptID.flatMap { store.nativeToolExecutionReceipt(id: $0) }
                ?? store.recentNativeToolExecutionReceipts(limit: 1).first
            guard let receipt else {
                throw CLIError.message("No saved native command receipt found. Run `reclaimer native run --command-id COMMAND_ID --dry-run --save-audit` first, or pass --id for an existing receipt.")
            }
            let report = NativeToolExecutionReceiptReportBuilder.build(
                title: options.nativeReceiptReportTitle,
                receipt: receipt,
                privacy: options.reportPrivacy
            )
            if let output = options.outputPath {
                let url = URL(fileURLWithPath: output).standardizedFileURL
                try SafeFileOutput.write(report.markdown, to: url)
                FileHandle.standardError.write(Data("wrote native command receipt report: \(url.path)\n".utf8))
            }
            if options.saveReport {
                let url = try ReportStore().save(nativeToolExecutionReceiptReport: report)
                FileHandle.standardError.write(Data("saved native command receipt report: \(url.path)\n".utf8))
            }
            if options.json {
                try printJSON(report)
            } else if options.outputPath == nil {
                print(report.markdown)
            }
        default:
            throw CLIError.message("Unknown native receipts subcommand: \(subcommand)")
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
            try printJSON(report)
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
                try printJSON(policy)
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
                try printJSON(policy)
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
                try printJSON(policy)
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
                try printJSON(document)
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
                try printJSON(result)
            } else {
                printPolicyImportResult(result)
            }
        default:
            throw CLIError.message("Unknown policy subcommand: \(subcommand)")
        }
    }

    private struct PlanCommandEvidence {
        let ruleEngine: RuleEngine
        let plan: ReclaimPlan
        let scanSession: ScanSession
    }

    private static func buildPlanCommandEvidence(options: ParsedOptions) throws -> PlanCommandEvidence {
        let ruleEngine = try options.ruleEngine()
        let scopePlan = try options.scopePlan()
        let preset: ScanScopePreset
        if let scopePlanPreset = scopePlan.preset {
            preset = scopePlanPreset
        } else {
            preset = try options.scopePreset()
        }
        let scopes = scopePlan.scopes
        let scanOptions = options.scanOptions(includeOpenFiles: false)
        let openFileChecker: any OpenFileChecking = options.noLsof ? NoOpenFilesChecker() : LsofOpenFileChecker()
        let scanner = try FileScanner(ruleEngine: ruleEngine, openFileChecker: openFileChecker)
        let findings = scanner.scan(scopes: scopes, options: scanOptions)
        let plan = PlanBuilder(openFileChecker: openFileChecker)
            .buildPlan(from: findings, mode: options.reviewAll ? .reviewAll : .autoSafeOnly)
        let scanSession = ScanSessionEvidenceBuilder.scannedSession(
            appVersion: "reclaimer-cli",
            ruleVersion: ruleEngine.version,
            preset: preset,
            scopes: scopes,
            userPathPolicy: scanOptions.userPathPolicy,
            findings: findings
        )
        return PlanCommandEvidence(
            ruleEngine: ruleEngine,
            plan: plan,
            scanSession: scanSession
        )
    }

    private static func matchingSessionForAuditTransition(
        store: AuditStore,
        currentScanSession: ScanSession
    ) throws -> ScanSession {
        guard let latest = try store.latestScanSession() else {
            return currentScanSession
        }
        let validated = latest.invalidatedIfBaselineChanged(
            scopeDigest: currentScanSession.scopeDigest,
            ruleVersion: currentScanSession.ruleVersion,
            policyDigest: currentScanSession.policyDigest,
            findingDigest: currentScanSession.findingDigest
        )
        return validated.stage == .invalidated ? currentScanSession : validated
    }

    private static func sessionForExecutionGate(
        store: AuditStore,
        currentScanSession: ScanSession
    ) throws -> ScanSession {
        guard let latest = try store.latestScanSession() else {
            return currentScanSession
        }
        return latest.invalidatedIfBaselineChanged(
            scopeDigest: currentScanSession.scopeDigest,
            ruleVersion: currentScanSession.ruleVersion,
            policyDigest: currentScanSession.policyDigest,
            findingDigest: currentScanSession.findingDigest
        )
    }

    private static func shouldRecordExecutionTransition(_ receipt: ExecutionReceipt) -> Bool {
        receipt.mode == ExecutionMode.perform.rawValue
            && receipt.actions.contains { $0.status == "done" }
    }

    static func plan(args: [String]) throws {
        let options = ParsedOptions(args)
        try options.validateReportPrivacyOptions()
        let evidence = try buildPlanCommandEvidence(options: options)
        let plan = evidence.plan
        if options.saveAudit {
            let store = AuditStore()
            let url = try store.save(plan: plan)
            let session = try matchingSessionForAuditTransition(
                store: store,
                currentScanSession: evidence.scanSession
            )
            try store.saveScanSession(session.recordPlan(planDigest: plan.id))
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
                try SafeFileOutput.write(report.markdown, to: url)
                FileHandle.standardError.write(Data("wrote plan report: \(url.path)\n".utf8))
            }
            if options.saveReport {
                let url = try ReportStore().save(planReport: report)
                FileHandle.standardError.write(Data("saved plan report: \(url.path)\n".utf8))
            }
        }
        if options.json {
            try printJSON(plan)
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
                try printJSON(plans)
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
                try SafeFileOutput.write(report.markdown, to: url)
                FileHandle.standardError.write(Data("wrote plan report: \(url.path)\n".utf8))
            }
            if options.saveReport {
                let url = try ReportStore().save(planReport: report)
                FileHandle.standardError.write(Data("saved plan report: \(url.path)\n".utf8))
            }
            if options.json {
                try printJSON(report)
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
        let report = FindingExplanationBuilder.build(for: finding)
        if options.json {
            try printJSON(report)
        } else {
            printFindingExplanationReport(report)
        }
    }

    static func execute(args: [String]) throws {
        let options = ParsedOptions(args)
        guard options.dryRun else {
            throw CLIError.message("execute is dry-run only because automatic filesystem mutation cannot be bound to the verified object. Review the plan and remove selected items manually in Finder.")
        }
        let evidence = try buildPlanCommandEvidence(options: options)
        let plan = evidence.plan
        let store = AuditStore()
        let session = if options.dryRun {
            try matchingSessionForAuditTransition(
                store: store,
                currentScanSession: evidence.scanSession
            )
        } else {
            try sessionForExecutionGate(
                store: store,
                currentScanSession: evidence.scanSession
            )
        }
        let receipt = ReclaimerExecutor(
            openFileChecker: options.noLsof ? NoOpenFilesChecker() : LsofOpenFileChecker(),
            configuration: ExecutorConfiguration(
                userPathPolicy: options.userPathPolicy,
                currentScanSession: session
            )
        )
            .execute(
                plan: plan,
                mode: options.dryRun ? .dryRun : .perform,
                ruleVersion: evidence.ruleEngine.version,
                userConfirmed: options.yes
            )
        if options.saveAudit {
            let url = try store.save(receipt: receipt)
            if options.dryRun {
                try store.saveScanSession(
                    session
                        .recordPlan(planDigest: plan.id)
                        .recordDryRunReceipt(receipt)
                )
            } else if shouldRecordExecutionTransition(receipt) {
                try store.saveScanSession(session.recordExecutionReceipt(receipt))
            } else {
                try store.saveScanSession(session)
            }
            FileHandle.standardError.write(Data("saved receipt: \(url.path)\n".utf8))
        }
        if options.json {
            try printJSON(receipt)
        } else {
            printReceipt(receipt)
        }
    }

    static func archive(args: [String]) throws {
        let options = ParsedOptions(args)
        let scopes = try options.scopes(includeUnavailable: options.includeMissingScopes)
        let scanner = try FileScanner(ruleEngine: try options.ruleEngine(), openFileChecker: options.noLsof ? NoOpenFilesChecker() : LsofOpenFileChecker())
        let findings = scanner.scan(scopes: scopes, options: options.scanOptions(includeOpenFiles: options.includeOpenFiles))
        let report = ArchiveReviewBuilder.build(
            title: options.archiveReviewTitle,
            findings: options.prepare(findings),
            mode: try options.largeOldReviewMode(),
            sort: try options.topOffenderSort(),
            limit: options.limit,
            privacy: options.reportPrivacy
        )
        if let output = options.outputPath {
            let url = URL(fileURLWithPath: output).standardizedFileURL
            try SafeFileOutput.write(report.markdown, to: url)
            FileHandle.standardError.write(Data("wrote archive review: \(url.path)\n".utf8))
        }
        if options.saveReport {
            let url = try ReportStore().save(archiveReviewReport: report)
            FileHandle.standardError.write(Data("saved archive review: \(url.path)\n".utf8))
        }
        if options.json {
            try printJSON(report)
        } else if options.outputPath == nil {
            printArchiveReviewReport(report)
        }
    }

    static func schedule(args: [String]) throws {
        guard let subcommand = args.first else {
            throw CLIError.message("schedule requires preview, install, uninstall, or status")
        }
        let manager = LaunchAgentManager()
        switch subcommand {
        case "preview":
            let options = ParsedOptions(Array(args.dropFirst()))
            let cli = options.value(after: "--cli-path")
                ?? URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL.path
            let schedule = try options.scheduleConfiguration()
            let preview = manager.preview(cliPath: cli, schedule: schedule)
            if options.json {
                try printJSON(preview)
            } else {
                printSchedulePreview(preview)
                print(manager.plist(cliPath: cli, logPath: preview.logPath, schedule: schedule))
            }
        case "install":
            let cli = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL.path
            let options = ParsedOptions(Array(args.dropFirst()))
            let schedule = try options.scheduleConfiguration()
            let url = try manager.install(cliPath: cli, schedule: schedule)
            print("installed launch agent plist: \(url.path)")
            print("scheduled report: \(schedule.reportKind.label), \(schedule.scopeSelection.summary), \(String(format: "%02d:%02d", schedule.hour, schedule.minute))")
            if args.contains("--load") {
                try manager.load()
                print("loaded launch agent")
            } else {
                print("load with: launchctl bootstrap gui/$(id -u) \(url.path)")
            }
        case "uninstall":
            if args.contains("--unload") {
                throw CLIError.message(manager.manualRemovalGuidance())
            }
            try manager.uninstall()
            print("no launch agent plist exists; nothing changed")
        case "status":
            let options = ParsedOptions(Array(args.dropFirst()))
            let status = manager.status(cliPath: URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL.path)
            if options.json {
                try printJSON(status)
            } else {
                printLaunchAgentStatus(status)
            }
        default:
            throw CLIError.message("Unknown schedule subcommand: \(subcommand)")
        }
    }

    static func holding(args: [String]) throws {
        guard let subcommand = args.first else {
            throw CLIError.message("holding requires list or expire")
        }
        let options = ParsedOptions(args)
        let store = HoldingStore()
        switch subcommand {
        case "list":
            let items = store.list()
            if options.json {
                try printJSON(items)
            } else {
                printHeldItems(items)
            }
        case "restore":
            guard args.indices.contains(1), !args[1].hasPrefix("-") else {
                throw CLIError.message("holding restore requires a held item id")
            }
            throw CLIError.message("holding restore is manual Finder work because macOS cannot bind the final path move to the verified held item. Reveal the holding record and move it manually after review.")
        case "expire":
            guard !options.yes else {
                throw CLIError.message("holding expire is dry-run only because delete cannot be bound to the verified held item. Review the list manually in Finder.")
            }
            let days = Double(options.value(after: "--older-than-days") ?? "") ?? 30
            guard days >= 0 else {
                throw CLIError.message("--older-than-days must be zero or greater")
            }
            let cutoff = Date().addingTimeInterval(-days * 24 * 60 * 60)
            let expired = try store.expire(olderThan: cutoff, dryRun: true)
            print("would expire \(expired.count) held item(s); Holding-area recovery is manual Finder work and Ryddi will not remove them automatically")
            printHeldItems(expired)
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
              release-trust [--json] [--manifest PATH]
              trust [--json] [--preset developer|general|all] [--template TEMPLATE_ID] [--path PATH ...] [--scope-set NAME_OR_ID]
                    [--manifest PATH]
              dogfood [--json] [--preset developer|general|all] [--template TEMPLATE_ID] [--path PATH ...] [--scope-set NAME_OR_ID] [--output PATH]
                      [--path-style full|home-relative|redacted] [--redact-user-text]
              scopes [--json] [--preset developer|general|all] [--template TEMPLATE_ID] [--path PATH ...] [--scope-set NAME_OR_ID]
              scopes templates list [--json] [--include-missing-scopes]
              scopes templates show TEMPLATE_ID [--json]
              scopes templates save TEMPLATE_ID [--name NAME] [--summary TEXT] [--json]
              scopes saved list [--json]
              scopes saved show NAME_OR_ID [--json]
              scopes saved add NAME --path PATH ... [--summary TEXT] [--json]
              scopes saved remove NAME_OR_ID [--json]
              scopes saved export [--json] [--output PATH]
              scopes saved import PATH [--json] [--replace]
              scan [--json] [--preset developer|general|all] [--template TEMPLATE_ID] [--path PATH ...] [--scope-set NAME_OR_ID] [--min-size BYTES] [--max-depth N] [--measurement-depth N] [--measurement-budget N] [--no-deduplicate-hardlinks] [--include-open-files]
                   [--sort size|logical|age|risk|category|scope] [--group category|safety|scope]
                   [--review large|old|all] [--limit N] [--include-missing-scopes] [--ignore-user-policy] [--include-user-rules]
              session latest [--json]
              session explain [--json]
              actions [--json] [--preset developer|general|all] [--template TEMPLATE_ID] [--path PATH ...] [--scope-set NAME_OR_ID]
              overview [--json] [--preset developer|general|all] [--template TEMPLATE_ID] [--path PATH ...] [--scope-set NAME_OR_ID] [--limit N] [--measurement-depth N] [--measurement-budget N] [--no-deduplicate-hardlinks]
                       [--sort size|logical|reclaim|age|risk|category|safety|scope|owner|action]
                       [--group none|category|safety|owner|scope|action]
                       [--save-history] [--ignore-user-policy] [--include-user-rules]
              queues [--json] [--preset developer|general|all] [--template TEMPLATE_ID] [--path PATH ...] [--scope-set NAME_OR_ID]
                     [--min-size BYTES] [--max-depth N] [--include-open-files] [--limit N]
                     [--queue safe-maintenance|quit-app-first|use-native-tool|valuable-history|personal-app-assets|unknown]
                     [--include-missing-scopes] [--ignore-user-policy] [--include-user-rules]
              large [--json] [--preset developer|general|all] [--template TEMPLATE_ID] [--path PATH ...] [--scope-set NAME_OR_ID]
                    [--min-size BYTES] [--max-depth N] [--large-threshold BYTES] [--old-days N]
                    [--review large|old|all] [--sort size|logical|age|category|owner|safety] [--limit N]
                    [--include-missing-scopes] [--ignore-user-policy] [--include-user-rules]
              drilldown [--json] [--preset developer|general|all] [--template TEMPLATE_ID] [--path PATH ...] [--scope-set NAME_OR_ID] [--min-size BYTES] [--max-depth N]
                        [--tree-depth N] [--limit N] [--include-missing-scopes] [--ignore-user-policy] [--include-user-rules]
              rules [--json] [--include-user-rules]
              rules user list [--json]
              rules user preview PATH [--json]
              rules user import PATH [--json] [--replace]
              rules user export [--json] [--output PATH]
              report [--json] [--preset developer|general|all] [--template TEMPLATE_ID] [--path PATH ...] [--scope-set NAME_OR_ID] [--limit N] [--output PATH] [--save-report]
                     [--title TEXT] [--path-style full|home-relative|redacted] [--redact-user-text]
                     [--include-missing-scopes] [--ignore-user-policy] [--include-user-rules]
              permissions [--json] [--preset developer|general|all] [--template TEMPLATE_ID] [--path PATH ...] [--scope-set NAME_OR_ID] [--include-missing-scopes]
              permissions guide [--json] [--preset developer|general|all] [--template TEMPLATE_ID] [--path PATH ...] [--scope-set NAME_OR_ID] [--output PATH] [--include-missing-scopes]
              active [--json] [--preset developer|general|all] [--template TEMPLATE_ID] [--path PATH ...] [--scope-set NAME_OR_ID] [--min-size BYTES] [--max-depth N] [--limit N] [--save-audit] [--include-user-rules]
              audit summary [--json]
              audit prune [--dry-run|--yes] [--older-than-days N] [--keep-recent N] [--json]
              issue package --output DIR [--path-style redacted|home-relative] [--include-remote] [--json]
              history record [--json] [--preset developer|general|all] [--template TEMPLATE_ID] [--path PATH ...] [--scope-set NAME_OR_ID] [--limit N]
              history list [--json] [--limit N]
              history diff [--json] [--group category|safety|scope] [--limit N]
              history report [--json] [--group category|safety|scope] [--limit N]
                             [--current-id ID --previous-id ID] [--output PATH] [--save-report]
                             [--title TEXT] [--path-style full|home-relative|redacted] [--redact-user-text]
              history prune [--dry-run|--yes] [--keep-recent N] [--json]
              duplicates [--json] --path PATH ... [--min-size BYTES] [--max-depth N] [--limit N]
                         [--max-files N] [--include-preserve] [--skip-hidden] [--show-excluded]
              downloads [--json] [--path DOWNLOADS_ROOT] [--limit N] [--old-days N] [--max-depth N] [--include-hidden] [--save-audit]
              browsers [--json] [--path CACHE_ROOT ...] [--home HOME] [--limit N] [--max-depth N] [--include-missing-scopes] [--save-audit]
              packages [--json] [--path CACHE_ROOT ...] [--home HOME] [--limit N] [--max-depth N] [--include-missing-scopes] [--save-audit]
              packages lane [--json] [--path CACHE_ROOT ...] [--home HOME] [--limit N] [--max-depth N] [--include-missing-scopes]
              projects [--json] [--path PROJECT_ROOT ...] [--home HOME] [--limit N] [--old-days N] [--search-depth N] [--max-depth N] [--include-vcs-status] [--include-policy-skipped] [--include-missing-scopes] [--save-audit]
              projects policy list [--json]
              projects policy review|preserve|skip-review PROJECT_ROOT [--reason TEXT] [--name NAME] [--json]
              projects policy set PROJECT_ROOT --decision review|preserve|skip-review [--reason TEXT] [--name NAME] [--json]
              projects policy remove PROJECT_ROOT [--json]
              projects policy export [--json] [--output PATH]
              projects policy import PATH [--json] [--replace]
              device-backups [--json] [--path BACKUP_ROOT] [--home HOME] [--limit N] [--old-days N] [--max-depth N] [--save-audit]
              xcode [--json] [--path XCODE_ROOT ...] [--home HOME] [--limit N] [--old-days N] [--max-depth N] [--include-missing-scopes] [--save-audit]
              trash [--json] [--path TRASH_ROOT] [--limit N] [--max-depth N] [--save-audit]
              apps [--json] [--path APP_ROOT ...] [--home HOME] [--min-size BYTES] [--limit N]
                   [--include-system-apps] [--no-orphans] [--show-excluded]
              apps uninstall-preview [--json] (--app PATH | --bundle-id ID | --name NAME)
                   [--path APP_ROOT ...] [--home HOME] [--min-size BYTES] [--limit N] [--output PATH]
                   [--save-audit] [--path-style full|home-relative|redacted] [--redact-user-text]
              apps uninstall --dry-run [--json] (--app PATH | --bundle-id ID | --name NAME)
                   [--path APP_ROOT ...] [--home HOME] [--min-size BYTES] [--save-audit] [--ignore-user-policy]
              agents [--json] [--path PATH ...] [--template TEMPLATE_ID] [--scope-set NAME_OR_ID] [--min-size BYTES] [--max-depth N] [--limit N]
                     [--include-missing-scopes] [--ignore-user-policy] [--include-user-rules]
              agents retention [--json] [--profile conservative|balanced|aggressive] [--path PATH ...] [--template TEMPLATE_ID] [--scope-set NAME_OR_ID]
                     [--min-size BYTES] [--max-depth N] [--limit N] [--include-missing-scopes] [--ignore-user-policy] [--include-user-rules]
              agents retention-plan [--json] [--profile conservative|balanced|aggressive] [--path PATH ...] [--template TEMPLATE_ID] [--scope-set NAME_OR_ID]
                     [--min-size BYTES] [--max-depth N] [--limit N] [--include-missing-scopes] [--ignore-user-policy] [--include-user-rules]
              native [--json] [--preset developer|general|all] [--template TEMPLATE_ID] [--path PATH ...] [--scope-set NAME_OR_ID] [--limit N] [--save-audit] [--include-user-rules]
              native homebrew cleanup [--dry-run|--yes] [--json] [--timeout SECONDS] [--save-audit] [--finding-path PATH]
              native run --command-id COMMAND_ID [--dry-run|--yes] [--json] [--preset developer|general|all] [--template TEMPLATE_ID] [--path PATH ...] [--scope-set NAME_OR_ID]
                     [--finding-path PATH] [--timeout SECONDS] [--save-audit] [--include-user-rules]
              native receipts list [--json] [--limit N]
              native receipts export [--json] [--id ID] [--output PATH] [--save-report] [--title TEXT]
                     [--path-style full|home-relative|redacted] [--redact-user-text]
              containers [--json] [--limit N] [--timeout SECONDS] [--save-audit]
              remote targets list [--json]
              remote probe TARGET [--json] [--timeout SECONDS] [--save-audit]
              remote scan TARGET [--preset vps-general] [--json] [--timeout SECONDS]
                    [--path-style full|home-relative|redacted] [--output PATH] [--save-audit] [--include-command-cards|--no-command-cards]
              remote dogfood TARGET [--json] [--timeout SECONDS]
                    [--path-style full|home-relative|redacted] [--output PATH] [--save-audit]
              remote dogfood --from-audit TARGET [--json]
                    [--path-style full|home-relative|redacted] [--output PATH] [--save-audit]
              remote native TARGET [--json] [--timeout SECONDS]
              remote plan TARGET [--preset vps-general] [--json] [--timeout SECONDS]
              remote history [list] [--json] [--limit N]
              remote history diff [--json] [--limit N] [--current-id ID --previous-id ID]
              remote history report [--json] [--limit N] [--current-id ID --previous-id ID]
                    [--path-style full|home-relative|redacted] [--output PATH]
              policy list [--json]
              policy protect PATH [--reason TEXT]
              policy exclude PATH [--reason TEXT]
              policy remove PATH [--kind protect|exclude]
              policy export [--json] [--output PATH]
              policy import PATH [--json] [--replace]
              plan [--json] [--preset developer|general|all] [--template TEMPLATE_ID] [--path PATH ...] [--scope-set NAME_OR_ID] [--review-all] [--save-audit] [--ignore-user-policy] [--include-user-rules]
                   [--output PATH] [--save-report] [--title TEXT]
                   [--path-style full|home-relative|redacted] [--redact-user-text]
              plans list [--json] [--limit N]
              plans export [--json] [--id ID] [--output PATH] [--save-report] [--title TEXT]
                           [--path-style full|home-relative|redacted] [--redact-user-text]
              explain PATH [--json] [--include-user-rules]
              execute --dry-run [--json] [--preset developer|general|all] [--template TEMPLATE_ID] [--path PATH ...] [--scope-set NAME_OR_ID] [--save-audit] [--ignore-user-policy] [--include-user-rules]
              receipts list [--json] [--limit N]
              receipts export [--json] [--id ID] [--output PATH] [--save-report] [--title TEXT]
                              [--path-style full|home-relative|redacted] [--redact-user-text]
              recovery [list] [--json] [--limit N]
              archive [--json] [--preset developer|general|all] [--template TEMPLATE_ID] [--path PATH ...] [--scope-set NAME_OR_ID]
                      [--min-size BYTES] [--max-depth N] [--large-threshold BYTES] [--old-days N]
                      [--review large|old|all] [--sort size|logical|age|category|owner|safety] [--limit N]
                      [--output PATH] [--save-report] [--title TEXT]
                      [--path-style full|home-relative|redacted] [--redact-user-text]
                      [--include-missing-scopes] [--include-open-files] [--ignore-user-policy] [--include-user-rules]
              schedule preview [--json] [--kind plan|evidence] [--preset developer|general|all] [--template TEMPLATE_ID] [--scope-set NAME_OR_ID] [--hour H] [--minute M] [--limit N] [--include-user-rules] [--cli-path PATH]
              schedule install [--kind plan|evidence] [--preset developer|general|all] [--template TEMPLATE_ID] [--scope-set NAME_OR_ID] [--hour H] [--minute M] [--limit N] [--include-user-rules] [--load]
              schedule uninstall
              schedule status [--json]
              holding list [--json]
              holding expire [--older-than-days N]

            Defaults use --preset developer. Use --preset general for ordinary Mac cleanup review roots
            or --preset all for general plus developer/agent storage. Use templates for guided cleanup modes, or saved scope sets for repeatable
            custom roots. User rule packs are local and opt-in
            per scan with --include-user-rules. Core execution is dry-run-only; `execute --yes` is rejected.
            Homebrew cleanup is the narrow exception and requires a fresh preview plus one-time same-process capability.
            Holding-area recovery is manual Finder work; Ryddi does not restore or expire held items automatically.
            Every --output export must name a new file in an existing directory; Ryddi refuses to overwrite an existing file.
            """
        )
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

struct AuditPruneCommandResult: Encodable {
    let plan: AuditPrunePlan
    let receipt: AuditPruneReceipt
}

func encodedJSON<T: Encodable>(_ value: T) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    let data: Data
    do {
        data = try encoder.encode(value)
    } catch {
        throw CLIError.message("JSON encoding failed: \(error.localizedDescription)")
    }
    guard let output = String(data: data, encoding: .utf8) else {
        throw CLIError.message("JSON encoding failed: encoded output was not valid UTF-8.")
    }
    return output
}

func printJSON<T: Encodable>(_ value: T) throws {
    print(try encodedJSON(value))
}

func printLatestScanSession(_ session: ScanSession?) {
    guard let session else {
        print("No scan session has been recorded yet.")
        print("Next: run `reclaimer scan --preset developer`.")
        return
    }
    print("Session: \(session.id)")
    print("Stage: \(session.stage.rawValue)")
    print("Preset: \(session.preset.rawValue)")
    print("Updated: \(session.updatedAt.formatted(date: .numeric, time: .standard))")
}

func printScanSessionExplanation(_ session: ScanSession?) {
    guard let session else {
        print("No scan session has been recorded yet.")
        print("Next: run `reclaimer scan --preset developer`.")
        return
    }

    print("Session: \(session.id)")
    print("Stage: \(session.stage.rawValue)")
    print("Preset: \(session.preset.rawValue)")
    print("Updated: \(session.updatedAt.formatted(date: .numeric, time: .standard))")
    print("\nEvidence")
    print("- findings: \(session.findingDigest ?? "missing")")
    print("- plan: \(session.planDigest ?? "missing")")
    print("- dry-run receipt: \(session.dryRunReceiptID ?? "missing")")
    print("- execution receipt: \(session.executionReceiptID ?? "missing")")

    let blockedReasons = scanSessionBlockedReasons(session)
    if !blockedReasons.isEmpty {
        print("\nBlocked reasons")
        for reason in blockedReasons {
            print("- \(reason)")
        }
    }

    print("\nNext: \(nextScanSessionCommand(session))")
}

func printActionCenter(_ report: ActionCenterReport) {
    guard let primary = report.primaryAction else {
        print("Primary action: none")
        print("Why: No current action is available from saved evidence.")
        printActionCenterNonClaims(report.nonClaims)
        return
    }

    print("Primary action: \(primary.title)")
    print("Kind: \(primary.kind.rawValue)")
    print("Why: \(primary.reason)")
    print("Estimated reclaim: \(ByteFormat.string(primary.estimatedReclaimBytes))")
    print("Count: \(primary.count)")
    print("Destructive: \(primary.isDestructive ? "yes" : "no")")

    let blockedReasons = actionCenterBlockedReasons(report)
    if !blockedReasons.isEmpty {
        print("\nBlocked reasons")
        for reason in blockedReasons {
            print("- \(reason)")
        }
    }

    let secondary = report.actions.dropFirst()
    if !secondary.isEmpty {
        print("\nOther actions")
        for action in secondary {
            print("- \(action.title): \(action.reason)")
        }
    }

    printActionCenterNonClaims(report.nonClaims)
}

func printActionCenterNonClaims(_ nonClaims: [String]) {
    print("\nNon-claims")
    for note in nonClaims {
        print("- \(note)")
    }
}

func scanSessionBlockedReasons(_ session: ScanSession) -> [String] {
    var reasons: [String] = []
    if !session.invalidationReasons.isEmpty {
        reasons.append(contentsOf: session.invalidationReasons.map(\.rawValue))
    }
    if session.findingDigest == nil {
        reasons.append("Finding evidence is missing.")
    }
    switch session.stage {
    case .notStarted:
        reasons.append("No scan has been recorded for this session.")
    case .scanned:
        reasons.append("Review queues before creating a reclaim plan.")
    case .reviewed:
        reasons.append("No reclaim plan has been recorded for the reviewed selection.")
    case .planReady:
        reasons.append("No dry-run receipt has been recorded for the current plan.")
    case .dryRunReady:
        if session.dryRunReceiptID == nil {
            reasons.append("Dry-run receipt evidence is missing.")
        }
    case .reclaimReady:
        reasons.append("Core filesystem cleanup is manual-only; review the selected paths in Finder.")
    case .executed:
        reasons.append("Cleanup already executed for this session.")
    case .recoveryAvailable:
        reasons.append("Recovery evidence is available from a completed cleanup.")
    case .invalidated:
        reasons.append("The session was invalidated by newer baseline evidence.")
    }
    return uniquePreservingOrder(reasons)
}

func nextScanSessionCommand(_ session: ScanSession) -> String {
    switch session.stage {
    case .notStarted, .invalidated:
        return "run `reclaimer scan --preset \(session.preset.rawValue)`"
    case .scanned:
        return "review queues, then run `reclaimer plan --preset \(session.preset.rawValue) --save-audit`"
    case .reviewed:
        return "run `reclaimer plan --preset \(session.preset.rawValue) --save-audit`"
    case .planReady:
        return "run `reclaimer execute --dry-run --preset \(session.preset.rawValue) --save-audit`"
    case .dryRunReady, .reclaimReady:
        return "review the dry-run receipt and selected paths in Finder; core filesystem cleanup is manual-only"
    case .executed, .recoveryAvailable:
        return "run `reclaimer recovery list` to review recovery state"
    }
}

func actionCenterBlockedReasons(_ report: ActionCenterReport) -> [String] {
    guard report.primaryAction?.kind != .executeSafePlan else {
        return []
    }
    let reasons = report.actions.map(\.reason).filter { !$0.isEmpty }
    return uniquePreservingOrder(reasons)
}

func uniquePreservingOrder(_ values: [String]) -> [String] {
    var seen = Set<String>()
    return values.filter { seen.insert($0).inserted }
}

func printReleaseTrustEvidence(_ evidence: ReleaseTrustEvidence) {
    print("Ryddi release trust")
    print("State: \(evidence.state.label)")
    print("Summary: \(evidence.summary)")
    print("Manifest: \(evidence.manifestPath ?? "not supplied")")
    print("Version: \(evidence.version ?? "unknown")")
    print("Build: \(evidence.buildNumber ?? "unknown")")
    print("Artifact: \(evidence.artifactName ?? "unknown")")
    print("SHA-256: \(evidence.artifactSHA256 ?? "unknown")")
    print("Commit: \(evidence.sourceCommit ?? "unknown")")
    print("\nGates")
    print("- codesign verified: \(evidence.codesignVerified ? "yes" : "no")")
    print("- Hardened Runtime: \(evidence.hardenedRuntime ? "yes" : "no")")
    print("- notarization status: \(evidence.notarizationStatus ?? "unknown")")
    print("- stapled: \(evidence.stapleValidated ? "yes" : "no")")
    print("- Gatekeeper accepted: \(evidence.gatekeeperAccepted ? "yes" : "no")")
    if !evidence.warnings.isEmpty {
        print("\nWarnings")
        for warning in evidence.warnings {
            print("- \(warning)")
        }
    }
}

func printTrustReadiness(_ report: TrustReadinessReport) {
    print("Ryddi trust readiness")
    print("Generated: \(report.createdAt.formatted())")
    print("Disk: \(report.diskStatus.pressure.label) - \(report.diskStatus.statusLine)")
    print("Coverage: \(report.permissionSummary.coverageLevel.label), \(report.permissionSummary.coverageSummary)")
    print("Automation: \(report.automationInstalled ? "installed" : "not installed")")
    print("Release trust: \(report.releaseTrustEvidence.state.label) - \(report.releaseTrustEvidence.summary)")
    if let plan = report.latestPlanSummary {
        print("Latest plan: \(plan.selectedCount)/\(plan.itemCount) selected, \(ByteFormat.string(plan.expectedImmediateReclaim)) expected reclaim")
    } else {
        print("Latest plan: none")
    }
    if let receipt = report.latestReceiptSummary {
        print("Latest receipt: \(receipt.mode), \(receipt.actionCount) action(s), \(receipt.errorCount) error(s)")
    } else {
        print("Latest receipt: none")
    }
    print("\nRecommended actions")
    for action in report.recommendedActions {
        print("- [\(action.severity.label)] \(action.title): \(action.detail)")
    }
    print("\nNon-claims")
    for note in report.nonClaims {
        print("- \(note)")
    }
}

func printLaunchAgentStatus(_ status: LaunchAgentStatus) {
    print("Ryddi scheduled report status")
    print("Label: \(status.label)")
    print("Installed: \(status.installed ? "yes" : "no")")
    print("Plist: \(status.installedPath)")
    print("Loaded check: \(status.loadedState)")
    print("Log: \(status.lastLogPath)")
    print("Scope: \(status.scopeSummary)")
    print("Report: \(status.reportKind.label)")
    print("Next scheduled time: \(status.nextScheduledTimeDisplay)")
    print("\nProgram arguments:")
    for argument in status.programArguments {
        print("- \(argument)")
    }
    print("\nNon-claims")
    for note in status.nonClaims {
        print("- \(note)")
    }
}

func printSchedulePreview(_ preview: LaunchAgentPreview) {
    print("Ryddi scheduled report preview")
    print("Label: \(preview.label)")
    print("Plist: \(preview.plistPath)")
    print("Log: \(preview.logPath)")
    print("Report: \(preview.schedule.reportKind.label)")
    print("Scope: \(preview.schedule.scopeSelection.summary)")
    print("Time: \(String(format: "%02d:%02d", preview.schedule.hour, preview.schedule.minute))")
    print("Program arguments:")
    for argument in preview.programArguments {
        print("- \(argument)")
    }
    print("\nNon-claims")
    for note in preview.nonClaims {
        print("- \(note)")
    }
    print("\nPlist")
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

func printScopeTemplates(_ templates: [ScopeTemplate]) {
    print("Ryddi scope templates")
    print("Templates: \(templates.count)")
    let groups = Dictionary(grouping: templates, by: \.group)
    for group in groups.keys.sorted() {
        print("\n\(group)")
        for template in (groups[group] ?? []).sorted(by: { $0.name < $1.name }) {
            print("- \(template.name) (\(template.id), \(template.scopes.count) root(s))")
            print("  \(template.summary)")
        }
    }
    print("\nNon-claims")
    for note in ScopeTemplateCatalog.defaultNonClaims {
        print("- \(note)")
    }
}

func printScopeTemplate(_ template: ScopeTemplate) {
    print("Ryddi scope template")
    print("Name: \(template.name)")
    print("ID: \(template.id)")
    print("Group: \(template.group)")
    print("Recommended use: \(template.recommendedUse)")
    print(template.summary)
    print("Scopes: \(template.scopes.count)")
    print("\nRoots")
    for scope in template.scopes {
        print("- \(scope.name): \(scope.root.path)")
    }
    print("\nNon-claims")
    for note in template.nonClaims {
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
    print("Scope summary: \(report.coverageSummary)")
    print("Readable scopes: \(report.readableCount)/\(report.totalCount)")
    print("Denied: \(report.deniedCount)")
    print("Missing: \(report.missingCount)")
    print("Unknown: \(report.unknownCount)")
    print("Full Disk Access settings: \(report.fullDiskAccessSettingsURL)")

    print("\nRecommended actions")
    for action in report.recommendedActions {
        print("- \(action)")
    }

    if !report.blockingUnavailableScopes.isEmpty {
        print("\nAccess blockers")
        for scope in report.blockingUnavailableScopes {
            print("- \(scope.permissionState.rawValue): \(scope.name) - \(scope.path)")
            print("  \(scope.message)")
        }
    }
    if !report.optionalUnavailableScopes.isEmpty {
        print("\nOptional missing roots")
        for scope in report.optionalUnavailableScopes {
            print("- \(scope.name) - \(scope.path)")
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
        print("\(pad("State", 13)) \(pad("Bytes", 11)) \(pad("Scope", 10)) \(pad("Safety", 22)) \(pad("Processes", 36)) Path")
        for item in report.items {
            let processes: String
            if !item.processSummary.isEmpty {
                processes = item.processSummary.joined(separator: ", ")
            } else if let failure = item.checkFailed {
                processes = failure
            } else {
                processes = "-"
            }
            let scope = item.finding.openFileStatus?.checkedRecursively == true ? "recursive" : "single"
            print("\(pad(item.state.label, 13)) \(pad(ByteFormat.string(item.finding.allocatedSize), 11)) \(pad(scope, 10)) \(pad(item.finding.safetyClass.label, 22)) \(pad(processes, 36)) \(item.finding.path)")
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
            if let workingDirectory = command.workingDirectory {
                print("  Working directory: \(workingDirectory)")
            }
            if let context = command.context {
                print("  Context: \(context)")
            }
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

func printNativeToolExecutionReceipt(_ receipt: NativeToolExecutionReceipt) {
    print("Native tool execution receipt \(receipt.id)")
    print("Generated: \(receipt.createdAt.formatted())")
    print("Rule version: \(receipt.ruleVersion)")
    print("Mode: \(receipt.mode.rawValue)")
    print("Status: \(receipt.status)")
    print("Finding path: \(receipt.findingPath)")
    print("Category: \(receipt.category)")
    print("Command id: \(receipt.command.id)")
    print("Command: \(receipt.command.command)")
    print("Risk: \(receipt.command.risk.label)")
    print("User confirmed: \(receipt.userConfirmed ? "yes" : "no")")
    if let before = receipt.beforeFreeBytes {
        print("Before free: \(ByteFormat.string(before))")
    }
    if receipt.mode == .perform, let after = receipt.afterFreeBytes {
        print("After free: \(ByteFormat.string(after))")
    }
    print("Message: \(receipt.message)")
    if let output = receipt.output {
        print("\nCommand output")
        print("Status: \(output.status)")
        if let exitCode = output.exitCode {
            print("Exit code: \(exitCode)")
        }
        if !output.stdoutPreview.isEmpty {
            print("stdout:")
            for line in output.stdoutPreview {
                print("  \(line)")
            }
        }
        if !output.stderrPreview.isEmpty {
            print("stderr:")
            for line in output.stderrPreview {
                print("  \(line)")
            }
        }
        if let launchError = output.launchError {
            print("Launch error: \(launchError)")
        }
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

func printNativeToolExecutionReceipts(_ receipts: [NativeToolExecutionReceipt]) {
    if receipts.isEmpty {
        print("No saved native command receipts.")
        return
    }
    print("\(pad("Created", 22)) \(pad("Mode", 8)) \(pad("Status", 10)) \(pad("Command", 22)) \(pad("Confirmed", 10)) ID")
    for receipt in receipts {
        print(
            "\(pad(receipt.createdAt.formatted(date: .numeric, time: .shortened), 22)) "
            + "\(pad(receipt.mode.rawValue, 8)) "
            + "\(pad(receipt.status, 10)) "
            + "\(pad(receipt.command.id, 22)) "
            + "\(pad(receipt.userConfirmed ? "yes" : "no", 10)) "
            + receipt.id
        )
    }
}

func printNativeActionReceipt(_ receipt: NativeActionReceipt) {
    print("Native action receipt \(receipt.id)")
    print("Generated: \(receipt.createdAt.formatted())")
    print("Kind: \(receipt.kind.rawValue)")
    print("Mode: \(receipt.mode.rawValue)")
    print("Command: \(receipt.commandDisplay.joined(separator: " "))")
    if let exitCode = receipt.exitCode {
        print("Exit code: \(exitCode)")
    }
    if let before = receipt.beforeDisk?.displayFreeBytes {
        print("Before free: \(ByteFormat.string(before))")
    }
    if receipt.mode == .perform, let after = receipt.afterDisk?.displayFreeBytes {
        print("After free: \(ByteFormat.string(after))")
    }
    if let skippedReason = receipt.skippedReason {
        print("Skipped: \(skippedReason)")
    }
    if !receipt.stdoutPreview.isEmpty {
        print("stdout:")
        for line in receipt.stdoutPreview {
            print("  \(line)")
        }
    }
    if !receipt.stderrPreview.isEmpty {
        print("stderr:")
        for line in receipt.stderrPreview {
            print("  \(line)")
        }
    }
    if !receipt.nonClaims.isEmpty {
        print("\nNon-claims")
        for note in receipt.nonClaims {
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

func printProjectDependencyPolicy(_ policy: ProjectDependencyPolicy) {
    print("Ryddi project dependency policy")
    if policy.projects.isEmpty {
        print("No saved project dependency policies configured.")
        return
    }
    for decision in ProjectDependencyPolicyDecision.allCases {
        let projects = policy.policies(decision: decision)
        guard !projects.isEmpty else { continue }
        print("\n\(decision.label)")
        for project in projects {
            let reason = project.reason.map { " - \($0)" } ?? ""
            print("- \(project.projectName): \(project.projectRootPath)\(reason)")
        }
    }
    print("\nNon-claims")
    for note in ProjectDependencyPolicyDocument.defaultNonClaims {
        print("- \(note)")
    }
}

func printProjectDependencyPolicyExportSummary(_ document: ProjectDependencyPolicyDocument) {
    print("Ryddi project dependency policy export")
    print("Projects: \(document.projects.count)")
    print("Schema: \(document.schemaVersion)")
    print("\nNon-claims")
    for note in document.nonClaims {
        print("- \(note)")
    }
}

func printProjectDependencyPolicyImportResult(_ result: ProjectDependencyPolicyImportResult) {
    print("Imported project dependency policy")
    print("Mode: \(result.mode)")
    print("Source: \(result.sourcePath)")
    print("Policy file: \(result.policyPath)")
    print("Imported projects: \(result.importedProjectCount)")
    print("Final projects: \(result.finalProjectCount)")
    print("")
    printProjectDependencyPolicy(result.policy)
    print("\nNon-claims")
    for note in result.nonClaims {
        print("- \(note)")
    }
}

func pad(_ value: String, _ length: Int) -> String {
    if value.count >= length {
        return String(value.prefix(max(0, length - 1))) + " "
    }
    return value.padding(toLength: length, withPad: " ", startingAt: 0)
}
