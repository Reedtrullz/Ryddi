import Foundation
import ReclaimerCore

struct AuditCLI {
    func run() {
        let args = Array(CommandLine.arguments.dropFirst())
        guard let first = args.first, first == "audit" else {
            print("Usage: ryddi audit <path> [--json] [--auto]")
            return
        }
        let flags = Set(args.dropFirst())
        let isJSON = flags.contains("--json")
        let isAuto = flags.contains("--auto")
        let pathArg = args.dropFirst().first { !$0.hasPrefix("-") }
        guard let path = pathArg else {
            print("Usage: ryddi audit <path> [--json] [--auto]")
            return
        }

        do {
            let scanner = DeepAuditScanner()
            let recs = try scanner.scan(path: path)
            let total = recs.reduce(0) { $0 + $1.reclaimableBytes }
            let report = AuditReport(
                scannedPaths: [path],
                totalBytes: total,
                bloatBytes: total,
                reclaimableBytes: total,
                recommendations: recs
            )

            if isJSON {
                let data = AuditReportFormatter.json(report: report)
                print(String(data: data, encoding: .utf8) ?? "")
                return
            }

            print(AuditReportFormatter.plainText(report: report))

            if isAuto {
                let safe = recs.filter { $0.safetyScore >= 0.8 }
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
                for rec in safe {
                    try? FileManager.default.trashItem(at: URL(fileURLWithPath: rec.path), resultingItemURL: nil)
                }
                print("Done.")
            }
        } catch {
            print("Audit failed: \(error)")
        }
    }
}
