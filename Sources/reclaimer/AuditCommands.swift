import Foundation
import ReclaimerCore

extension ReclaimerCLI {
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
                try SafeFileOutput.write(report.markdown, to: url)
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

    static func audit(args: [String]) throws {
        let subcommand = args.first ?? "summary"
        let options = ParsedOptions(Array(args.dropFirst()))
        let store = AuditStore()
        switch subcommand {
        case "summary":
            let summary = store.summary()
            if options.json {
                printJSON(summary)
            } else {
                printAuditSummary(summary)
            }
        case "prune":
            guard options.dryRun else {
                throw CLIError.message("audit prune is dry-run only because unlink cannot be bound to the verified audit object. Review the plan manually instead.")
            }
            let policy = AuditRetentionPolicy(
                olderThanDays: options.auditOlderThanDays,
                keepRecent: options.keepRecent
            )
            let plan = store.prunePlan(policy: policy)
            let receipt = try store.prune(plan: plan, dryRun: options.dryRun)
            if options.json {
                printJSON(AuditPruneCommandResult(plan: plan, receipt: receipt))
            } else {
                printAuditPruneResult(plan: plan, receipt: receipt)
            }
        default:
            throw CLIError.message("audit requires summary or prune")
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
                try SafeFileOutput.write(report.markdown, to: url)
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
            throw CLIError.message("recovery restore is manual Finder work because macOS cannot bind the final path move to the verified held item. Reveal the holding record and move it manually after review.")
        default:
            throw CLIError.message("Unknown recovery subcommand: \(subcommand)")
        }
    }
}

func printAuditSummary(_ summary: AuditStoreSummary) {
    print("Ryddi audit store")
    print("Root: \(summary.rootPath)")
    print("Known audit files: \(summary.totalKnownFileCount) (\(ByteFormat.string(summary.totalKnownBytes)))")
    print("Unknown files: \(summary.unknownFileCount)")
    print("Symlinks skipped: \(summary.symlinkCount)")
    if summary.items.isEmpty {
        print("No known audit JSON files found.")
        return
    }
    print("\nKnown audit kinds")
    for item in summary.items {
        let latest = item.latestModifiedAt.map { $0.formatted() } ?? "unknown"
        print("- \(item.kind): \(item.fileCount) file(s), \(ByteFormat.string(item.totalBytes)), latest \(latest)")
    }
}

func printAuditPruneResult(plan: AuditPrunePlan, receipt: AuditPruneReceipt) {
    print("Ryddi audit retention preview")
    print("Root: \(plan.rootPath)")
    print("Policy: older than \(plan.policy.olderThanDays) days, keep \(plan.policy.keepRecent) recent known files")
    print("Candidates: \(plan.candidateCount) (\(ByteFormat.string(plan.candidateBytes)))")
    print("Automatic deletion: disabled")
    print("Unknown files skipped: \(plan.skippedUnknownPaths.count)")
    print("Symlinks skipped: \(plan.skippedSymlinkPaths.count)")
    if receipt.dryRun {
        print("\nManual review only. Ryddi does not delete audit JSON; review candidates in Finder.")
    }
    if !plan.candidates.isEmpty {
        print("\nCandidates")
        for candidate in plan.candidates.prefix(20) {
            let date = candidate.modifiedAt.map { $0.formatted() } ?? "unknown date"
            print("- \(candidate.kind): \(ByteFormat.string(candidate.bytes)) \(date) \(candidate.path)")
        }
        if plan.candidates.count > 20 {
            print("- ... \(plan.candidates.count - 20) more")
        }
    }
    if !receipt.errors.isEmpty {
        print("\nErrors")
        for error in receipt.errors {
            print("- \(error)")
        }
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
    print("Automatic restores: disabled; holding records require manual Finder recovery.")

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
