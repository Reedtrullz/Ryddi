import Foundation

public struct ExecutionReconciliation: Hashable, Sendable {
    public let remainingFindings: [Finding]
    public let completedFindingIDs: Set<Finding.ID>
    public let completedPaths: [String]
    public let skippedPaths: [String]
    public let requiresVerificationScan: Bool

    public init(
        remainingFindings: [Finding],
        completedFindingIDs: Set<Finding.ID>,
        completedPaths: [String],
        skippedPaths: [String],
        requiresVerificationScan: Bool
    ) {
        self.remainingFindings = remainingFindings
        self.completedFindingIDs = completedFindingIDs
        self.completedPaths = completedPaths
        self.skippedPaths = skippedPaths
        self.requiresVerificationScan = requiresVerificationScan
    }
}

public enum ExecutionReconciler {
    public static func reconcile(
        findings: [Finding],
        receipt: ExecutionReceipt
    ) -> ExecutionReconciliation {
        let completedPaths = uniqueStandardizedPaths(
            receipt.actions.filter { $0.status == "done" }.map(\.path)
        )
        let skippedPaths = uniqueStandardizedPaths(
            receipt.actions.filter { $0.status != "done" }.map(\.path)
        )
        let completedComponents = completedPaths.map(pathComponents)
        var completedFindingIDs = Set<Finding.ID>()
        var remainingFindings: [Finding] = []

        for finding in findings {
            let findingComponents = pathComponents(finding.path)
            if completedComponents.contains(where: { isSameOrDescendant(findingComponents, of: $0) }) {
                completedFindingIDs.insert(finding.id)
            } else {
                remainingFindings.append(finding)
            }
        }

        return ExecutionReconciliation(
            remainingFindings: remainingFindings,
            completedFindingIDs: completedFindingIDs,
            completedPaths: completedPaths,
            skippedPaths: skippedPaths,
            requiresVerificationScan: true
        )
    }

    private static func uniqueStandardizedPaths(_ paths: [String]) -> [String] {
        var seen = Set<String>()
        return paths.compactMap { path in
            let standardized = canonicalURL(path).path
            return seen.insert(standardized).inserted ? standardized : nil
        }
    }

    private static func pathComponents(_ path: String) -> [String] {
        canonicalURL(path).pathComponents
    }

    private static func canonicalURL(_ path: String) -> URL {
        var existingAncestor = URL(fileURLWithPath: path).standardizedFileURL
        var missingComponents: [String] = []

        while !FileManager.default.fileExists(atPath: existingAncestor.path) {
            let parent = existingAncestor.deletingLastPathComponent()
            guard parent.path != existingAncestor.path else { break }
            missingComponents.append(existingAncestor.lastPathComponent)
            existingAncestor = parent
        }

        var resolved = existingAncestor.resolvingSymlinksInPath().standardizedFileURL
        for component in missingComponents.reversed() {
            resolved.appendPathComponent(component)
        }
        return resolved.standardizedFileURL
    }

    private static func isSameOrDescendant(_ path: [String], of ancestor: [String]) -> Bool {
        guard path.count >= ancestor.count else { return false }
        return zip(path, ancestor).allSatisfy { $0 == $1 }
    }
}
