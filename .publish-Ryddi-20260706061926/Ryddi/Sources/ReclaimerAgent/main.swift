import Foundation
import ReclaimerCore

@main
struct ReclaimerAgent {
    static func main() throws {
        let scanner = try FileScanner()
        let findings = scanner.scan(scopes: DefaultScopes.scopes(for: .developer), options: ScanOptions(includeOpenFileStatus: true))
        let plan = PlanBuilder(openFileChecker: NoOpenFilesChecker()).buildPlan(from: findings, mode: .autoSafeOnly)
        let store = AuditStore()
        let planURL = try store.save(plan: plan)
        print("Ryddi agent wrote report plan: \(planURL.path)")
        print("Expected safe reclaim: \(ByteFormat.string(plan.expectedImmediateReclaim))")
    }
}
