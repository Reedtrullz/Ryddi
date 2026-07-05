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
        case "history":
            try history(args: args)
        case "duplicates":
            try duplicates(args: args)
        case "apps":
            try apps(args: args)
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
        case "explain":
            try explain(args: args)
        case "execute":
            try execute(args: args)
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
        let scanner = try FileScanner(openFileChecker: options.noLsof ? NoOpenFilesChecker() : LsofOpenFileChecker())
        let findings = scanner.scan(
            scopes: options.scopes(includeUnavailable: options.includeMissingScopes),
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
        let scopes = options.scopes(includeUnavailable: true)
        let scanner = try FileScanner(openFileChecker: options.noLsof ? NoOpenFilesChecker() : LsofOpenFileChecker())
        let findings = scanner.scan(scopes: scopes, options: options.scanOptions(includeOpenFiles: options.includeOpenFiles))
        let overview = FindingAnalytics.overview(findings: findings, scopes: scopes, topLimit: options.limit)
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

    static func history(args: [String]) throws {
        guard let subcommand = args.first else {
            throw CLIError.message("history requires record, list, or diff")
        }
        let options = ParsedOptions(Array(args.dropFirst()))
        let store = ScanHistoryStore()
        switch subcommand {
        case "record":
            let scopes = options.scopes(includeUnavailable: true)
            let scanner = try FileScanner(openFileChecker: options.noLsof ? NoOpenFilesChecker() : LsofOpenFileChecker())
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
            .scan(scopes: options.scopes(), options: options.duplicateOptions)
        if options.json {
            printJSON(report)
        } else {
            printDuplicateReview(report, options: options)
        }
    }

    static func apps(args: [String]) throws {
        let options = ParsedOptions(args)
        let report = try AppReviewScanner().scan(options: options.appReviewOptions)
        if options.json {
            printJSON(report)
        } else {
            printAppReview(report, options: options)
        }
    }

    static func native(args: [String]) throws {
        let options = ParsedOptions(args)
        let scanner = try FileScanner(openFileChecker: options.noLsof ? NoOpenFilesChecker() : LsofOpenFileChecker())
        let findings = scanner.scan(scopes: options.scopes(), options: options.scanOptions(includeOpenFiles: false))
        let report = NativeToolGuidance.report(for: findings, ruleVersion: try RuleEngine.bundled().version)
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
            throw CLIError.message("policy requires list, protect, exclude, or remove")
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
        default:
            throw CLIError.message("Unknown policy subcommand: \(subcommand)")
        }
    }

    static func plan(args: [String]) throws {
        let options = ParsedOptions(args)
        let scanner = try FileScanner(openFileChecker: options.noLsof ? NoOpenFilesChecker() : LsofOpenFileChecker())
        let findings = scanner.scan(scopes: options.scopes(), options: options.scanOptions(includeOpenFiles: false))
        let builder = PlanBuilder(openFileChecker: options.noLsof ? NoOpenFilesChecker() : LsofOpenFileChecker())
        let plan = builder.buildPlan(from: findings, mode: options.reviewAll ? .reviewAll : .autoSafeOnly)
        if options.saveAudit {
            let url = try AuditStore().save(plan: plan)
            FileHandle.standardError.write(Data("saved plan: \(url.path)\n".utf8))
        }
        if options.json {
            printJSON(plan)
        } else {
            printPlan(plan)
        }
    }

    static func explain(args: [String]) throws {
        guard let path = args.first, !path.hasPrefix("-") else {
            throw CLIError.message("explain requires a path")
        }
        let options = ParsedOptions(args)
        let scanner = try FileScanner(openFileChecker: options.noLsof ? NoOpenFilesChecker() : LsofOpenFileChecker())
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
        let scanner = try FileScanner(openFileChecker: options.noLsof ? NoOpenFilesChecker() : LsofOpenFileChecker())
        let findings = scanner.scan(scopes: options.scopes(), options: options.scanOptions(includeOpenFiles: false))
        let builder = PlanBuilder(openFileChecker: options.noLsof ? NoOpenFilesChecker() : LsofOpenFileChecker())
        let plan = builder.buildPlan(from: findings, mode: options.reviewAll ? .reviewAll : .autoSafeOnly)
        let receipt = ReclaimerExecutor(
            openFileChecker: options.noLsof ? NoOpenFilesChecker() : LsofOpenFileChecker(),
            configuration: ExecutorConfiguration(userPathPolicy: options.userPathPolicy)
        )
            .execute(
                plan: plan,
                mode: options.dryRun ? .dryRun : .perform,
                ruleVersion: try RuleEngine.bundled().version,
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
              scan [--json] [--path PATH ...] [--min-size BYTES] [--max-depth N] [--include-open-files]
                   [--sort size|logical|age|risk|category|scope] [--group category|safety|scope]
                   [--review large|old|all] [--limit N] [--include-missing-scopes] [--ignore-user-policy]
              overview [--json] [--path PATH ...] [--limit N] [--save-history] [--ignore-user-policy]
              history record [--json] [--path PATH ...] [--limit N]
              history list [--json] [--limit N]
              history diff [--json] [--group category|safety|scope] [--limit N]
              duplicates [--json] --path PATH ... [--min-size BYTES] [--max-depth N] [--limit N]
                         [--max-files N] [--include-preserve] [--skip-hidden] [--show-excluded]
              apps [--json] [--path APP_ROOT ...] [--home HOME] [--min-size BYTES] [--limit N]
                   [--include-system-apps] [--no-orphans] [--show-excluded]
              native [--json] [--path PATH ...] [--limit N] [--save-audit]
              containers [--json] [--limit N] [--timeout SECONDS] [--save-audit]
              policy list [--json]
              policy protect PATH [--reason TEXT]
              policy exclude PATH [--reason TEXT]
              policy remove PATH [--kind protect|exclude]
              plan [--json] [--path PATH ...] [--review-all] [--save-audit] [--ignore-user-policy]
              explain PATH [--json]
              execute --dry-run [--json] [--path PATH ...] [--save-audit] [--ignore-user-policy]
              execute --yes [--path PATH ...] [--review-all] [--save-audit] [--ignore-user-policy]
              archive [--json] [--path PATH ...]   # review/compression-oriented plan only
              schedule install [--hour H] [--minute M] [--load]
              schedule uninstall [--unload]
              schedule status
              holding list [--json]
              holding restore ID [--to PATH]
              holding expire [--older-than-days N] [--yes]

            Defaults scan known developer/agent bloat locations. Execution is dry-run unless --yes is supplied.
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
    var includeOpenFiles: Bool { args.contains("--include-open-files") }
    var includeMissingScopes: Bool { args.contains("--include-missing-scopes") }
    var noLsof: Bool { args.contains("--no-lsof") }
    var hasPath: Bool { !values(after: "--path").isEmpty }
    var includePreserve: Bool { args.contains("--include-preserve") }
    var showExcluded: Bool { args.contains("--show-excluded") }
    var includeSystemApps: Bool { args.contains("--include-system-apps") }
    var includeOrphans: Bool { !args.contains("--no-orphans") }
    var ignoreUserPolicy: Bool { args.contains("--ignore-user-policy") }
    var hour: Int { Int(value(after: "--hour") ?? "") ?? 9 }
    var minute: Int { Int(value(after: "--minute") ?? "") ?? 30 }
    var limit: Int { max(1, Int(value(after: "--limit") ?? "") ?? 80) }
    var sort: String { value(after: "--sort") ?? "size" }
    var group: String? { value(after: "--group") }
    var growthGroup: GrowthGroup { GrowthGroup(rawValue: group ?? "category") ?? .category }
    var review: String { value(after: "--review") ?? "all" }
    var largeThreshold: Int64 { Int64(value(after: "--large-threshold") ?? "") ?? 5_000_000_000 }
    var oldDays: Int { Int(value(after: "--old-days") ?? "") ?? 180 }
    var maxFilesToHash: Int { max(1, Int(value(after: "--max-files") ?? "") ?? 5_000) }
    var reason: String? { value(after: "--reason") }
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

    func scopes(includeUnavailable: Bool = false) -> [ScanScope] {
        let paths = values(after: "--path")
        if !paths.isEmpty {
            return paths.map { ScanScope(name: URL(fileURLWithPath: $0).lastPathComponent, root: URL(fileURLWithPath: $0)) }
        }
        return DefaultScopes.developerAgentBloat(includeUnavailable: includeUnavailable)
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

    print("\nVisual map nodes")
    for node in overview.mapNodes.prefix(10) {
        let reclaim = node.isReclaimable ? "reclaimable" : "review"
        print("- \(pad(node.name, 22)) \(pad(ByteFormat.string(node.allocatedSize), 10)) \(reclaim)")
    }

    print("\nTop offenders")
    printFindingRows(overview.topFindings)

    print("\nAPFS/accounting notes")
    for note in overview.accountingNotes {
        print("- \(note)")
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

func printPlan(_ plan: ReclaimPlan) {
    print("Plan \(plan.id)")
    print("Expected immediate reclaim: \(ByteFormat.string(plan.expectedImmediateReclaim))")
    for line in plan.dryRunSummary {
        print(line)
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

func printReceipt(_ receipt: ExecutionReceipt) {
    print("Receipt \(receipt.id)")
    for action in receipt.actions {
        print("[\(action.status)] \(action.action.label): \(action.path) - \(action.message)")
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
