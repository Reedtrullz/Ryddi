import SwiftUI
import ReclaimerCore

@MainActor
@Observable
final class RyddiAppModel {
    let dashboard: DashboardModel

    init(dashboard: DashboardModel = DashboardModel()) {
        self.dashboard = dashboard
    }

    var menuTitle: String {
        guard let freeBytes = dashboard.diskStatus.displayFreeBytes else {
            return "Ryddi"
        }
        return "Ryddi \(ByteFormat.string(freeBytes))"
    }

    var symbolName: String {
        switch dashboard.diskStatus.pressure {
        case .healthy: "externaldrive.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .critical: "xmark.octagon.fill"
        case .unknown: "questionmark.circle.fill"
        }
    }

    func scanFromMenuBar() async {
        await dashboard.scan()
    }
}
