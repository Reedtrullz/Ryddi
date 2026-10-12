import Foundation
import ReclaimerCore
import Darwin

struct AuditCLI {
    func run() {
        let args = Array(CommandLine.arguments.dropFirst())
        guard let first = args.first, first == "audit" else {
            print("Usage: ryddi audit <path> [--json] [--auto]")
            exit(64)
        }
        let flags = Set(args.dropFirst())
        let isJSON = flags.contains("--json")
        let isAuto = flags.contains("--auto")
        let pathArg = args.dropFirst().first { !$0.hasPrefix("-") }
        guard let path = pathArg else {
            print("Usage: ryddi audit <path> [--json] [--auto]")
            exit(64)
        }

        do {
            let scanner = DeepAuditScanner()
            let result = try scanner.scanWithCoverage(path: path)
            let recs = result.recommendations
            let total = recs.reduce(0) { $0 + $1.reclaimableBytes }
            let report = AuditReport(
                scannedPaths: [path],
                totalBytes: total,
                bloatBytes: total,
                reclaimableBytes: total,
                recommendations: recs,
                coverage: [result.coverage]
            )

            if isJSON {
                let data = AuditReportFormatter.json(report: report)
                print(String(data: data, encoding: .utf8) ?? "")
                exit(report.hasCompleteCoverage ? 0 : 2)
            }

            print(AuditReportFormatter.plainText(report: report))
            guard report.hasCompleteCoverage else {
                if isAuto { print("Automatic cleanup refused because scan coverage is incomplete.") }
                exit(2)
            }

            if isAuto {
                let safe = recs.filter { $0.safetyScore >= 0.8 && $0.action == .moveToTrash }
                if safe.isEmpty {
                    print("No high-safety items to reclaim.")
                    return
                }
                print("\nAuto-reclaim \(safe.count) high-safety items (\(ByteCountFormatter().string(fromByteCount: safe.reduce(0) { $0 + $1.reclaimableBytes })))")
                print("Confirm (y/N): ", terminator: "")
                guard let line = readLine()?.lowercased(), line == "y" || line == "yes" else {
                    print("Cancelled.")
                    return
                }
                var failed: [String] = []
                let validator = CleanupValidator()
                for rec in safe {
                    do {
                        let url = try validator.validate(rec, scanRoot: path)
                        guard let identity = rec.identity else { throw CleanupValidationError.missingIdentity }
                        try SessionTrashMover().moveValidatedFileToTrash(source: url, scannedIdentity: identity)
                    } catch {
                        failed.append("\(rec.path): \(error.localizedDescription)")
                    }
                }
                if !failed.isEmpty {
                    print("Warning: failed to move \(failed.count) item(s) to Trash.")
                    for failure in failed { print(failure) }
                }
                print("Done.")
            }
        } catch {
            print("Audit failed: \(error)")
            exit(1)
        }
    }
}
