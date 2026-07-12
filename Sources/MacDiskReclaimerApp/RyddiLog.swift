import Foundation
import OSLog
import ReclaimerCore

enum RyddiLog {
    static let scan = Logger(subsystem: "com.reidar.ryddi", category: "scan")
    static let workflow = Logger(subsystem: "com.reidar.ryddi", category: "workflow")
    static let window = Logger(subsystem: "com.reidar.ryddi", category: "window")
    static let e2e = Logger(subsystem: "com.reidar.ryddi", category: "e2e")
    static let signposter = OSSignposter(subsystem: "com.reidar.ryddi", category: "performance")
}

struct RyddiDiagnosticSpan {
    let operation: DiagnosticOperation
    let startedAt: ContinuousClock.Instant
    let signpostState: OSSignpostIntervalState
}

@MainActor
final class RyddiDiagnosticRecorder {
    private let clock = ContinuousClock()
    private var durations: [DiagnosticOperation: Int] = [:]
    private var eventCounts: [DiagnosticEvent: Int] = [:]
    private(set) var lastErrorKind: DiagnosticErrorKind?

    func begin(_ operation: DiagnosticOperation) -> RyddiDiagnosticSpan {
        let state = RyddiLog.signposter.beginInterval(signpostName(operation))
        return RyddiDiagnosticSpan(operation: operation, startedAt: clock.now, signpostState: state)
    }

    func end(_ span: RyddiDiagnosticSpan) {
        let elapsed = span.startedAt.duration(to: clock.now)
        let milliseconds = max(0, Int(elapsed.components.seconds * 1_000) + Int(elapsed.components.attoseconds / 1_000_000_000_000_000))
        durations[span.operation] = milliseconds
        RyddiLog.signposter.endInterval(signpostName(span.operation), span.signpostState)
        RyddiLog.workflow.info("operation=\(span.operation.rawValue, privacy: .public) duration_ms=\(milliseconds, privacy: .public)")
    }

    func record(_ event: DiagnosticEvent) {
        eventCounts[event, default: 0] += 1
        RyddiLog.workflow.info("event=\(event.rawValue, privacy: .public) count=\(self.eventCounts[event, default: 0], privacy: .public)")
    }

    func record(error kind: DiagnosticErrorKind) {
        lastErrorKind = kind
        RyddiLog.workflow.error("error_kind=\(kind.rawValue, privacy: .public)")
    }

    func metadata(
        appVersion: String,
        preset: ScanScopePreset,
        stage: ScanSessionStage?,
        findingCount: Int,
        permissionReport: PermissionAdvisorReport
    ) -> DiagnosticMetadata {
        DiagnosticMetadataBuilder.build(
            appVersion: appVersion,
            preset: preset,
            stage: stage,
            findingCount: findingCount,
            readableScopeCount: permissionReport.readableCount,
            totalScopeCount: permissionReport.totalCount,
            durations: durations,
            eventCounts: eventCounts,
            lastErrorKind: lastErrorKind
        )
    }

    private func signpostName(_ operation: DiagnosticOperation) -> StaticString {
        switch operation {
        case .scan: "Scan"
        case .presentation: "Presentation Snapshot"
        case .plan: "Plan"
        case .dryRun: "Dry Run"
        case .trashExecution: "Trash Execution"
        case .navigation: "Navigation"
        }
    }
}
