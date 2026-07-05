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
        let findings = scanner.scan(scopes: options.scopes(), options: options.scanOptions(includeOpenFiles: options.includeOpenFiles))
        if options.json {
            printJSON(findings)
        } else {
            printFindings(findings)
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
        let receipt = ReclaimerExecutor(openFileChecker: options.noLsof ? NoOpenFilesChecker() : LsofOpenFileChecker())
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
              scan [--json] [--path PATH ...] [--min-size BYTES] [--max-depth N] [--include-open-files]
              plan [--json] [--path PATH ...] [--review-all] [--save-audit]
              explain PATH [--json]
              execute --dry-run [--json] [--path PATH ...] [--save-audit]
              execute --yes [--path PATH ...] [--review-all] [--save-audit]
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
    var includeOpenFiles: Bool { args.contains("--include-open-files") }
    var noLsof: Bool { args.contains("--no-lsof") }
    var hour: Int { Int(value(after: "--hour") ?? "") ?? 9 }
    var minute: Int { Int(value(after: "--minute") ?? "") ?? 30 }

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

    func scopes() -> [ScanScope] {
        let paths = values(after: "--path")
        if !paths.isEmpty {
            return paths.map { ScanScope(name: URL(fileURLWithPath: $0).lastPathComponent, root: URL(fileURLWithPath: $0)) }
        }
        return DefaultScopes.developerAgentBloat()
    }

    func scanOptions(includeOpenFiles: Bool) -> ScanOptions {
        let minSize = Int64(value(after: "--min-size") ?? "") ?? 1_000_000
        let maxDepth = Int(value(after: "--max-depth") ?? "") ?? 2
        return ScanOptions(
            minimumFindingSize: minSize,
            maximumFindingDepth: maxDepth,
            measurementDepth: maxDepth + 4,
            includeOpenFileStatus: includeOpenFiles
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

func printJSON<T: Encodable>(_ value: T) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    let data = try! encoder.encode(value)
    print(String(data: data, encoding: .utf8)!)
}

func printFindings(_ findings: [Finding]) {
    for finding in findings.prefix(80) {
        print("\(ByteFormat.string(finding.allocatedSize).padding(toLength: 10, withPad: " ", startingAt: 0)) \(finding.safetyClass.label.padding(toLength: 22, withPad: " ", startingAt: 0)) \(finding.path)")
    }
    if findings.count > 80 {
        print("... \(findings.count - 80) more findings")
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
