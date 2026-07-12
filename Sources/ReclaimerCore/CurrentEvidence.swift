import Foundation

public enum CurrentEvidenceRejection: String, Codable, CaseIterable, Hashable, Sendable {
    case missingSession
    case sessionInvalidated
    case planDigestMismatch
    case dryRunReceiptIDMismatch
    case executionReceiptIDMismatch
}

public struct CurrentEvidenceSnapshot: Hashable, Sendable {
    public let session: ScanSession?
    public let plan: ReclaimPlan?
    public let dryRunReceipt: ExecutionReceipt?
    public let executionReceipt: ExecutionReceipt?
    public let rejectedEvidence: [CurrentEvidenceRejection]

    public init(
        session: ScanSession?,
        plan: ReclaimPlan?,
        dryRunReceipt: ExecutionReceipt?,
        executionReceipt: ExecutionReceipt?,
        rejectedEvidence: [CurrentEvidenceRejection]
    ) {
        self.session = session
        self.plan = plan
        self.dryRunReceipt = dryRunReceipt
        self.executionReceipt = executionReceipt
        self.rejectedEvidence = rejectedEvidence
    }
}

public enum CurrentEvidenceResolver {
    public static func resolve(
        session: ScanSession?,
        plan: ReclaimPlan?,
        dryRunReceipt: ExecutionReceipt?,
        executionReceipt: ExecutionReceipt?
    ) -> CurrentEvidenceSnapshot {
        guard let session else {
            return CurrentEvidenceSnapshot(
                session: nil,
                plan: nil,
                dryRunReceipt: nil,
                executionReceipt: nil,
                rejectedEvidence: hasEvidence(plan, dryRunReceipt, executionReceipt) ? [.missingSession] : []
            )
        }

        guard session.stage != .invalidated, session.invalidationReasons.isEmpty else {
            return CurrentEvidenceSnapshot(
                session: session,
                plan: nil,
                dryRunReceipt: nil,
                executionReceipt: nil,
                rejectedEvidence: hasEvidence(plan, dryRunReceipt, executionReceipt) ? [.sessionInvalidated] : []
            )
        }

        var rejections: [CurrentEvidenceRejection] = []
        let currentPlan: ReclaimPlan?
        if let plan {
            if session.planDigest == plan.id {
                currentPlan = plan
            } else {
                currentPlan = nil
                rejections.append(.planDigestMismatch)
            }
        } else {
            currentPlan = nil
        }

        let currentDryRunReceipt: ExecutionReceipt?
        if let dryRunReceipt {
            if session.dryRunReceiptID == dryRunReceipt.id {
                currentDryRunReceipt = dryRunReceipt
            } else {
                currentDryRunReceipt = nil
                rejections.append(.dryRunReceiptIDMismatch)
            }
        } else {
            currentDryRunReceipt = nil
        }

        let currentExecutionReceipt: ExecutionReceipt?
        if let executionReceipt {
            if session.executionReceiptID == executionReceipt.id {
                currentExecutionReceipt = executionReceipt
            } else {
                currentExecutionReceipt = nil
                rejections.append(.executionReceiptIDMismatch)
            }
        } else {
            currentExecutionReceipt = nil
        }

        return CurrentEvidenceSnapshot(
            session: session,
            plan: currentPlan,
            dryRunReceipt: currentDryRunReceipt,
            executionReceipt: currentExecutionReceipt,
            rejectedEvidence: rejections
        )
    }

    private static func hasEvidence(
        _ plan: ReclaimPlan?,
        _ dryRunReceipt: ExecutionReceipt?,
        _ executionReceipt: ExecutionReceipt?
    ) -> Bool {
        plan != nil || dryRunReceipt != nil || executionReceipt != nil
    }
}
