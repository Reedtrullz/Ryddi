import Foundation
import ReclaimerCore

@main
struct ReclaimerAgent {
    static func main() throws {
        guard !CommandLine.arguments.contains(where: forbiddenArgument) else {
            throw NSError(
                domain: "Ryddi.Agent",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Ryddi scheduled agent is report-only and refuses execute, --yes, prune, reset, uninstall, and native run arguments."]
            )
        }
        let scanner = try FileScanner()
        let findings = scanner.scan(scopes: DefaultScopes.scopes(for: .developer), options: ScanOptions(includeOpenFileStatus: true))
        let plan = PlanBuilder(openFileChecker: NoOpenFilesChecker()).buildPlan(from: findings, mode: .autoSafeOnly)
        let store = AuditStore()
        let planURL = try store.save(plan: plan)
        print("Ryddi agent wrote report plan: \(planURL.path)")
        print("Expected safe reclaim: \(ByteFormat.string(plan.expectedImmediateReclaim))")
    }

    private static func forbiddenArgument(_ argument: String) -> Bool {
        ["execute", "--yes", "prune", "reset", "uninstall"].contains(argument)
    }
}
