import Foundation
import ReclaimerCore

extension DashboardModel {
    func exportEvidenceReport(pathStyle: ReportPathStyle = .full, redactUserText: Bool = false) async {
        guard let currentOverview = overview, !findings.isEmpty else {
            error = "Run a scan before exporting an evidence report."
            return
        }

        let activityID = activities.begin(.auditLoad, message: "Exporting evidence report")
        defer { activities.finish(.auditLoad, id: activityID) }
        do {
            let currentFindings = findings
            let currentScopes = scanScopes
            let currentPolicy = userPathPolicy
            let url = try await Task.detached {
                let report = EvidenceReportBuilder.build(
                    overview: currentOverview,
                    findings: currentFindings,
                    scopes: currentScopes,
                    diskStatus: DiskStatusReader().snapshot(),
                    userPathPolicy: currentPolicy,
                    privacy: ReportPrivacyOptions(pathStyle: pathStyle, redactUserText: redactUserText)
                )
                return try ReportStore().save(report: report)
            }.value
            lastReportExportURL = url
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func exportPlanReport(_ plan: ReclaimPlan, pathStyle: ReportPathStyle = .full) async {
        let activityID = activities.begin(.auditLoad, message: "Exporting plan report")
        defer { activities.finish(.auditLoad, id: activityID) }
        do {
            let url = try await Task.detached {
                let report = ReclaimPlanReportBuilder.build(
                    plan: plan,
                    privacy: ReportPrivacyOptions(pathStyle: pathStyle)
                )
                return try ReportStore().save(planReport: report)
            }.value
            lastPlanReportExportURL = url
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func exportReceiptReport(_ receipt: ExecutionReceipt, pathStyle: ReportPathStyle = .full) async {
        let activityID = activities.begin(.auditLoad, message: "Exporting receipt report")
        defer { activities.finish(.auditLoad, id: activityID) }
        do {
            let url = try await Task.detached {
                let report = ExecutionReceiptReportBuilder.build(
                    receipt: receipt,
                    privacy: ReportPrivacyOptions(pathStyle: pathStyle)
                )
                return try ReportStore().save(executionReceiptReport: report)
            }.value
            lastReceiptReportExportURL = url
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func exportGrowthReport(pathStyle: ReportPathStyle = .full) async {
        guard scanSnapshots.count >= 2 else {
            error = "Run at least two scans before exporting a growth report."
            return
        }

        let activityID = activities.begin(.auditLoad, message: "Exporting growth report")
        defer { activities.finish(.auditLoad, id: activityID) }
        do {
            let current = scanSnapshots[0]
            let previous = scanSnapshots[1]
            let url = try await Task.detached {
                let report = GrowthReportBuilder.build(
                    previous: previous,
                    current: current,
                    group: .category,
                    privacy: ReportPrivacyOptions(pathStyle: pathStyle)
                )
                return try ReportStore().save(growthReport: report)
            }.value
            lastGrowthReportExportURL = url
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func exportArchiveReview(mode: LargeOldReviewMode = .all, sort: TopOffenderSort = .allocated, pathStyle: ReportPathStyle = .full) async {
        guard !findings.isEmpty else {
            error = "Run a scan before exporting an archive review."
            return
        }

        let activityID = activities.begin(.auditLoad, message: "Exporting archive review")
        defer { activities.finish(.auditLoad, id: activityID) }
        do {
            let currentFindings = findings
            let url = try await Task.detached {
                let report = ArchiveReviewBuilder.build(
                    findings: currentFindings,
                    mode: mode,
                    sort: sort,
                    limit: 80,
                    privacy: ReportPrivacyOptions(pathStyle: pathStyle)
                )
                return try ReportStore().save(archiveReviewReport: report)
            }.value
            lastArchiveReviewExportURL = url
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func exportUserPathPolicy() async {
        let activityID = activities.begin(.auditLoad, message: "Exporting path policy")
        defer { activities.finish(.auditLoad, id: activityID) }
        do {
            let url = try await Task.detached {
                let document = UserPathPolicyStore().exportDocument()
                return try ReportStore().save(userPathPolicyDocument: document)
            }.value
            lastPolicyExportURL = url
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func exportSavedScopeSets() async {
        let activityID = activities.begin(.auditLoad, message: "Exporting saved scope sets")
        defer { activities.finish(.auditLoad, id: activityID) }
        do {
            let url = try await Task.detached {
                let document = try SavedScopeSetStore().exportDocument()
                return try ReportStore().save(savedScopeSetDocument: document)
            }.value
            lastScopeSetExportURL = url
            error = nil
        } catch {
            lastScopeSetExportURL = nil
            self.error = error.localizedDescription
        }
    }

    func exportDiagnosticSummary() async {
        let activityID = activities.begin(.auditLoad, message: "Exporting diagnostics")
        defer { activities.finish(.auditLoad, id: activityID) }
        do {
            let metadata = diagnostics.metadata(
                appVersion: actionCenterAppVersion,
                preset: actionCenterPreset,
                stage: currentScanSession?.stage,
                findingCount: findings.count,
                permissionReport: permissionReport
            )
            lastDiagnosticExportURL = try await Task.detached {
                try ReportStore().save(diagnosticMetadata: metadata)
            }.value
            error = nil
        } catch {
            diagnostics.record(error: .exportFailed)
            self.error = error.localizedDescription
        }
    }

}
