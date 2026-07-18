import Foundation
import ReclaimerCore

enum HomeSuggestionRoute: Equatable {
    case cleanup
    case storageReview(StorageReviewDestination)
    case explore
    case informational

    static func resolve(
        suggestion: HomeSuggestion,
        findings: [Finding]
    ) -> HomeSuggestionRoute {
        switch suggestion.kind.intent {
        case .reviewSafeCleanup:
            return .cleanup
        case .useNativeMaintenance:
            let containsContainerStorage = findings.contains { finding in
                guard suggestion.findingIDs.contains(finding.id) else { return false }
                let path = finding.path.lowercased()
                return path.contains("colima") || path.contains("docker")
            }
            return containsContainerStorage ? .storageReview(.containers) : .explore
        case .resolveCondition, .inspectPersonalFiles:
            return .explore
        case .informational:
            return .informational
        }
    }
}
