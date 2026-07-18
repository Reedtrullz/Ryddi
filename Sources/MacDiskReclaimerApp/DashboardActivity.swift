import Foundation

enum DashboardActivityKind: Hashable, Sendable {
    case scan
    case cleanup
    case auditLoad
    case review
    case remote
}

enum CloudFootprintOperation: Equatable, Sendable {
    case discovering
    case analyzing(provider: String)
    case cancelling

    var message: String {
        switch self {
        case .discovering:
            "Discovering local cloud folders…"
        case .analyzing(let provider):
            "Reviewing \(provider) metadata without opening files…"
        case .cancelling:
            "Stopping cloud review…"
        }
    }
}

enum ScanResultFeedbackStyle: Equatable, Sendable {
    case success
    case warning
    case stopped
}

struct ScanResultFeedback: Equatable, Sendable {
    let style: ScanResultFeedbackStyle
    let title: String
    let detail: String
}

enum DashboardActivityState: Equatable, Sendable {
    case idle
    case running(id: UUID, kind: DashboardActivityKind, progress: Double?, message: String)
    case cancelling(id: UUID, kind: DashboardActivityKind)
    case failed(kind: DashboardActivityKind, message: String)

    var id: UUID? {
        switch self {
        case .running(let id, _, _, _), .cancelling(let id, _): id
        case .idle, .failed: nil
        }
    }

    var message: String {
        switch self {
        case .running(_, _, _, let message), .failed(_, let message): message
        case .cancelling(_, let kind): "Cancelling \(kind.label.lowercased())"
        case .idle: ""
        }
    }
}

struct DashboardActivityRegistry: Sendable {
    private var states = [DashboardActivityKind: DashboardActivityState]()

    mutating func begin(_ kind: DashboardActivityKind, message: String) -> UUID {
        let id = UUID()
        states[kind] = .running(id: id, kind: kind, progress: nil, message: message)
        return id
    }

    mutating func update(
        _ kind: DashboardActivityKind,
        id: UUID,
        progress: Double?,
        message: String
    ) {
        guard case .running(let currentID, let currentKind, _, _) = state(for: kind),
              currentID == id,
              currentKind == kind else { return }
        states[kind] = .running(id: id, kind: kind, progress: progress, message: message)
    }

    mutating func markCancelling(_ kind: DashboardActivityKind) {
        guard case .running(let id, let currentKind, _, _) = state(for: kind),
              currentKind == kind else { return }
        states[kind] = .cancelling(id: id, kind: currentKind)
    }

    mutating func finish(_ kind: DashboardActivityKind, id: UUID) {
        guard state(for: kind).id == id else { return }
        states[kind] = .idle
    }

    mutating func fail(_ kind: DashboardActivityKind, id: UUID, message: String) {
        guard state(for: kind).id == id else { return }
        states[kind] = .failed(kind: kind, message: message)
    }

    func state(for kind: DashboardActivityKind) -> DashboardActivityState {
        states[kind] ?? .idle
    }

    func isRunning(_ kind: DashboardActivityKind) -> Bool {
        switch state(for: kind) {
        case .running, .cancelling: true
        case .idle, .failed: false
        }
    }

    func isCurrent(_ kind: DashboardActivityKind, id: UUID) -> Bool {
        state(for: kind).id == id
    }
}

private extension DashboardActivityKind {
    var label: String {
        switch self {
        case .scan: "Scan"
        case .cleanup: "Cleanup"
        case .auditLoad: "Audit load"
        case .review: "Review"
        case .remote: "Remote activity"
        }
    }
}
