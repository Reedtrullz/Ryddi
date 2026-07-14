import Foundation
import ReclaimerCore

extension ReclaimerCLI {
    static func dogfood(args: [String]) throws {
        let options = ParsedOptions(args)
        try options.validateReportPrivacyOptions()
        let preset = try options.scopePreset()
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
            .withScanCoverage(result.coverage)
        let queues = FindingAnalytics.reviewQueueReport(findings: findings, limitPerQueue: options.limit)
        let plan = PlanBuilder(openFileChecker: LsofOpenFileChecker()).buildPlan(from: findings, mode: .autoSafeOnly)
        let activeReport = ActiveFileReviewScanner(openFileChecker: LsofOpenFileChecker()).review(
            findings: findings,
            options: ActiveFileReviewOptions(limit: options.limit)
        )
        let report = DogfoodReportBuilder.build(
            preset: preset,
            overview: overview,
            queues: queues,
            plan: plan,
            activeFileReport: activeReport,
            permissionReport: PermissionAdvisor.report(scopeSummaries: overview.scopeSummaries),
            diskStatus: DiskStatusReader().snapshot(),
            privacy: options.reportPrivacy
        )
        if let output = options.outputPath {
            let url = URL(fileURLWithPath: output).standardizedFileURL
            try SafeFileOutput.write(report.markdown, to: url)
            FileHandle.standardError.write(Data("wrote dogfood report: \(url.path)\n".utf8))
        }
        if options.json {
            printJSON(report)
        } else if options.outputPath == nil {
            print(report.markdown)
        }
    }

    static func report(args: [String]) throws {
        let options = ParsedOptions(args)
        try options.validateReportPrivacyOptions()
        let scopes = try options.scopes(includeUnavailable: true)
        let scanner = try FileScanner(ruleEngine: try options.ruleEngine(), openFileChecker: options.noLsof ? NoOpenFilesChecker() : LsofOpenFileChecker())
        let result = scanner.scanWithCoverage(
            scopes: scopes,
            options: options.scanOptions(includeOpenFiles: options.includeOpenFiles)
        )
        let findings = result.findings
        let overview = FindingAnalytics.overview(
            findings: findings,
            scopes: scopes,
            topLimit: options.limit,
            scopeAccessSummaries: result.coverage.scopeAccessSummaries
        )
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
            try SafeFileOutput.write(report.markdown, to: url)
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

func printFindingExplanationReport(_ report: FindingExplanationReport) {
    let finding = report.finding
    print("Ryddi finding explanation")
    print("Generated: \(report.generatedAt.formatted())")
    print("Path: \(finding.path)")
    print("Summary: \(report.summary)")
    print("Safety: \(finding.safetyClass.label)")
    print("Action: \(finding.actionKind.label)")
    print("Cleanup permission: \(report.cleanupPermission)")

    print("\nWhat this is")
    for line in report.whatThisIs {
        print("- \(line)")
    }

    print("\nWhy matched")
    for line in report.whyMatched {
        print("- \(line)")
    }

    print("\nRisk and exact action")
    print("- Risk: \(report.riskSummary)")
    print("- Exact action: \(report.exactAction)")
    print("- Removal effect: \(report.removalEffect)")

    print("\nRecovery")
    for line in report.recovery {
        print("- \(line)")
    }

    print("\nConditions")
    for line in report.conditions {
        print("- \(line)")
    }

    if let nativeReceipt = report.nativeToolReceipt {
        print("\nNative tool receipt preview")
        print("- \(nativeReceipt.message)")
        for command in nativeReceipt.commands {
            print("- \(command.command) [\(command.risk.label)] \(command.purpose)")
        }
    } else if !report.guidanceCommands.isEmpty {
        print("\nGuidance commands")
        for line in report.guidanceCommands {
            print("- \(line)")
        }
    }

    print("\nNext steps")
    for line in report.nextSteps {
        print("- \(line)")
    }

    print("\nExplanation non-claims")
    for note in report.nonClaims {
        print("- \(note)")
    }
}
