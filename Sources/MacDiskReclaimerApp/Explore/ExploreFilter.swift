import Foundation
import ReclaimerCore

enum ExploreMinimumSize: Int64, CaseIterable, Identifiable {
    case any = 0
    case hundredMegabytes = 104_857_600
    case oneGigabyte = 1_073_741_824
    case fiveGigabytes = 5_368_709_120

    var id: Int64 { rawValue }

    var label: String {
        switch self {
        case .any: "Any size"
        case .hundredMegabytes: "100 MB+"
        case .oneGigabyte: "1 GB+"
        case .fiveGigabytes: "5 GB+"
        }
    }
}

struct ExploreFilter: Equatable {
    var searchText = ""
    var category: GuidedMapCategory?
    var minimumSize: ExploreMinimumSize = .any
    var evidenceState: GuidedMapMeasurementState?

    func matchingIDs(in snapshot: GuidedMapSnapshot) -> Set<String> {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return Set(snapshot.nodes.filter { node in
            guard node.id != snapshot.rootID else { return true }
            guard node.allocatedBytes >= minimumSize.rawValue else { return false }
            if let category, node.category != category { return false }
            if let evidenceState, node.measurementState != evidenceState { return false }
            if !query.isEmpty {
                let haystack = "\(node.displayName) \(node.path ?? "")"
                guard haystack.localizedCaseInsensitiveContains(query) else { return false }
            }
            return true
        }.map(\.id))
    }
}
