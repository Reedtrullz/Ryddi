import Foundation
import ReclaimerCore

extension ReclaimerCLI {
    static func remote(args: [String]) throws {
        guard let subcommand = args.first else {
            throw CLIError.message("remote requires targets, probe, scan, dogfood, native, plan, or history")
        }
        let rest = Array(args.dropFirst())
        switch subcommand {
        case "execute", "prune", "reset":
            throw CLIError.message("Remote \(subcommand) is not available in v1; Remote Targets are report-only and never run destructive cleanup.")
        case "targets":
            try remoteTargets(args: rest)
        case "probe":
            try remoteProbe(args: rest)
        case "scan":
            try remoteScan(args: rest, mode: "scan")
        case "dogfood":
            try remoteDogfood(args: rest)
        case "native":
            try remoteNative(args: rest)
        case "plan":
            try remoteScan(args: rest, mode: "plan")
        case "history":
            try remoteHistory(args: rest)
        default:
            throw CLIError.message("Unknown remote command: \(subcommand)")
        }
    }

    static func remoteTargets(args: [String]) throws {
        let subcommand = args.first ?? "list"
        let options = ParsedOptions(Array(args.dropFirst()))
        guard subcommand == "list" else {
            throw CLIError.message("remote targets supports only: list")
        }
        let targets = RemoteTargetResolver().targets()
        if options.json {
            printJSON(targets)
        } else {
            printRemoteTargets(targets)
        }
    }

    static func remoteProbe(args: [String]) throws {
        let options = ParsedOptions(args)
        guard let targetInput = remoteTargetArgument(args) else {
            throw CLIError.message("remote probe requires TARGET")
        }
        let target = try RemoteTargetResolver().resolve(targetInput)
        let report = RemoteProbeBuilder(target: target, timeout: options.timeoutSeconds).probe()
        guard report.commands.contains(where: { $0.exitCode == 0 }) else {
            throw CLIError.message("Remote probe could not reach \(targetInput) with read-only SSH commands; no cleanup was executed and no password prompt was requested.")
        }
        if options.saveAudit {
            let url = try AuditStore().save(remoteProbeReport: report)
            FileHandle.standardError.write(Data("saved remote probe report: \(url.path)\n".utf8))
        }
        if options.json {
            printJSON(report)
        } else {
            printRemoteProbeReport(report)
        }
    }

    static func remoteScan(args: [String], mode: String) throws {
        let options = ParsedOptions(args)
        try options.validateReportPrivacyOptions()
        guard let targetInput = remoteTargetArgument(args) else {
            throw CLIError.message("remote \(mode) requires TARGET")
        }
        let target = try RemoteTargetResolver().resolve(targetInput)
        let report = RemoteScanBuilder(target: target, timeout: options.timeoutSeconds).scan(
            preset: try options.remoteScanPreset(),
            privacy: options.reportPrivacy
        )
        if options.saveAudit, report.coverage.level == .unreachable {
            throw CLIError.message("Remote \(mode) for \(targetInput) is unreachable; no audit record was saved. Use --output FILE to export an explicit degraded report.")
        }
        if options.saveAudit {
            let url = try AuditStore().save(remoteScanReport: report)
            FileHandle.standardError.write(Data("saved remote scan report: \(url.path)\n".utf8))
        }
        if let output = options.outputPath {
            let markdown = RemoteReportBuilder.build(report: report, privacy: options.reportPrivacy).markdown
            let url = URL(fileURLWithPath: output).standardizedFileURL
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try markdown.write(to: url, atomically: true, encoding: .utf8)
            FileHandle.standardError.write(Data("wrote remote report: \(url.path)\n".utf8))
        }
        if options.json {
            printJSON(report)
        } else if options.outputPath == nil {
            printRemoteScanReport(report, title: mode == "plan" ? "Remote Report-Only Plan" : "Remote Scan Report")
        }
    }

    static func remoteDogfood(args: [String]) throws {
        let options = ParsedOptions(args)
        try options.validateReportPrivacyOptions()
        guard let targetInput = remoteTargetArgument(args) else {
            throw CLIError.message("remote dogfood requires TARGET")
        }

        let store = AuditStore()
        let fromAudit = args.contains("--from-audit")
        let probe: RemoteProbeReport?
        let scan: RemoteScanReport

        if fromAudit {
            let queryTarget = RemoteTargetReference(input: targetInput)
            let latestScan: RemoteScanReport
            do {
                guard let selectedScan = try store.selectedRemoteScanReport(forAuditQuery: queryTarget) else {
                    throw CLIError.message("remote dogfood --from-audit found no saved remote scan for \(targetInput)")
                }
                latestScan = selectedScan
            } catch let error as AuditStore.RemoteAuditQueryError {
                throw CLIError.message("remote dogfood --from-audit \(error.localizedDescription)")
            }
            scan = latestScan
            probe = store.latestRemoteProbeReport(forConcreteTarget: scan.target)
        } else {
            let target = try RemoteTargetResolver().resolve(targetInput)
            let liveProbe = RemoteProbeBuilder(target: target, timeout: options.timeoutSeconds).probe()
            guard liveProbe.commands.contains(where: { $0.exitCode == 0 }) else {
                throw CLIError.message("Remote dogfood could not reach \(targetInput) with read-only SSH commands; no cleanup was executed and no password prompt was requested.")
            }
            probe = liveProbe
            scan = RemoteScanBuilder(target: target, timeout: options.timeoutSeconds).scan(
                preset: try options.remoteScanPreset(),
                privacy: options.reportPrivacy
            )
        }

        let growth = store.latestPreviousRemoteScanReport(forConcreteTarget: scan.target, excludingReportID: scan.id).map {
            RemoteGrowthReportBuilder.build(previous: $0, current: scan, privacy: options.reportPrivacy)
        }
        let report = RemoteDogfoodReportBuilder.build(
            probe: probe,
            scan: scan,
            growth: growth,
            privacy: options.reportPrivacy
        )

        if options.saveAudit {
            let url = try store.save(remoteDogfoodReport: report)
            FileHandle.standardError.write(Data("saved remote dogfood report: \(url.path)\n".utf8))
        }
        if let output = options.outputPath {
            let url = URL(fileURLWithPath: output).standardizedFileURL
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try report.markdown.write(to: url, atomically: true, encoding: .utf8)
            FileHandle.standardError.write(Data("wrote remote dogfood report: \(url.path)\n".utf8))
        }
        if options.json {
            printJSON(report)
        } else if options.outputPath == nil {
            print(report.markdown)
        }
    }

    static func remoteNative(args: [String]) throws {
        let options = ParsedOptions(args)
        guard let targetInput = remoteTargetArgument(args) else {
            throw CLIError.message("remote native requires TARGET")
        }
        let target = try RemoteTargetResolver().resolve(targetInput)
        let report = RemoteScanBuilder(target: target, timeout: options.timeoutSeconds).scan()
        if options.json {
            printJSON(report.nativeGuidance)
        } else {
            printRemoteNativeGuidance(report.nativeGuidance, target: report.target)
        }
    }

    static func remoteHistory(args: [String]) throws {
        let subcommand = args.first?.hasPrefix("--") == true ? "list" : (args.first ?? "list")
        let optionArgs = args.first?.hasPrefix("--") == true ? args : Array(args.dropFirst())
        let options = ParsedOptions(optionArgs)
        let store = AuditStore()
        switch subcommand {
        case "list":
            let reports = store.recentRemoteScanReports(limit: options.limit)
            if options.json {
                printJSON(reports)
            } else {
                printRemoteScanHistory(reports)
            }
        case "diff", "report":
            try options.validateReportPrivacyOptions()
            let pair = try remoteHistoryPair(options: options, store: store)
            let report = RemoteGrowthReportBuilder.build(
                previous: pair.previous,
                current: pair.current,
                limit: options.limit,
                privacy: options.reportPrivacy
            )
            if subcommand == "report", let output = options.outputPath {
                let url = URL(fileURLWithPath: output).standardizedFileURL
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try report.markdown.write(to: url, atomically: true, encoding: .utf8)
                FileHandle.standardError.write(Data("wrote remote growth report: \(url.path)\n".utf8))
            }
            if options.json {
                printJSON(report)
            } else if subcommand == "report", options.outputPath == nil {
                print(report.markdown)
            } else if subcommand == "diff" {
                printRemoteGrowthDeltas(report)
            }
        default:
            throw CLIError.message("remote history requires list, diff, or report")
        }
    }

    static func remoteHistoryPair(options: ParsedOptions, store: AuditStore) throws -> (previous: RemoteScanReport, current: RemoteScanReport) {
        if options.currentSnapshotID != nil || options.previousSnapshotID != nil {
            guard let currentID = options.currentSnapshotID, let previousID = options.previousSnapshotID else {
                throw CLIError.message("remote history requires both --current-id and --previous-id when comparing explicit remote scans")
            }
            guard let current = store.remoteScanReport(id: currentID) else {
                throw CLIError.message("No saved remote scan report found for --current-id \(currentID)")
            }
            guard let previous = store.remoteScanReport(id: previousID) else {
                throw CLIError.message("No saved remote scan report found for --previous-id \(previousID)")
            }
            return (previous, current)
        }
        let reports = store.recentRemoteScanReports(limit: Int.max)
            .filter { $0.coverage.level != .unreachable }
            .prefix(2)
        guard reports.count == 2 else {
            throw CLIError.message("remote history requires at least two saved reachable remote scan reports")
        }
        return (reports[1], reports[0])
    }

    static func remoteTargetArgument(_ args: [String]) -> String? {
        var skipNext = false
        let valueFlags = Set(["--timeout", "--preset", "--path-style", "--output"])
        for arg in args {
            if skipNext {
                skipNext = false
                continue
            }
            if valueFlags.contains(arg) {
                skipNext = true
                continue
            }
            if arg.hasPrefix("--") {
                continue
            }
            return arg
        }
        return nil
    }
}

func printRemoteTargets(_ targets: [RemoteTargetReference]) {
    print("Ryddi remote targets")
    if targets.isEmpty {
        print("No non-wildcard SSH aliases found in ~/.ssh/config.")
        return
    }
    for target in targets {
        print("- \(target.input)")
    }
}

func printRemoteProbeReport(_ report: RemoteProbeReport) {
    print("Remote probe \(report.id)")
    print("Generated: \(report.createdAt.formatted())")
    print("Target: \(report.target.alias ?? report.target.input)")
    print("Host: \(report.target.resolvedHost ?? "unknown")")
    print("User: \(report.target.resolvedUser ?? "unknown")")
    print("Host key: \(report.target.knownHostsState)")
    print("OS: \(report.osSummary ?? "unknown")")
    print("Home: \(report.homeDirectory ?? "unknown")")
    if let sudo = report.sudoNonInteractive {
        print("Non-interactive sudo: \(sudo ? "available" : "not available")")
    }
    if !report.availableTools.isEmpty {
        print("Tools: \(report.availableTools.joined(separator: ", "))")
    }
    print("\nRead-only commands")
    for command in report.commands {
        let code = command.exitCode.map(String.init) ?? "blocked"
        print("- [exit \(code)] \(command.displayCommand)")
        if let stderr = command.stderrPreview.first {
            print("  \(stderr)")
        }
    }
    print("\nNon-claims")
    for note in report.nonClaims {
        print("- \(note)")
    }
}

func printRemoteScanReport(_ report: RemoteScanReport, title: String) {
    print("\(title) \(report.id)")
    print("Generated: \(report.createdAt.formatted())")
    print("Target: \(report.target.alias ?? report.target.input)")
    print("Host: \(report.target.resolvedHost ?? "unknown")")
    print("Preset: \(report.preset.rawValue)")
    print("Coverage: \(report.coverage.level.rawValue)")
    print(report.coverage.explanation)
    if !report.continuityWarnings.isEmpty {
        print("\nTarget continuity warnings")
        for warning in report.continuityWarnings {
            print("- \(warning.field): \(warning.previousValue) -> \(warning.currentValue) (\(warning.severity))")
        }
    }
    if !report.diskFilesystems.isEmpty {
        print("\nFilesystems")
        for filesystem in report.diskFilesystems {
            let capacity = filesystem.capacityPercent.map { "\($0)%" } ?? "-"
            let used = filesystem.usedBytes.map(ByteFormat.string) ?? "-"
            print("- \(filesystem.mount): \(used) used, \(capacity)")
        }
    }
    if !report.findings.isEmpty {
        print("\nFindings")
        print("\(pad("Bucket", 22)) \(pad("Size", 12)) \(pad("Safety", 22)) Next action")
        for finding in report.findings.sorted(by: { ($0.allocatedBytes ?? 0) > ($1.allocatedBytes ?? 0) }).prefix(40) {
            let size = finding.allocatedBytes.map(ByteFormat.string) ?? "-"
            print("\(pad(finding.bucket, 22)) \(pad(size, 12)) \(pad(finding.safetyClass.label, 22)) \(finding.recommendedNextAction.label)")
            print("  \(finding.displayPath)")
        }
    } else {
        if report.coverage.level == .unreachable {
            print("\nNo remote findings produced because the target was unreachable or all evidence commands failed.")
        } else {
            print("\nNo remote findings produced.")
        }
    }
    if !report.nativeGuidance.isEmpty {
        print("\nNative guidance")
        for item in report.nativeGuidance {
            print("- \(item.title): \(item.command)")
            print("  \(item.summary)")
        }
    }
    print("\nRead-only commands")
    for command in report.commands.prefix(40) {
        let code = command.exitCode.map(String.init) ?? "blocked"
        print("- [exit \(code)] \(command.displayCommand)")
        if let stderr = command.stderrPreview.first {
            print("  \(stderr)")
        }
    }
    print("\nNon-claims")
    for note in report.nonClaims {
        print("- \(note)")
    }
}

func printRemoteNativeGuidance(_ guidance: [RemoteNativeGuidance], target: RemoteTargetReference) {
    print("Remote native guidance")
    print("Target: \(target.alias ?? target.input)")
    if guidance.isEmpty {
        print("No remote native guidance generated.")
    } else {
        for item in guidance {
            print("\n\(item.title)")
            print("Command: \(item.command)")
            print("Risk: \(item.risk)")
            print(item.summary)
        }
    }
    print("\nNon-claims")
    for note in RemoteScanReport.defaultNonClaims {
        print("- \(note)")
    }
}

func printRemoteScanHistory(_ reports: [RemoteScanReport]) {
    print("Ryddi remote scan history")
    if reports.isEmpty {
        print("No saved remote scan reports found.")
        return
    }
    print("\(pad("Created", 22)) \(pad("Findings", 10)) \(pad("Bytes", 12)) Target")
    for report in reports {
        let bytes = report.findings.reduce(Int64(0)) { $0 + ($1.allocatedBytes ?? 0) }
        let target = report.target.alias ?? report.target.input
        let host = report.target.resolvedHost.map { " (\($0))" } ?? ""
        print("\(pad(report.createdAt.formatted(), 22)) \(pad(String(report.findings.count), 10)) \(pad(ByteFormat.string(bytes), 12)) \(target)\(host)")
        print("  id: \(report.id)")
    }
    print("\nNon-claims")
    print("- Remote history reads saved local audit records only; it does not connect to servers.")
    print("- A saved remote scan report can contain private host metadata and paths; review before sharing.")
}

func printRemoteGrowthDeltas(_ report: RemoteGrowthReport) {
    print("Remote growth diff \(report.id)")
    print("Target: \(report.target.alias ?? report.target.input)")
    print("Previous: \(report.previousScanID) at \(report.previousCreatedAt.formatted())")
    print("Current: \(report.currentScanID) at \(report.currentCreatedAt.formatted())")
    print("Delta: \(signedBytes(report.deltaAllocatedBytes)) across saved finding bytes")

    print("\nLargest bucket deltas")
    if report.bucketDeltas.isEmpty {
        print("No remote bucket deltas recorded.")
    } else {
        print("\(pad("Delta", 12)) \(pad("Current", 12)) \(pad("Previous", 12)) Bucket")
        for delta in report.bucketDeltas {
            print("\(pad(signedBytes(delta.deltaAllocatedBytes), 12)) \(pad(ByteFormat.string(delta.currentAllocatedBytes), 12)) \(pad(ByteFormat.string(delta.previousAllocatedBytes), 12)) \(delta.bucket)")
        }
    }

    print("\nLargest path deltas")
    if report.findingDeltas.isEmpty {
        print("No remote path deltas recorded.")
    } else {
        print("\(pad("Delta", 12)) \(pad("Current", 12)) \(pad("Safety", 22)) Path")
        for delta in report.findingDeltas {
            print("\(pad(signedBytes(delta.deltaAllocatedBytes), 12)) \(pad(ByteFormat.string(delta.currentAllocatedBytes), 12)) \(pad(delta.currentSafetyClass?.label ?? "-", 22)) \(delta.displayPath)")
        }
    }

    print("\nNon-claims")
    for note in report.nonClaims {
        print("- \(note)")
    }
}

func signedBytes(_ bytes: Int64) -> String {
    bytes > 0 ? "+\(ByteFormat.string(bytes))" : ByteFormat.string(bytes)
}
